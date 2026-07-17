import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Holds the user's theme choice (system / light / dark) and persists it to a
/// small local file, mirroring [FavoritesService]. `MaterialApp` listens to it
/// (via `ListenableBuilder`) so switching rebuilds the whole app.
class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _fileName = 'theme.txt';
  ThemeMode _mode = ThemeMode.system;
  File? _file;

  ThemeMode get mode => _mode;

  /// Loads the saved theme mode from disk. Called before `runApp`.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        _mode = _parse(await file.readAsString());
      }
    } catch (_) {
      // Fall back to system on any error.
    }
  }

  /// Sets and persists the theme mode.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _file?.writeAsString(name(mode));
    } catch (_) {}
  }

  static ThemeMode _parse(String s) {
    switch (s.trim()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String name(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
