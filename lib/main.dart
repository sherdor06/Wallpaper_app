import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'services/ad_service.dart';
import 'services/favorites_service.dart';
import 'services/unlock_service.dart';
import 'services/wallpaper_service.dart';
import 'ui/splash_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bound the in-memory image cache so decoding many 4K wallpapers can't OOM.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // ~100 MB
  // Remove leftover temp download files from earlier runs (fire-and-forget).
  WallpaperService.instance.cleanTemp();
  // Pre-warm the liquid-glass shaders (prevents first-frame jank).
  // enablePerformanceMonitor: false — otherwise it draws a colored border overlay.
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  // Initialize AdMob and gather UMP (GDPR) consent before any ads load.
  await AdService.instance.init();
  // Load favorites + unlocked (4K) wallpapers from disk.
  await FavoritesService.instance.init();
  await UnlockService.instance.init();
  // Wrap provides the glass theme/scope to all GlassXxx widgets.
  runApp(LiquidGlassWidgets.wrap(child: const WallpaperApp()));
}

class WallpaperApp extends StatelessWidget {
  const WallpaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wallpapers',
      theme: _darkTheme(),
      home: const SplashGate(),
    );
  }

  ThemeData _darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C5CE7),
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0E0E12),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E0E12),
        foregroundColor: Colors.white,
        centerTitle: false,
      ),
    );
  }
}
