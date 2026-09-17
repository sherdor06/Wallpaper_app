import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'config/app_config.dart';
import 'firebase_options.dart';
import 'services/ad_service.dart';
import 'services/analytics_service.dart';
import 'services/consent_service.dart';
import 'services/deep_link_service.dart';
import 'services/favorites_service.dart';
import 'services/history_service.dart';
import 'services/home_layout_service.dart';
import 'services/search_service.dart';
import 'services/push_service.dart';
import 'services/remote_config_service.dart';
import 'services/theme_service.dart';
import 'services/unlock_service.dart';
import 'services/wallpaper_service.dart';
import 'ui/splash_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge from the first frame, on every Android version — not only
  // where Android 15 forces it. Before this, older Android kept opaque system
  // bars until the first detail page was dismissed and switched the mode, so
  // the same app looked different depending on where the user had been.
  // Every screen already lays out for it: the chrome sits in SafeArea and the
  // grids scroll under the bars. Bar colours come from [_systemBars].
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Firebase must init before any Firebase service (Crashlytics/Analytics/RC).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Route uncaught Flutter framework + async errors to Crashlytics.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  // Yandex AppMetrica — CIS analytics + free install attribution + push. Skipped
  // when no key is provided (--dart-define=APPMETRICA_API_KEY=...). Crash
  // reporting stays OFF so Firebase Crashlytics remains the single crash owner
  // (two native crash handlers would fight over the signal handlers).
  if (AppConfig.hasAppMetrica) {
    try {
      await AppMetrica.activate(
        AppMetricaConfig(
          AppConfig.appMetricaApiKey,
          // Both JVM and native crash reporting off — Firebase Crashlytics is the
          // single crash owner (two native crash handlers would conflict).
          crashReporting: false,
          nativeCrashReporting: false,
          logs: kDebugMode,
        ),
      );
    } catch (_) {
      // Analytics init must never block app startup.
    }
  }
  // Bound the in-memory image cache so decoding many 4K wallpapers can't OOM.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // ~100 MB
  // Remove leftover temp download files from earlier runs (fire-and-forget).
  WallpaperService.instance.cleanTemp();
  // Pre-warm the liquid-glass shaders (prevents first-frame jank). iOS only —
  // Android uses solid variants everywhere, so no shader compilation at all.
  // enablePerformanceMonitor: false — otherwise it draws a colored border overlay.
  if (!Platform.isAndroid) {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  }
  // Remote Config first — AdService reads the ad kill switch / frequency from
  // it, and ConsentService reads the `consent_required` region flag.
  await RemoteConfigService.instance.init();
  // Then the stored consent answer, so [ConsentService.isRequired] is truthful
  // by the time the splash finishes and decides whether to ask.
  await ConsentService.instance.init();
  // Ad init — deliberately NOT awaited. Nothing on screen needs it: the banner
  // awaits [AdService.adsAllowed] itself, and every interstitial/rewarded path
  // is guarded until consent resolves. Awaiting it would put the whole ad stack
  // on the cold-start critical path — and in the EEA it would block startup for
  // as long as the consent dialog is on screen, which it waits for.
  // The navigator is for the simulator stand-in page (debug only); a device
  // build never touches it.
  unawaited(AdService.instance.init(navigator: WallpaperApp.navigatorKey));
  // Load favorites + unlocked (4K) wallpapers + theme choice from disk.
  await FavoritesService.instance.init();
  await HistoryService.instance.init();
  await UnlockService.instance.init();
  await ThemeService.instance.init();
  await HomeLayoutService.instance.init();
  await SearchService.instance.init();
  // After history: PushService reads the applied-wallpaper count to decide
  // whether the permission prompt has been earned yet.
  await PushService.instance.init();
  runApp(const WallpaperApp());
}

class WallpaperApp extends StatefulWidget {
  const WallpaperApp({super.key});

  /// Shared links arrive from outside the widget tree, so the service that
  /// handles them needs a way to push without a BuildContext.
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<WallpaperApp> createState() => _WallpaperAppState();
}

class _WallpaperAppState extends State<WallpaperApp> {
  @override
  void initState() {
    super.initState();
    // After the first frame: a link that launched the app is replayed here, and
    // pushing onto a navigator that has not mounted yet would be dropped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init(WallpaperApp.navigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the user switches the theme mode.
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: WallpaperApp.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Wallpapers',
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: ThemeService.instance.mode,
          navigatorObservers: [AnalyticsService.observer],
          // Glass scope lives here so its brightness follows the *resolved* app
          // theme (not the device OS). iOS only — Android uses no glass widgets,
          // so the whole glass pipeline is skipped there (performance).
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            // Root system-bar style, so screens without an AppBar (home,
            // search, collections) still get bars that match the theme. An
            // AppBar deeper in the tree overrides the status bar for its own
            // page, as it should.
            final content = AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemBars(brightness),
              child: child ?? const SizedBox.shrink(),
            );
            if (Platform.isAndroid) return content;
            return LiquidGlassWidgets.wrap(
              theme: GlassThemeData(brightness: Theme.of(context).brightness),
              child: content,
            );
          },
          home: const SplashGate(),
        );
      },
    );
  }

  /// Transparent system bars with icons that contrast the resolved theme.
  /// Android 15 makes the bars transparent itself; this is what brings older
  /// Android to the same look. The engine applies the colours only below
  /// API 35 (the window calls behind them are deprecated there), so nothing
  /// here reaches a 15+ device.
  static SystemUiOverlayStyle _systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS reads the bar's *background* brightness and picks icons itself.
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C5CE7),
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0E0E12) : const Color(0xFFF5F5FA);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
    );
  }
}
