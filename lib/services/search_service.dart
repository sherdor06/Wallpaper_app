import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';

/// What a query resolved to: the matching wallpapers and the named filters
/// the words turned out to be (a collection, a mood), so the results screen
/// can show "27 results · Girly · Light" rather than just a count.
class SearchResult {
  final List<Wallpaper> items;
  final List<SearchFilter> filters;
  const SearchResult({required this.items, required this.filters});

  static const empty = SearchResult(items: [], filters: []);
}

/// A word in the query that named something the catalog knows.
class SearchFilter {
  final String label;
  final SearchFilterKind kind;

  /// Category id for a collection filter, mood id for a mood filter.
  final String id;
  const SearchFilter({
    required this.label,
    required this.kind,
    required this.id,
  });
}

enum SearchFilterKind { collection, mood }

/// Search over the catalog, plus the short list of recent queries.
///
/// The catalog carries almost no free text — most titles are "Nature 178" —
/// so search is a fast filter, not a text index: words match collection
/// names and taglines, moods, and whatever words the tags do carry. Every
/// word must match something about a wallpaper for it to count.
class SearchService extends ChangeNotifier {
  SearchService._();
  static final SearchService instance = SearchService._();

  static const _fileName = 'search_recent.json';
  static const _maxRecent = 8;

  File? _file;
  final List<String> _recent = [];

  /// Most recent first.
  List<String> get recent => List.unmodifiable(_recent);

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/$_fileName');
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is List) _recent.addAll(data.map((e) => e.toString()));
      }
    } catch (_) {
      // Recents are a convenience; start empty.
    }
  }

  /// Records a query the user actually acted on — submitted or tapped a
  /// result for — not every keystroke.
  Future<void> remember(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _recent.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    _recent.insert(0, q);
    if (_recent.length > _maxRecent) {
      _recent.removeRange(_maxRecent, _recent.length);
    }
    notifyListeners();
    try {
      await _file?.writeAsString(jsonEncode(_recent));
    } catch (_) {}
  }

  Future<void> clearRecent() async {
    _recent.clear();
    notifyListeners();
    try {
      await _file?.writeAsString('[]');
    } catch (_) {}
  }

  /// Resolves [query] against [catalog]. Pure; safe to call on every
  /// keystroke for a catalog of a few thousand.
  static SearchResult search(Catalog catalog, String query) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .where((w) => w.length >= 2)
        .toList();
    if (words.isEmpty) return SearchResult.empty;

    // Which collections and moods each word names, if any.
    final byCategory = <String, WallpaperCategory>{
      for (final c in catalog.categories) c.id: c,
    };
    final filters = <SearchFilter>[];
    final wordCategories = <String, Set<String>>{};
    final wordMoods = <String, Set<String>>{};
    for (final w in words) {
      for (final c in catalog.categories) {
        final hay = '${c.id} ${c.name} ${c.tagline ?? ''}'.toLowerCase();
        if (_hasWord(hay, w)) {
          (wordCategories[w] ??= {}).add(c.id);
          if (!filters.any(
            (f) => f.id == c.id && f.kind == SearchFilterKind.collection,
          )) {
            filters.add(
              SearchFilter(
                label: c.name,
                kind: SearchFilterKind.collection,
                id: c.id,
              ),
            );
          }
        }
      }
      for (final m in kMoodOrder) {
        if (m.startsWith(w) || moodLabel(m).toLowerCase().startsWith(w)) {
          (wordMoods[w] ??= {}).add(m);
          if (!filters.any(
            (f) => f.id == m && f.kind == SearchFilterKind.mood,
          )) {
            filters.add(
              SearchFilter(
                label: moodLabel(m),
                kind: SearchFilterKind.mood,
                id: m,
              ),
            );
          }
        }
      }
    }

    bool matches(Wallpaper wp, String w) {
      if (wordCategories[w]?.contains(wp.category) ?? false) return true;
      if (wp.moods.any((m) => wordMoods[w]?.contains(m) ?? false)) return true;
      if (!wp.isAutoTitled && wp.title.toLowerCase().contains(w)) return true;
      for (final t in wp.tags) {
        if (t.startsWith('©')) continue; // credits are not searchable words
        if (t.toLowerCase().contains(w)) return true;
      }
      // A word that is not a known collection or mood may still be part of
      // one: "aesth" → aesthetic, via the category name prefix.
      final cat = byCategory[wp.category];
      return cat != null && cat.name.toLowerCase().startsWith(w);
    }

    final items = [
      for (final wp in catalog.wallpapers)
        if (words.every((w) => matches(wp, w))) wp,
    ];
    // Only name the filters that actually shaped the result. "girly dark"
    // also matches Space through its tagline ("…the deep dark"), but no
    // Space wallpaper survives the "girly" word, so Space is not a filter.
    final cats = {for (final wp in items) wp.category};
    final moods = {for (final wp in items) ...wp.moods};
    final shown = [
      for (final f in filters)
        if (f.kind == SearchFilterKind.collection
            ? cats.contains(f.id)
            : moods.contains(f.id))
          f,
    ];
    return SearchResult(items: items, filters: shown);
  }

  /// Whole-word-ish match: "cat" hits "cats" and "cat," but not "locate".
  static bool _hasWord(String hay, String word) =>
      RegExp('(^|[^a-z])${RegExp.escape(word)}').hasMatch(hay);
}
