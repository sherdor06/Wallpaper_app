import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:yandex_mobileads/mobile_ads.dart';

import 'analytics_service.dart';
import 'remote_config_service.dart';

/// Manages ads through the Yandex Mobile Ads SDK. Ads are the only
/// monetization — there is no premium/ad-free tier, so ads are always shown.
///
/// Yandex is used directly, without a mediation layer. This app's audience is
/// CIS, which is where Yandex's demand is strongest, and a single network keeps
/// the SDK surface small.
///
/// The public surface (`adsAllowed`, [bannerUnitId], [maybeShowInterstitial],
/// [maybeShowInterstitialOnBrowse], [showRewardedToUnlock], [rewardedAvailable])
/// is unchanged from the AdMob and AppLovin implementations before it, so the UI
/// never learns which network is behind it — and putting mediation back later is
/// a change to this file alone.
///
/// One structural difference from those two is worth knowing when editing here:
/// Yandex has no preloaded-singleton-with-auto-reload model. A full-screen ad is
/// a one-shot object — load it, show it, destroy it, load the next. That is why
/// this class holds `_interstitial` / `_rewarded` instances and reloads after
/// every show, instead of asking the SDK whether an ad "is ready".
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// When true, no ads are shown (banner hidden, interstitials skipped).
  ///
  /// Ads are shown by default in every build. For clean store screenshots hide
  /// them with `--dart-define=HIDE_ADS=true`.
  static const bool adsHidden =
      bool.fromEnvironment('HIDE_ADS', defaultValue: false);

  /// True when ads must not be shown at all — either the compile-time
  /// [adsHidden] flag, or the `ads_enabled` Remote Config kill switch is off.
  bool get _adsOff => adsHidden || !RemoteConfigService.instance.adsEnabled;

  bool _canRequestAds = false;
  final Completer<bool> _adsAllowed = Completer<bool>();

  /// Resolves once the SDK is up and consent has been applied — `true` if ads
  /// may be requested. Ad widgets (e.g. the banner) await this before loading.
  Future<bool> get adsAllowed => _adsAllowed.future;

  /// Whether a rewarded ad could actually play, answered synchronously so the UI
  /// can decide whether to offer one at all.
  ///
  /// [showRewardedToUnlock] grants the unlock for free when this is false, which
  /// means any "watch an ad" affordance shown in that state is a promise the app
  /// cannot keep — the tap just downloads. Screens that gate content must check
  /// this before drawing the gate.
  ///
  /// Deliberately ignores [_canRequestAds]: that only goes true after [init]
  /// returns, and a gate that appeared a second into every cold start would
  /// flicker. This looks at the things known up front — the build flag, the
  /// Remote Config kill switch, and whether this platform has unit ids at all.
  bool get rewardedAvailable => !_adsOff && !_credentialsMissing;

  // --- Frequency caps -------------------------------------------------------
  // Interstitials have two independent triggers:
  //   • value moments — a wallpaper was applied/saved → every [_showEvery]
  //   • browse steps  — the user shuffled to another wallpaper → [_browseEvery]
  // Separate counters because browsing is far more frequent than applying.
  //
  // Both share ONE cooldown, and every full-screen ad — rewarded included —
  // refreshes it (see [_noteFullScreenShown]). That is what makes it safe to
  // request an interstitial right after a rewarded unlock: the gap swallows it
  // instead of stacking two full-screen ads on one tap.
  int get _showEvery => RemoteConfigService.instance.adShowEvery;
  int get _browseEvery => RemoteConfigService.instance.adBrowseEvery;
  Duration get _minGap =>
      Duration(seconds: RemoteConfigService.instance.adMinGapSeconds);
  int _actionCount = 0;
  int _browseCount = 0;
  DateTime _lastFullScreen = DateTime.fromMillisecondsSinceEpoch(0);

  // --- Credentials ----------------------------------------------------------
  // Yandex ad unit ids, created in the YAN partner interface under app 19979404
  // (bundle com.sherdor.wallpapers). No SDK key exists in this SDK — the unit id
  // identifies the account, so there is nothing else to configure.
  //
  // TODO(sherdor): create the iOS units once the app ships on the App Store.
  // Yandex treats iOS as a separate app, so it gets its own ids rather than
  // reusing the Android ones.
  static const _bannerAndroid = 'R-M-19979404-1';
  static const _interstitialAndroid = 'R-M-19979404-2';
  static const _rewardedAndroid = 'R-M-19979404-3';

  static const _bannerIos = 'YOUR_IOS_BANNER_UNIT_ID';
  static const _interstitialIos = 'YOUR_IOS_INTERSTITIAL_UNIT_ID';
  static const _rewardedIos = 'YOUR_IOS_REWARDED_UNIT_ID';

  // Yandex's public demo units. They always fill with test creatives, need no
  // moderation, and count against nobody's statistics — so debug builds use
  // them unconditionally. That is what makes the full rewarded flow testable on
  // an emulator while the real units are still waiting on moderation, and it
  // keeps a developer's own taps out of the live account (the invalid-activity
  // pattern every network bans for).
  static const _demoBanner = 'demo-banner-yandex';
  static const _demoInterstitial = 'demo-interstitial-yandex';
  static const _demoRewarded = 'demo-rewarded-yandex';

  static String get _platformBanner => Platform.isIOS ? _bannerIos : _bannerAndroid;
  String get bannerUnitId => kReleaseMode ? _platformBanner : _demoBanner;
  String get _interstitialUnitId => kReleaseMode
      ? (Platform.isIOS ? _interstitialIos : _interstitialAndroid)
      : _demoInterstitial;
  String get _rewardedUnitId => kReleaseMode
      ? (Platform.isIOS ? _rewardedIos : _rewardedAndroid)
      : _demoRewarded;

  /// True while a *release* build on *this platform* still has placeholder
  /// unit ids. Everything stays switched off in that state rather than firing
  /// requests that can only fail — a stream of malformed requests is exactly
  /// the pattern networks flag.
  ///
  /// Per-platform, not global: Android is configured and iOS is not, and a
  /// global check would let an iOS release request `YOUR_IOS_...` all day.
  /// Debug builds never count as missing — they run on the demo units above,
  /// which is what lets iOS be tested before its real ids exist.
  static bool get _credentialsMissing =>
      kReleaseMode && _platformBanner.startsWith('YOUR_');

  // --- Full-screen ad state -------------------------------------------------
  // Each holds at most one loaded ad, consumed on show and reloaded after.
  InterstitialAdLoader? _interstitialLoader;
  RewardedAdLoader? _rewardedLoader;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  /// The rewarded show currently on screen, so a double tap awaits the first one
  /// instead of starting a second.
  Future<bool>? _rewardInFlight;

  /// Ceiling on how long a rewarded show may stay unresolved.
  ///
  /// The result arrives when the ad is dismissed. If that never happens — an SDK
  /// edge case, or the process being backgrounded at the wrong moment — the
  /// awaiting caller would hang and the save button would sit in its "Playing"
  /// state for the rest of the session. Generous enough that no real ad reaches
  /// it.
  static const _rewardTimeoutAfter = Duration(minutes: 3);

  Future<void> init() async {
    if (_adsOff || _credentialsMissing) {
      if (!_adsAllowed.isCompleted) _adsAllowed.complete(false);
      return;
    }

    await YandexAds.setLogging(!kReleaseMode);
    // Privacy has to be settled before the SDK starts: ATT decides whether iOS
    // hands out an IDFA at all, and the consent flag rides on every request.
    await _requestTrackingAuthorization();
    await _applyUserConsent();

    await YandexAds.initialize();
    _canRequestAds = true;
    if (!_adsAllowed.isCompleted) _adsAllowed.complete(true);

    _interstitialLoader = InterstitialAdLoader();
    _rewardedLoader = RewardedAdLoader();
    unawaited(_preloadInterstitial());
    unawaited(_preloadRewarded());
  }

  /// Shows Apple's App Tracking Transparency prompt on iOS.
  ///
  /// Only asks when the status is still `notDetermined` — iOS shows the system
  /// dialog once per install, and calling again just returns the stored answer.
  /// A denial is fine: ads keep serving, they are simply contextual.
  Future<void> _requestTrackingAuthorization() async {
    if (!Platform.isIOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) return;
      // iOS silently drops the prompt if the app is not yet active — this runs
      // during startup, so give the window a beat to settle.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (_) {
      // Never block ad loading on the prompt failing.
    }
  }

  /// Tells the SDK whether personal data may be used for targeting.
  ///
  /// Unlike MAX, this SDK ships no consent management platform — the flag is
  /// ours to set, and there is no dialog in the app to set it from. So the
  /// answer is "no" unless something already asked: on iOS, ATT is exactly that
  /// question, and an authorized status carries the user's own yes.
  ///
  /// The cost is non-personalised ads (and a lower price) for Android users
  /// everywhere, including the CIS audience GDPR never covered. Adding a CMP —
  /// or a consent dialog shown only in the EEA — is what turns that back on.
  Future<void> _applyUserConsent() async {
    var consent = false;
    if (Platform.isIOS) {
      try {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        consent = status == TrackingStatus.authorized;
      } catch (_) {
        consent = false;
      }
    }
    try {
      await YandexAds.setUserConsent(consent);
    } catch (_) {
      // Defaults to no consent inside the SDK, which is the safe direction.
    }
  }

  /// Loads the next interstitial into [_interstitial], if one isn't already
  /// there or on its way.
  ///
  /// Failures are swallowed without a retry loop on purpose: the next trigger
  /// calls this again, which spaces retries by real user activity instead of
  /// hammering the network after a no-fill.
  Future<void> _preloadInterstitial() async {
    final loader = _interstitialLoader;
    if (loader == null || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    try {
      _interstitial = await loader.loadAd(
        adRequest: AdRequest(adUnitId: _interstitialUnitId),
      );
    } catch (_) {
      // No fill or a network error — try again on the next trigger.
    } finally {
      _loadingInterstitial = false;
    }
  }

  Future<void> _preloadRewarded() async {
    final loader = _rewardedLoader;
    if (loader == null || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    try {
      _rewarded = await loader.loadAd(
        adRequest: AdRequest(adUnitId: _rewardedUnitId),
      );
    } catch (_) {
      // Same as above — the next unlock attempt re-requests.
    } finally {
      _loadingRewarded = false;
    }
  }

  /// Show an interstitial after a "value moment" — a wallpaper was applied or
  /// saved. Subject to [_showEvery] and the shared cooldown.
  ///
  /// Safe to call unconditionally, including immediately after a rewarded
  /// unlock: the cooldown in [_showInterstitial] rejects it. Callers must NOT
  /// re-implement that check themselves.
  Future<void> maybeShowInterstitial() async {
    if (_adsOff || !_canRequestAds) return;
    _actionCount++;
    if (_actionCount % _showEvery != 0) return;
    await _showInterstitial();
  }

  /// Show an interstitial while the user browses (the shuffle button) — the
  /// screen is about to change anyway, so an ad here costs no lost context.
  ///
  /// Uses its own, much looser counter: most sessions browse many more
  /// wallpapers than they apply, and this trigger is what keeps the format
  /// earning when nearly every wallpaper is rewarded-gated.
  Future<void> maybeShowInterstitialOnBrowse() async {
    if (_adsOff || !_canRequestAds) return;
    _browseCount++;
    if (_browseCount % _browseEvery != 0) return;
    await _showInterstitial();
  }

  /// Shows the preloaded interstitial if the shared full-screen cooldown has
  /// elapsed. No-op if too soon or none ready.
  Future<void> _showInterstitial() async {
    if (DateTime.now().difference(_lastFullScreen) < _minGap) return;
    final ad = _interstitial;
    if (ad == null) {
      // Nothing loaded — start one for next time rather than waiting on it now.
      unawaited(_preloadInterstitial());
      return;
    }
    _interstitial = null;
    _noteFullScreenShown();
    AnalyticsService.logAdImpression('interstitial');
    try {
      await ad.setAdEventListener(eventListener: InterstitialAdEventListener());
      await ad.show();
      await ad.waitForDismiss().timeout(_rewardTimeoutAfter);
    } catch (_) {
      // A failed show costs nothing here — there is no caller waiting on it.
    } finally {
      await ad.destroy();
      unawaited(_preloadInterstitial());
    }
  }

  /// Records that a full-screen ad was just shown, starting the cooldown that
  /// blocks the *next* one. Called for interstitial and rewarded alike.
  void _noteFullScreenShown() => _lastFullScreen = DateTime.now();

  /// Shows a rewarded ad to unlock gated content. Returns `true` if the reward
  /// was earned — or if ads are unavailable, so the user is never hard blocked
  /// by a missing or failed ad.
  Future<bool> showRewardedToUnlock() async {
    if (_adsOff || !_canRequestAds) return true;

    // A show already in flight means a duplicate tap; let the first one settle.
    final inFlight = _rewardInFlight;
    if (inFlight != null) return inFlight;

    final ad = _rewarded;
    if (ad == null) {
      // Not filled — grant this time and load one for the next attempt.
      unawaited(_preloadRewarded());
      return true;
    }
    _rewarded = null;

    final play = _playRewarded(ad);
    _rewardInFlight = play;
    try {
      return await play;
    } finally {
      _rewardInFlight = null;
    }
  }

  /// Plays [ad] to completion and reports whether the unlock is granted.
  ///
  /// Grants on a failed show and on the timeout as well as on a real reward:
  /// in every one of those cases the user did nothing wrong, and the unlock is
  /// worth less than a dead button.
  Future<bool> _playRewarded(RewardedAd ad) async {
    var failedToShow = false;
    var timedOut = false;
    Reward? reward;

    _noteFullScreenShown();
    AnalyticsService.logAdImpression('rewarded');
    try {
      await ad.setAdEventListener(
        eventListener: RewardedAdEventListener(
          onAdFailedToShow: (_) => failedToShow = true,
        ),
      );
      await ad.show();
      reward = await ad.waitForDismiss().timeout(_rewardTimeoutAfter);
    } on TimeoutException {
      timedOut = true;
    } catch (_) {
      failedToShow = true;
    } finally {
      await ad.destroy();
      unawaited(_preloadRewarded());
    }

    return reward != null || failedToShow || timedOut;
  }
}
