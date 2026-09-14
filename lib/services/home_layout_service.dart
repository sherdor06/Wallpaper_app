import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The two ways the Home tab can present the catalog.
enum HomeLayout {
  /// Curated: a wallpaper of the day, a few themed rows, then everything.
  editorial,

  /// Browse: one card per category, tap into the one you want.
  collections,
}

/// Remembers which Home layout the user chose, the way [ThemeService]
/// remembers the theme — a one-line file, read before `runApp`, so the tab
/// opens the way it was left rather than flashing the default first.
class HomeLayoutService extends ChangeNotifier {
  HomeLayoutService._();
  static final HomeLayoutService instance = HomeLayoutService._();

  static const _fileName = 'home_layout.txt';

  HomeLayout _layout = HomeLayout.editorial;
  File? _file;

  HomeLayout get layout => _layout;

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        final name = (await file.readAsString()).trim();
        _layout = HomeLayout.values.firstWhere(
          (l) => l.name == name,
          orElse: () => HomeLayout.editorial,
        );
      }
    } catch (_) {
      // Unreadable store — the default is a fine place to start.
    }
  }

  Future<void> setLayout(HomeLayout layout) async {
    if (layout == _layout) return;
    _layout = layout;
    notifyListeners();
    try {
      await _file?.writeAsString(layout.name);
    } catch (_) {
      // Kept for this session at least.
    }
  }
}
