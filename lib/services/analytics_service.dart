import 'dart:async' show unawaited;

import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import '../config/app_config.dart';

/// Thin wrapper around analytics: Firebase Analytics everywhere, plus Yandex
/// AppMetrica when configured (strong in the CIS region + free attribution).
/// A navigator observer provides automatic `screen_view` tracking (Firebase).
///
/// All log calls are fire-and-forget and never throw, so they are safe to call
/// from anywhere without awaiting.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Add to `MaterialApp.navigatorObservers` for automatic screen views.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// Sends one event to Firebase and (when a key is set) Yandex AppMetrica.
  /// Both calls are fire-and-forget.
  static void _log(String name, Map<String, Object> params) {
    _quietly(_analytics.logEvent(name: name, parameters: params));
    if (AppConfig.hasAppMetrica) {
      _quietly(AppMetrica.reportEventWithMap(name, params));
    }
  }

  /// Fire-and-forget that means it. An unawaited future that fails lands in
  /// `PlatformDispatcher.onError`, which main.dart reports to Crashlytics as a
  /// *fatal* crash — so a hiccup on an analytics channel would have shown up
  /// as the app crashing when nothing had.
  static void _quietly(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  static void logWallpaperView(String id, {String? category}) {
    _log('wallpaper_view', <String, Object>{
      'wallpaper_id': id,
      if (category != null && category.isNotEmpty) 'category': category,
    });
  }

  static void logWallpaperSet(String id, {String? target}) {
    _log('wallpaper_set', <String, Object>{
      'wallpaper_id': id,
      if (target != null) 'target': target,
    });
  }

  static void logWallpaperDownload(String id) {
    _log('wallpaper_download', <String, Object>{'wallpaper_id': id});
  }

  /// A share sheet was opened for a wallpaper. Logged on open, not on send —
  /// the platform sheet never tells the app whether anything was actually sent,
  /// so this counts intent, and the arrivals show up as app-link opens.
  static void logShare(String id) {
    _log('wallpaper_share', <String, Object>{'wallpaper_id': id});
  }

  static void logRewardedUnlock(String id) {
    _log('rewarded_unlock', <String, Object>{'wallpaper_id': id});
  }

  static void logAdImpression(String type) {
    _log('ad_impression', <String, Object>{'ad_type': type});
  }
}
