import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:applovin_max/applovin_max.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

import 'analytics_service.dart';
import 'remote_config_service.dart';

/// Manages ads through AppLovin MAX, with Yandex mediated inside it. Ads are the
/// only monetization — there is no premium/ad-free tier, so ads are always shown.
///
/// MAX is a mediation layer, not just a network: Yandex, Unity, Mintegral and
/// others bid through it and are configured in the MAX dashboard rather than in
/// this file. That matters here because the CIS audience this app serves is
/// where Yandex's demand is strongest, while MAX covers everywhere else — and if
/// AdMob is ever reinstated it becomes one more network in the same auction,
/// with no code change.
///
/// The public surface (`adsAllowed`, [bannerUnitId], [maybeShowInterstitial],
/// [maybeShowInterstitialOnBrowse], [showRewardedToUnlock]) is unchanged from
/// the AdMob implementation, so the UI never learns which network is behind it.
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

  bool _initialized = false;
  bool _canRequestAds = false;
  final Completer<bool> _adsAllowed = Completer<bool>();

  /// Resolves once the SDK is up and consent has been gathered — `true` if ads
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
  /// Deliberately ignores [_canRequestAds]: that only goes true after
  /// [initialize] returns, and a gate that appeared a second into every cold
  /// start would flicker. This looks at the things known up front — the build
  /// flag, the Remote Config kill switch, and whether credentials exist at all.
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
  // TODO(sherdor): fill these in from the AppLovin dashboard before shipping.
  // The SDK key is under Account → Keys; the unit ids under MAX → Ad Units,
  // created separately per platform. Yandex is switched on inside the dashboard
  // (MAX → Networks → Yandex) — it needs no ids here.
  static const _sdkKey = String.fromEnvironment('APPLOVIN_SDK_KEY',
      defaultValue: 'YOUR_APPLOVIN_SDK_KEY');

  static const _bannerAndroid = 'YOUR_ANDROID_BANNER_UNIT_ID';
  static const _bannerIos = 'YOUR_IOS_BANNER_UNIT_ID';
  static const _interstitialAndroid = 'YOUR_ANDROID_INTERSTITIAL_UNIT_ID';
  static const _interstitialIos = 'YOUR_IOS_INTERSTITIAL_UNIT_ID';
  static const _rewardedAndroid = 'YOUR_ANDROID_REWARDED_UNIT_ID';
  static const _rewardedIos = 'YOUR_IOS_REWARDED_UNIT_ID';

  /// True while the credentials above are still placeholders. Everything stays
  /// switched off in that state rather than firing requests that can only fail
  /// — a stream of malformed requests is exactly the pattern networks flag.
  static bool get _credentialsMissing =>
      _sdkKey.startsWith('YOUR_') || _bannerAndroid.startsWith('YOUR_');

  /// Devices that must never see live ads.
  ///
  /// MAX has no debug/live split in the unit ids the way AdMob did, so this is
  /// the only thing standing between a development tap and an invalid-activity
  /// flag on the account. These are Google Advertising IDs (Android) / IDFAs
  /// (iOS) — read them from the device's own logs on first launch, or from
  /// Settings → Google → Ads on Android.
  static const List<String> _testDeviceIds = [
    // Samsung Galaxy A17 (dev phone) — replace with its advertising ID.
    // 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
  ];

  String get bannerUnitId => Platform.isIOS ? _bannerIos : _bannerAndroid;
  String get _interstitialUnitId =>
      Platform.isIOS ? _interstitialIos : _interstitialAndroid;
  String get _rewardedUnitId =>
      Platform.isIOS ? _rewardedIos : _rewardedAndroid;

  // --- Rewarded state -------------------------------------------------------
  // MAX reports through listeners rather than per-ad objects, so the result of
  // a show has to be carried between callbacks.
  Completer<bool>? _rewardCompleter;
  bool _rewardEarned = false;
  Timer? _rewardTimeout;

  /// Ceiling on how long a rewarded show may stay unresolved.
  ///
  /// The result arrives through `onAdHidden` / `onAdDisplayFailed`. If neither
  /// ever fires — an SDK edge case, or the process being backgrounded at the
  /// wrong moment — the awaiting caller would hang and the save button would sit
  /// in its "Playing" state for the rest of the session. Generous enough that no
  /// real ad reaches it.
  static const _rewardTimeoutAfter = Duration(minutes: 3);

  Future<void> init() async {
    if (_adsOff || _credentialsMissing) {
      if (!_adsAllowed.isCompleted) _adsAllowed.complete(false);
      return;
    }

    _registerListeners();

    // MAX's own consent flow replaces Google's UMP: it detects the user's
    // geography and presents a GDPR-compliant CMP where one is required.
    AppLovinMAX.setTermsAndPrivacyPolicyFlowEnabled(true);
    AppLovinMAX.setPrivacyPolicyUrl('https://wallpapers-cdn.pages.dev/privacy');
    if (_testDeviceIds.isNotEmpty) {
      AppLovinMAX.setTestDeviceAdvertisingIds(_testDeviceIds);
    }
    AppLovinMAX.setVerboseLogging(!kReleaseMode);

    final config = await AppLovinMAX.initialize(_sdkKey);
    _initialized = config != null;
    _canRequestAds = _initialized;
    if (!_adsAllowed.isCompleted) _adsAllowed.complete(_canRequestAds);
    if (!_canRequestAds) return;

    // ATT after MAX's consent flow, before the first ad request: the CMP answers
    // GDPR, ATT answers Apple, and the IDFA has to be settled before anything is
    // fetched or the request goes out unpersonalised.
    await _requestTrackingAuthorization();

    AppLovinMAX.loadInterstitial(_interstitialUnitId);
    AppLovinMAX.loadRewardedAd(_rewardedUnitId);
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
      // right after the consent flow, so give the window a beat to settle.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (_) {
      // Never block ad loading on the prompt failing.
    }
  }

  void _registerListeners() {
    AppLovinMAX.setInterstitialListener(InterstitialListener(
      onAdLoadedCallback: (_) {},
      // MAX retries internally with its own backoff — reloading here would
      // fight that and hammer the network.
      onAdLoadFailedCallback: (_, __) {},
      onAdDisplayedCallback: (_) {},
      onAdDisplayFailedCallback: (_, __) =>
          AppLovinMAX.loadInterstitial(_interstitialUnitId),
      onAdClickedCallback: (_) {},
      onAdHiddenCallback: (_) =>
          AppLovinMAX.loadInterstitial(_interstitialUnitId),
    ));

    AppLovinMAX.setRewardedAdListener(RewardedAdListener(
      onAdLoadedCallback: (_) {},
      onAdLoadFailedCallback: (_, __) {},
      onAdDisplayedCallback: (_) {},
      // The show never happened, so grant access rather than punishing the user
      // for the network's failure.
      onAdDisplayFailedCallback: (_, __) {
        _settleReward(true);
        AppLovinMAX.loadRewardedAd(_rewardedUnitId);
      },
      onAdClickedCallback: (_) {},
      onAdHiddenCallback: (_) {
        _settleReward(_rewardEarned);
        AppLovinMAX.loadRewardedAd(_rewardedUnitId);
      },
      onAdReceivedRewardCallback: (_, __) => _rewardEarned = true,
    ));
  }

  void _settleReward(bool granted) {
    _rewardTimeout?.cancel();
    _rewardTimeout = null;
    final c = _rewardCompleter;
    _rewardCompleter = null;
    if (c != null && !c.isCompleted) c.complete(granted);
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
    final ready = await AppLovinMAX.isInterstitialReady(_interstitialUnitId);
    if (ready != true) return; // MAX is already retrying on its own
    _noteFullScreenShown();
    AppLovinMAX.showInterstitial(_interstitialUnitId);
    AnalyticsService.logAdImpression('interstitial');
  }

  /// Records that a full-screen ad was just shown, starting the cooldown that
  /// blocks the *next* one. Called for interstitial and rewarded alike.
  void _noteFullScreenShown() => _lastFullScreen = DateTime.now();

  /// Shows a rewarded ad to unlock gated content. Returns `true` if the reward
  /// was earned — or if ads are unavailable, so the user is never hard blocked
  /// by a missing or failed ad.
  Future<bool> showRewardedToUnlock() async {
    if (_adsOff || !_canRequestAds) return true;
    final ready = await AppLovinMAX.isRewardedAdReady(_rewardedUnitId);
    if (ready != true) {
      // Not filled — grant this time; MAX keeps retrying in the background.
      return true;
    }
    // A show already in flight means a duplicate tap; let the first one settle.
    if (_rewardCompleter != null) return _rewardCompleter!.future;

    _rewardEarned = false;
    final completer = Completer<bool>();
    _rewardCompleter = completer;
    // Grant on timeout rather than refuse: if the SDK went silent the user did
    // nothing wrong, and the unlock is worth less than a dead button.
    _rewardTimeout?.cancel();
    _rewardTimeout = Timer(_rewardTimeoutAfter, () => _settleReward(true));
    _noteFullScreenShown();
    AppLovinMAX.showRewardedAd(_rewardedUnitId);
    AnalyticsService.logAdImpression('rewarded');
    return completer.future;
  }
}
