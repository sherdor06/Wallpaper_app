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
  static const _kAdBrowseEvery = 'ad_browse_every';
  static const _kAdMinGapSeconds = 'ad_min_gap_seconds';
  static const _kRewardedRequiredFor4k = 'rewarded_required_for_4k';
  static const _kRewardedRequiredForFhd = 'rewarded_required_for_fhd';
  static const _kConsentRequired = 'consent_required';
  static const _kFeaturedCategory = 'featured_category';
  static const _kHomeStrip = 'home_strip';
  static const _kUpdateLatestBuild = 'update_latest_build';
  static const _kUpdateMinBuild = 'update_min_build';

  // Safe defaults (identical to the old constants) — used until/unless the
  // console overrides them.
  static const bool _defAdsEnabled = true;
  static const int _defAdShowEvery = 3;
  static const int _defAdBrowseEvery = 8;
  static const int _defAdMinGapSeconds = 45;
  static const bool _defRewardedRequiredFor4k = true;
  static const bool _defRewardedRequiredForFhd = true;
  // Defaults to false so the CIS audience is never asked a GDPR question that
  // does not apply to them. The console condition turns it on for the EEA/UK;
  // ConsentService also asks on a device-locale hint, which covers the case
  // where this value never arrived.
  static const bool _defConsentRequired = false;
  // Empty: no spotlight card on the home screen. Set to a category id
  // ("aesthetic") from the console to announce a new collection; clear it
  // again once it is old news — no app update either way.
  static const String _defFeaturedCategory = '';
  // The collections in the home carousel, in order. Comma-separated ids;
  // unknown or thin ones are dropped by the home screen.
  static const String _defHomeStrip =
      'girly,aesthetic,nature,animals,cars,space,anime,city';
  // Zero: no build is behind, so nobody is asked to update until a value is
  // published. See UpdateService.
  static const int _defUpdateLatestBuild = 0;
  static const int _defUpdateMinBuild = 0;

  /// How long launch waits for a fetch. Launch sits behind the native splash
  /// until this returns, so the full [RemoteConfigSettings.fetchTimeout] was up
  /// to eight seconds of logo on a slow connection, about once an hour.
  static const _launchBudget = Duration(seconds: 3);

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
        _kAdBrowseEvery: _defAdBrowseEvery,
        _kAdMinGapSeconds: _defAdMinGapSeconds,
        _kRewardedRequiredFor4k: _defRewardedRequiredFor4k,
        _kRewardedRequiredForFhd: _defRewardedRequiredForFhd,
        _kConsentRequired: _defConsentRequired,
        _kFeaturedCategory: _defFeaturedCategory,
        _kHomeStrip: _defHomeStrip,
        _kUpdateLatestBuild: _defUpdateLatestBuild,
        _kUpdateMinBuild: _defUpdateMinBuild,
      });
      // Readable from here on: the values activated on an earlier launch, or
      // the defaults. A failed fetch used to leave [_rc] null, so an offline
      // start fell back to hard-coded defaults — the ad kill switch included —
      // even with last session's values on disk.
      _rc = rc;
      // A fetch that overruns [_launchBudget] still finishes in the
      // background, but is only activated on the next launch: values that
      // change while the home screen is up would rearrange it under the user.
      final fetched = await rc
          .fetch()
          .then((_) => true)
          .timeout(_launchBudget, onTimeout: () => false);
      if (fetched) await rc.activate();
    } catch (_) {
      // Keep whatever is active.
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

  /// Show an interstitial at most every N browse steps — currently the shuffle
  /// button (min 1). Looser than [adShowEvery] because browsing is frequent.
  int get adBrowseEvery {
    final v = _rc?.getInt(_kAdBrowseEvery) ?? _defAdBrowseEvery;
    return v > 0 ? v : _defAdBrowseEvery;
  }

  /// Minimum seconds between any two full-screen ads — interstitial *and*
  /// rewarded share this gap, so the two can never appear back to back.
  int get adMinGapSeconds {
    final v = _rc?.getInt(_kAdMinGapSeconds) ?? _defAdMinGapSeconds;
    return v >= 0 ? v : _defAdMinGapSeconds;
  }

  /// Whether opening/applying a 4K wallpaper requires watching a rewarded ad.
  /// `false` makes all 4K wallpapers free to use.
  bool get rewardedRequiredFor4k =>
      _rc?.getBool(_kRewardedRequiredFor4k) ?? _defRewardedRequiredFor4k;

  /// Same gate for Full-HD wallpapers, so monetization isn't limited to the 4K
  /// tier. Resolution labels stay accurate — only the gate widens.
  bool get rewardedRequiredForFhd =>
      _rc?.getBool(_kRewardedRequiredForFhd) ?? _defRewardedRequiredForFhd;

  /// Whether this user must be asked for ad-personalisation consent.
  ///
  /// Set through a console *condition* rather than a plain value — Firebase
  /// resolves the country server-side, which is the only signal here that
  /// actually knows where the device is. See [ConsentService].
  bool get consentRequired =>
      _rc?.getBool(_kConsentRequired) ?? _defConsentRequired;

  /// Category id the home screen spotlights as a new collection, or empty for
  /// none. The home screen also checks the category actually has enough
  /// wallpapers, so a typo here hides the card rather than showing a broken one.
  String get featuredCategory =>
      (_rc?.getString(_kFeaturedCategory) ?? _defFeaturedCategory).trim();

  /// Category ids for the home carousel, in display order. Falls back to
  /// the default line-up when the remote value is empty.
  List<String> get homeStrip {
    final raw = _rc?.getString(_kHomeStrip) ?? '';
    final ids = [
      for (final s in (raw.isEmpty ? _defHomeStrip : raw).split(','))
        if (s.trim().isNotEmpty) s.trim(),
    ];
    return ids;
  }

  /// Builds below this number are offered the update (the `+N` in pubspec,
  /// Android's versionCode). Set it to the new build once that build is live on
  /// Play; Play itself still decides whether this device can have it yet.
  int get updateLatestBuild =>
      _rc?.getInt(_kUpdateLatestBuild) ?? _defUpdateLatestBuild;

  /// Builds below this number stop at a full-screen "Update required" page.
  /// For a build found to be broken, not for ordinary releases.
  int get updateMinBuild => _rc?.getInt(_kUpdateMinBuild) ?? _defUpdateMinBuild;
}
