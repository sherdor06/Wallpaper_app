import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tracks which premium (4K) wallpapers the user has unlocked by watching a
/// rewarded ad, and persists them to a local JSON file so an unlock is permanent
/// (no need to watch the video again).
///
/// Mirrors [FavoritesService]: no new package — writes `unlocked.json` to the
/// app's internal directory via `path_provider`. Calls `notifyListeners()` on
/// change so the detail page can drop the lock hint immediately.
class UnlockService extends ChangeNotifier {
  UnlockService._();
  static final UnlockService instance = UnlockService._();

  static const _fileName = 'unlocked.json';
  final Set<String> _ids = <String>{};
  File? _file;

  bool isUnlocked(String id) => _ids.contains(id);

  /// Loads unlocked ids from disk. Called before `runApp`.
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
      // If loading fails, continue with an empty set.
    }
  }

  /// Marks [id] as unlocked (idempotent) and persists.
  Future<void> unlock(String id) async {
    if (_ids.add(id)) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode(_ids.toList()));
    } catch (_) {
      // If saving fails, it's not critical (still kept in memory this session).
    }
  }
}
