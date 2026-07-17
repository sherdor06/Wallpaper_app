import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

/// Reads feature flags / ad-tuning values from Firebase Remote Config so they
/// can be changed from the Firebase console without shipping an app update.
///
/// Values are fetched once at startup (in [init]) and then read from the cached
/// config. Every getter has a safe default that matches the previously
/// hard-coded behavior, so the app keeps working if the fetch fails (offline,
/// first launch) or a bad value is published remotely.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  // Remote Config parameter keys — create these in the Firebase console.
  static const _kAdsEnabled = 'ads_enabled';
  static const _kAdShowEvery = 'ad_show_every';
  static const _kAdMinGapSeconds = 'ad_min_gap_seconds';
  static const _kRewardedRequiredFor4k = 'rewarded_required_for_4k';

  // Safe defaults (identical to the old constants) — used until/unless the
  // console overrides them.
  static const bool _defAdsEnabled = true;
  static const int _defAdShowEvery = 3;
  static const int _defAdMinGapSeconds = 45;
  static const bool _defRewardedRequiredFor4k = true;

  FirebaseRemoteConfig? _rc;

  /// Loads defaults, then fetches + activates the latest values. Never throws —
  /// on any error the default/last-cached values remain in effect.
  Future<void> init() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        // Debug: always fetch fresh. Release: throttle to once per hour so we
        // don't hammer the backend and stay within Remote Config quotas.
        minimumFetchInterval:
            kReleaseMode ? const Duration(hours: 1) : Duration.zero,
      ));
      await rc.setDefaults(<String, dynamic>{
        _kAdsEnabled: _defAdsEnabled,
        _kAdShowEvery: _defAdShowEvery,
        _kAdMinGapSeconds: _defAdMinGapSeconds,
        _kRewardedRequiredFor4k: _defRewardedRequiredFor4k,
      });
      await rc.fetchAndActivate();
      _rc = rc;
    } catch (_) {
      // Keep defaults on any failure.
      _rc = null;
    }
  }

  /// Master ad kill switch. `false` hides all ads app-wide (banner +
  /// interstitial + rewarded), without an app update.
  bool get adsEnabled => _rc?.getBool(_kAdsEnabled) ?? _defAdsEnabled;

  /// Show an interstitial at most every N qualifying actions (min 1).
  int get adShowEvery {
    final v = _rc?.getInt(_kAdShowEvery) ?? _defAdShowEvery;
    return v > 0 ? v : _defAdShowEvery;
  }

  /// Minimum seconds between two interstitials (min 0).
  int get adMinGapSeconds {
    final v = _rc?.getInt(_kAdMinGapSeconds) ?? _defAdMinGapSeconds;
    return v >= 0 ? v : _defAdMinGapSeconds;
  }

  /// Whether opening/applying a 4K wallpaper requires watching a rewarded ad.
  /// `false` makes all 4K wallpapers free to use.
  bool get rewardedRequiredFor4k =>
      _rc?.getBool(_kRewardedRequiredFor4k) ?? _defRewardedRequiredFor4k;
}
