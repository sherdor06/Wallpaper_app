import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../ui/detail_page.dart';
import '../ui/home/collection_page.dart';
import 'update_service.dart';

/// Opens the wallpaper (`/w/<id>`) or collection (`/c/<id>`) a link points at.
///
/// Links are plain https URLs on the CDN's domain, not a custom scheme: with
/// the app installed Android App Links opens them here, and without it they
/// are a web page that leads to the store. Only `/w/` is in the intent filter
/// and on the site; `/c/` arrives from notifications alone.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  // Must match the intent filter in AndroidManifest.xml and `_redirects`.
  static const _host = 'wallpapers-cdn.pages.dev';
  static const _wallpaperPrefix = '/w/';
  static const _collectionPrefix = '/c/';

  final AppLinks _appLinks = AppLinks();
  // Never cancelled: links can arrive whenever the app is alive.
  // ignore: cancel_subscriptions
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigator;

  // A notification tapped on a cold start is read before `runApp`, when there
  // is no navigator yet. [init] replays it.
  Uri? _pending;

  static Uri shareUrlFor(String wallpaperId) =>
      Uri.parse('https://$_host$_wallpaperPrefix$wallpaperId');

  // Strict about host and prefix: anything else is not a link we published.
  static String? _idAfter(Uri uri, String prefix) {
    if (uri.host != _host || !uri.path.startsWith(prefix)) return null;
    final id = uri.path.substring(prefix.length);
    return id.isEmpty ? null : Uri.decodeComponent(id);
  }

  /// Called after `runApp`, so the link that launched the app is not missed.
  Future<void> init(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(handleUri(pending));
    _sub ??= _appLinks.uriLinkStream.listen(handleUri, onError: (_) {});
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await handleUri(initial);
    } catch (_) {}
  }

  /// Also the entry point for links in notifications ([PushService]).
  Future<void> handleUri(Uri uri) async {
    final wallpaperId = _idAfter(uri, _wallpaperPrefix);
    final collectionId = _idAfter(uri, _collectionPrefix)
        ?.replaceAll('/', '')
        .toLowerCase();
    if (wallpaperId == null && collectionId == null) return;
    // A build below the supported floor shows only the update page.
    if (UpdateService.instance.need == UpdateNeed.required) return;
    if (_navigator == null) {
      _pending = uri;
      return;
    }

    // Awaits a catalog that is still loading on a cold start.
    final Catalog catalog;
    try {
      catalog = await WallpaperRepository.instance.fetchCatalog();
    } catch (_) {
      return;
    }

    final Widget? page;
    if (collectionId != null) {
      final collection = catalog.collection(collectionId);
      page = collection == null ? null : CollectionPage(collection: collection);
    } else {
      final wallpaper = catalog.wallpapers
          .where((w) => w.id == wallpaperId)
          .firstOrNull;
      page = wallpaper == null ? null : DetailPage(wallpaper: wallpaper);
    }

    // An id that is gone or mistyped leaves the user where they are.
    final nav = _navigator?.currentState;
    if (page == null || nav == null) return;
    await nav.push(MaterialPageRoute(builder: (_) => page!));
  }
}
