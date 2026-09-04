import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps an ordered history of the wallpapers the user has applied or saved.
///
/// Mirrors [FavoritesService]: a small JSON file in the app's internal
/// directory, `notifyListeners()` on change. Unlike favorites this is a *list* —
/// order matters (most recent first) and re-applying a wallpaper moves it back
/// to the front instead of duplicating it.
class HistoryService extends ChangeNotifier {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  static const _fileName = 'history.json';

  /// Upper bound so the file (and the Archive grid) can't grow without limit.
  static const _maxEntries = 120;

  final List<String> _ids = <String>[];
  File? _file;

  /// Applied wallpaper ids, most recent first (read-only).
  List<String> get ids => List.unmodifiable(_ids);

  bool get isEmpty => _ids.isEmpty;

  /// Loads the history from disk. Called before `runApp`.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is List) {
          _ids.addAll(data.map((e) => e.toString()));
        }
      }
    } catch (_) {
      // If loading fails, continue with an empty history.
    }
  }

  /// Records [id] as the most recently used wallpaper.
  Future<void> add(String id) async {
    _ids
      ..remove(id) // re-applying moves it to the front rather than duplicating
      ..insert(0, id);
    if (_ids.length > _maxEntries) {
      _ids.removeRange(_maxEntries, _ids.length);
    }
    notifyListeners();
    await _save();
  }

  /// Removes the given ids — the Archive screen's multi-select delete.
  Future<void> removeAll(Iterable<String> ids) async {
    final gone = ids.toSet();
    if (gone.isEmpty) return;
    final before = _ids.length;
    _ids.removeWhere(gone.contains);
    if (_ids.length == before) return;
    notifyListeners();
    await _save();
  }

  /// Empties the history (the Archive screen's "Clear" action).
  Future<void> clear() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode(_ids));
    } catch (_) {
      // Not critical — the list is still correct in memory.
    }
  }
}
