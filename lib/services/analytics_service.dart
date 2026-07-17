import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper around Firebase Analytics: one app-wide instance, a navigator
/// observer for automatic `screen_view` tracking, and typed helpers for the key
/// funnel events (view → set / download, ad impressions, rewarded unlocks).
///
/// All log calls are fire-and-forget and never throw, so they are safe to call
/// from anywhere without awaiting.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Add to `MaterialApp.navigatorObservers` for automatic screen views.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  static void logWallpaperView(String id, {String? category}) {
    _analytics.logEvent(name: 'wallpaper_view', parameters: <String, Object>{
      'wallpaper_id': id,
      if (category != null && category.isNotEmpty) 'category': category,
    });
  }

  static void logWallpaperSet(String id, {String? target}) {
    _analytics.logEvent(name: 'wallpaper_set', parameters: <String, Object>{
      'wallpaper_id': id,
      if (target != null) 'target': target,
    });
  }

  static void logWallpaperDownload(String id) {
    _analytics.logEvent(
      name: 'wallpaper_download',
      parameters: <String, Object>{'wallpaper_id': id},
    );
  }

  static void logRewardedUnlock(String id) {
    _analytics.logEvent(
      name: 'rewarded_unlock',
      parameters: <String, Object>{'wallpaper_id': id},
    );
  }

  static void logAdImpression(String type) {
    _analytics.logEvent(
      name: 'ad_impression',
      parameters: <String, Object>{'ad_type': type},
    );
  }
}
