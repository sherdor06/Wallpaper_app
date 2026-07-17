import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'analytics_service.dart';
import 'remote_config_service.dart';

/// Manages AdMob ads (banner + interstitial). Ads are the only monetization —
/// there is no premium/ad-free tier, so ads are always shown.
///
/// Real AdMob unit IDs are used only in RELEASE builds; DEBUG builds use Google's
/// official TEST units. This protects the AdMob account from "invalid clicks"
/// during development (tapping your own live ads can get the account banned).
/// The real App IDs live in AndroidManifest.xml / Info.plist (used in all builds).
///
/// Before any ad is requested, UMP (Google's User Messaging Platform) gathers
/// GDPR consent for EEA/UK users. Ads only load once [adsAllowed] resolves to
/// `true` — required by AdMob policy for personalized ads in the EEA.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// When true, no ads are shown (banner hidden, interstitials skipped).
  ///
  /// Ads are shown by default in every build — debug/profile use Google's TEST
  /// unit ids (see below), so showing them is safe. For clean store screenshots
  /// hide them with `--dart-define=HIDE_ADS=true`.
  static const bool adsHidden =
      bool.fromEnvironment('HIDE_ADS', defaultValue: false);

  /// True when ads must not be shown at all — either the compile-time
  /// [adsHidden] flag, or the `ads_enabled` Remote Config kill switch is off.
  bool get _adsOff => adsHidden || !RemoteConfigService.instance.adsEnabled;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _initialized = false;

  // Whether gathered consent allows requesting ads. Stays false until UMP
  // consent has been resolved (or true immediately for users outside the EEA).
  bool _canRequestAds = false;
  final Completer<bool> _adsAllowed = Completer<bool>();

  /// Resolves once ad consent has been gathered — `true` if ads may be
  /// requested. Ad widgets (e.g. the banner) await this before loading.
  Future<bool> get adsAllowed => _adsAllowed.future;

  // Frequency cap: show an interstitial at most every [_showEvery] actions and
  // never more often than [_minGap]. Both come from Remote Config (with safe
  // defaults) so they can be tuned from the console without an app update.
  int get _showEvery => RemoteConfigService.instance.adShowEvery;
  Duration get _minGap =>
      Duration(seconds: RemoteConfigService.instance.adMinGapSeconds);
  int _actionCount = 0;
  DateTime _lastShown = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Real AdMob unit IDs (release only) ---
  static const _bannerIosReal = 'ca-app-pub-8510304338648685/3349592764';
  static const _bannerAndroidReal = 'ca-app-pub-8510304338648685/8027204377';
  static const _interstitialIosReal = 'ca-app-pub-8510304338648685/3166558696';
  static const _interstitialAndroidReal = 'ca-app-pub-8510304338648685/3561345758';
  // Rewarded (4K unlock) — real AdMob unit ids (per app / platform).
  static const _rewardedIosReal = 'ca-app-pub-8510304338648685/7828949747';
  static const _rewardedAndroidReal = 'ca-app-pub-8510304338648685/5475651512';

  // --- Google test unit IDs (debug) ---
  static const _bannerIosTest = 'ca-app-pub-3940256099942544/2934735716';
  static const _bannerAndroidTest = 'ca-app-pub-3940256099942544/6300978111';
  static const _interstitialIosTest = 'ca-app-pub-3940256099942544/4411468910';
  static const _interstitialAndroidTest = 'ca-app-pub-3940256099942544/1033173712';
  static const _rewardedIosTest = 'ca-app-pub-3940256099942544/1712485313';
  static const _rewardedAndroidTest = 'ca-app-pub-3940256099942544/5224354917';

  // Your physical test device's hashed id — printed to the console the first time
  // an ad is requested ("Use RequestConfiguration...setTestDeviceIds(...)"). When
  // set, real devices get test ads (no invalid-click risk); with
  // `--dart-define=UMP_TEST=true` it also forces the EEA consent geography so the
  // UMP flow can be tested from a non-EEA region.
  static const bool _umpTest = bool.fromEnvironment('UMP_TEST');
  static const List<String> _testDeviceIds = [
    // 'YOUR_DEVICE_HASH',
  ];

  /// Banner unit id — real in release, test in debug (per platform).
  String get bannerUnitId {
    if (kReleaseMode) return Platform.isIOS ? _bannerIosReal : _bannerAndroidReal;
    return Platform.isIOS ? _bannerIosTest : _bannerAndroidTest;
  }

  /// Interstitial unit id — real in release, test in debug (per platform).
  String get _interstitialUnitId {
    if (kReleaseMode) {
      return Platform.isIOS ? _interstitialIosReal : _interstitialAndroidReal;
    }
    return Platform.isIOS ? _interstitialIosTest : _interstitialAndroidTest;
  }

  /// Rewarded unit id — real in release, test in debug (per platform).
  String get _rewardedUnitId {
    if (kReleaseMode) {
      return Platform.isIOS ? _rewardedIosReal : _rewardedAndroidReal;
    }
    return Platform.isIOS ? _rewardedIosTest : _rewardedAndroidTest;
  }

  Future<void> init() async {
    // Initializing the SDK before consent is fine — only ad *requests* need
    // consent. This must stay fast: it blocks app startup (awaited in main()).
    await MobileAds.instance.initialize();
    if (_testDeviceIds.isNotEmpty) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: _testDeviceIds),
      );
    }
    _initialized = true;

    if (_adsOff) {
      // Ads disabled (HIDE_ADS build or the Remote Config kill switch) — skip
      // consent + loading entirely.
      if (!_adsAllowed.isCompleted) _adsAllowed.complete(false);
      return;
    }
    _gatherConsent();
  }

  /// Requests the latest UMP consent info and shows the consent form if
  /// required, then enables ad loading. Fire-and-forget: the SDK shows the form
  /// once the UI is up, so this must not block startup.
  void _gatherConsent() {
    final params = ConsentRequestParameters(
      consentDebugSettings: _umpTest
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: _testDeviceIds,
            )
          : null,
    );
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        // Consent info updated — show the form if required, then resolve.
        ConsentForm.loadAndShowConsentFormIfRequired((_) => _resolveConsent());
      },
      (FormError _) {
        // Offline / fetch error — fall back to whatever cached consent exists.
        _resolveConsent();
      },
    );
  }

  /// Reads the resolved consent state and starts preloading ads if allowed.
  Future<void> _resolveConsent() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    if (!_adsAllowed.isCompleted) _adsAllowed.complete(_canRequestAds);
    if (_canRequestAds) {
      _loadInterstitial();
      _loadRewarded();
    }
  }

  void _loadInterstitial() {
    if (!_initialized || !_canRequestAds) return;
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    if (!_initialized || !_canRequestAds) return;
    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Show an interstitial (e.g. after a wallpaper is applied), subject to the
  /// frequency cap, then preload the next one. No-op if not due or none ready.
  Future<void> maybeShowInterstitial() async {
    if (_adsOff || !_canRequestAds) return;
    _actionCount++;
    final due = _actionCount % _showEvery == 0 &&
        DateTime.now().difference(_lastShown) >= _minGap;
    if (!due) return;

    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _lastShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitial = null;
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _interstitial = null;
        _loadInterstitial();
      },
    );
    _interstitial = null;
    try {
      await ad.show();
      AnalyticsService.logAdImpression('interstitial');
    } catch (_) {
      // show() rarely throws; the failure callback already disposes/reloads.
    }
  }

  /// Shows a rewarded ad to unlock premium (4K) content. Returns `true` if the
  /// reward was earned — or if ads are unavailable, so the user is never hard
  /// blocked by a missing/failed ad. Preloads the next rewarded afterwards.
  Future<bool> showRewardedToUnlock() async {
    if (_adsOff || !_canRequestAds) return true;
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded(); // not ready — grant this time, preload for next
      return true;
    }
    _rewarded = null;
    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(true); // show failed — grant
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
      AnalyticsService.logAdImpression('rewarded');
    } catch (_) {
      if (!done.isCompleted) done.complete(true);
    }
    return done.future;
  }
}
