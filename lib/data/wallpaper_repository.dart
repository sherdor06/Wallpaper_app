import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/collection.dart';
import '../models/wallpaper.dart';

/// Catalog result: categories + wallpapers.
class Catalog {
  final List<WallpaperCategory> categories;
  final List<Wallpaper> wallpapers;

  Catalog({required this.categories, required this.wallpapers});

  static final empty = Catalog(categories: const [], wallpapers: const []);

  /// Wallpapers grouped by category id, built once per catalog. Every home
  /// surface asks for a category's wallpapers, and a catalog of a couple of
  /// thousand filtered a dozen times per build added up.
  late final Map<String, List<Wallpaper>> _byCategory = () {
    final out = <String, List<Wallpaper>>{};
    for (final w in wallpapers) {
      (out[w.category] ??= []).add(w);
    }
    return out;
  }();

  late final Map<String, WallpaperCategory> _meta = {
    for (final c in categories) c.id: c,
  };

  /// The collection for [id], or null when the catalog has no wallpaper in
  /// it. Name and tagline come from the catalog's category entry; a category
  /// the config does not describe gets its id capitalised.
  Collection? collection(String id) {
    final items = _byCategory[id];
    if (items == null) return null;
    final meta = _meta[id];
    return Collection(
      id: id,
      name: meta?.name ?? categoryLabel(id),
      tagline: meta?.tagline,
      items: items,
    );
  }

  /// Every collection big enough to be a destination (see
  /// [Collection.isDestination]), fullest first.
  List<Collection> destinations() => [
    for (final id in _byCategory.keys)
      if (collection(id) case final c? when c.isDestination) c,
  ]..sort((a, b) => b.items.length.compareTo(a.items.length));
}

/// Source of wallpapers.
///
/// Data flow: `catalog.json` from Cloudflare R2/CDN -> disk cache (offline) ->
/// bundled sample (assets/catalog.sample.json). It falls back in that order, so
/// the app still works offline or before the CDN is configured.
class WallpaperRepository {
  WallpaperRepository._();
  static final WallpaperRepository instance = WallpaperRepository._();

  static const _bundledAsset = 'assets/catalog.sample.json';
  static const _cacheFileName = 'catalog_cache.json';

  final Dio _dio = Dio(
    BaseOptions(
      // Without these a stalled connection holds the gallery on its loader
      // for as long as the OS takes to give up — over a minute — while a
      // perfectly good copy sits in the disk cache.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  Catalog? _cache;

  /// Returns the catalog. When [forceRefresh] is `true`, the cache is bypassed
  /// and the catalog is re-fetched from the CDN (used by pull-to-refresh).
  Future<Catalog> fetchCatalog({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;

    // Each source counts only if it parses. A captive-portal login page, or
    // an error page served with a 200, is not a catalog — cached, it would
    // leave the app empty on every later offline start. So the network copy
    // is parsed first and written to disk only once it has.
    Catalog? catalog;
    if (AppConfig.hasRemoteCatalog) {
      try {
        // On pull-to-refresh, bust the CDN cache so deletions/additions appear
        // immediately (r2.dev otherwise caches catalog.json for ~5 minutes).
        final url = forceRefresh
            ? '${AppConfig.catalogUrl}?t=${DateTime.now().millisecondsSinceEpoch}'
            : AppConfig.catalogUrl;
        final res = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final raw = res.data;
        if (raw != null && raw.isNotEmpty) {
          catalog = _parse(raw);
          await _saveToDisk(raw); // so it works offline next time
        }
      } catch (_) {
        // No network, or a body that is not a catalog: the disk copy follows.
      }
    }
    catalog ??= await _parseFromDisk();

    // If nothing else worked -> bundled sample (so the app isn't empty).
    catalog ??= _parse(await rootBundle.loadString(_bundledAsset));
    _cache = catalog;
    return catalog;
  }

  /// The last good catalog on disk, or null when there is none or it no
  /// longer parses — which a copy saved by an older build, before responses
  /// were checked, may not.
  Future<Catalog?> _parseFromDisk() async {
    final raw = await _readFromDisk();
    if (raw == null || raw.isEmpty) return null;
    try {
      return _parse(raw);
    } catch (_) {
      return null;
    }
  }

  Catalog _parse(String raw) {
    final decoded = jsonDecode(raw);
    final base = AppConfig.cdnBaseUrl;

    // The root can be either a Map ({categories, wallpapers}) or a bare List.
    final List wallpapersJson;
    final List categoriesJson;
    if (decoded is Map<String, dynamic>) {
      wallpapersJson =
          (decoded['wallpapers'] ?? decoded['items'] ?? []) as List;
      categoriesJson = (decoded['categories'] ?? []) as List;
    } else if (decoded is List) {
      wallpapersJson = decoded;
      categoriesJson = const [];
    } else {
      return Catalog.empty;
    }

    final wallpapers = wallpapersJson
        .whereType<Map<String, dynamic>>()
        .map((e) => Wallpaper.fromJson(e, base: base))
        .toList();

    // iOS can't set live (video) wallpapers — hide them from the whole catalog
    // so users never reach the unsupported "Set live wallpaper" action.
    if (Platform.isIOS) {
      wallpapers.removeWhere((w) => w.isLive);
    }

    // Mix categories so the "All" view isn't grouped. Shuffled once per load
    // (stable while browsing; re-mixed on pull-to-refresh / next launch).
    wallpapers.shuffle();

    var categories = categoriesJson
        .whereType<Map<String, dynamic>>()
        .map(WallpaperCategory.fromJson)
        .toList();

    // If the catalog provides no categories, derive them from the wallpapers.
    if (categories.isEmpty) {
      final ids = <String>{
        for (final w in wallpapers)
          if (w.category.isNotEmpty) w.category,
      };
      categories = [
        for (final id in ids) WallpaperCategory(id: id, name: _titleCase(id)),
      ];
    }

    // On iOS, drop any category left with no wallpapers after removing live ones
    // (e.g. an explicit "live" category coming from the catalog JSON).
    if (Platform.isIOS) {
      final used = {for (final w in wallpapers) w.category};
      categories = categories.where((c) => used.contains(c.id)).toList();
    }

    return Catalog(categories: categories, wallpapers: wallpapers);
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<void> _saveToDisk(String raw) async {
    try {
      await (await _cacheFile()).writeAsString(raw);
    } catch (_) {
      // If the cache can't be written, it's not critical — just skip silently.
    }
  }

  Future<String?> _readFromDisk() async {
    try {
      final file = await _cacheFile();
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
