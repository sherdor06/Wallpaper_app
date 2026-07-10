import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Manages favorite wallpapers and persists them to a local JSON file.
///
/// No new package needed — it writes `favorites.json` to the app's internal
/// directory via `path_provider` (already a dependency). On change it calls
/// `notifyListeners()`, so the UI updates immediately when a heart is tapped.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  static const _fileName = 'favorites.json';
  final Set<String> _ids = <String>{};
  File? _file;

  /// Favorite wallpaper ids (read-only).
  Set<String> get favorites => Set.unmodifiable(_ids);

  bool isFavorite(String id) => _ids.contains(id);

  /// Loads favorites from disk. Called before `runApp`.
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
      // If loading fails, continue with an empty list.
    }
  }

  /// Adds to or removes from favorites.
  Future<void> toggle(String id) async {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode(_ids.toList()));
    } catch (_) {
      // If saving fails, it's not critical (still kept in memory).
    }
  }
}
