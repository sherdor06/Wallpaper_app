import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

import '../../services/ad_service.dart';

/// Bottom banner (always shown — ads are the only monetization).
///
/// [AdWidget] is a real widget rather than an overlay, so it sits in the
/// Scaffold's bottom column like any other child and the nav bar rests directly
/// on top of it.
///
/// An inline banner stretches to the container width and stops at a height we
/// choose, and the SDK can be asked for that height before any ad exists — so
/// the strip is reserved up front and nothing around it jumps when the ad
/// arrives. While the banner loads (or if it fails) a neutral placeholder of
/// the same height fills it.
///
/// Inline rather than sticky: a sticky banner picks its own height for a
/// screen-pinned slot and came back 100dp tall, which is a lot of the screen to
/// hand to an ad that sits directly above the nav bar. [_maxHeight] caps it.
///
/// The [AdWidget] is mounted as soon as `BannerAd.load` has built the ad's
/// platform view, not once the ad has loaded. That order is load-bearing: the
/// request is only sent from the view's creation callback, so a widget that
/// waited for "loaded" before mounting the view would wait forever. Until the
/// ad paints, the view is 1dp tall and sits invisibly over the placeholder.
///
/// When the banner cannot fill — the network refused the unit, or every retry
/// came back empty — the ad is destroyed and the strip collapses. In November
/// 2026 the network was found refusing the unit, and the reserved strip had
/// been sitting empty above every user's nav bar.
class AdBannerPlaceholder extends StatefulWidget {
  const AdBannerPlaceholder({super.key});

  @override
  State<AdBannerPlaceholder> createState() => _AdBannerPlaceholderState();
}

class _AdBannerPlaceholderState extends State<AdBannerPlaceholder> {
  /// Ceiling on the banner's height. The SDK fills up to this and reports what
  /// it actually used; a standard banner is 50dp, which is what this asks for.
  static const _maxHeight = 50;

  /// Height used until the SDK reports the real one — same as the cap, so the
  /// reserved strip is right even before the answer arrives.
  static const _fallbackHeight = _maxHeight * 1.0;

  /// Unlike a mediation layer, this SDK does not keep retrying behind the view:
  /// a failed load stays failed until asked again. Without a retry a single
  /// no-fill at startup would mean no banner for the whole session — so retry a
  /// few times, slowly enough not to look like a hammering client.
  static const _retryAfter = Duration(seconds: 60);
  static const _maxAttempts = 3;

  BannerAd? _ad;
  Timer? _retryTimer;
  StreamSubscription<BannerAdLoadState>? _loadStates;

  /// Loads sent since the last one that filled.
  int _attempts = 0;
  int? _reservedHeight;
  bool _loaded = false;
  bool _setupStarted = false;

  /// Null until [AdService.adsAllowed] answers. `false` means no ad will ever
  /// arrive in this session — the SDK is off, or this platform has no unit ids —
  /// and the widget collapses instead of reserving space.
  ///
  /// That distinction matters while iOS is still unconfigured: users there must
  /// not be left looking at an empty grey strip where a banner will one day be.
  bool? _adsPossible;

  /// True once this banner has stopped trying for the session (see
  /// [_giveUp]); it then takes no space, like [_adsPossible] false.
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    // Skip entirely when ads are hidden (e.g. store screenshots).
    if (AdService.adsHidden) return;
    // Wait until the SDK is up and consent is applied before requesting. Any
    // debug run answers false here (see AdService.adsAllowed), so the strip
    // collapses and nothing is requested.
    unawaited(
      AdService.instance.adsAllowed.then((allowed) {
        if (!mounted) return;
        setState(() => _adsPossible = allowed);
        if (allowed) unawaited(_setup());
      }),
    );
  }

  /// Reserves the banner's height, then kicks off the first load.
  Future<void> _setup() async {
    if (_setupStarted) return;
    _setupStarted = true;
    // Refused earlier this session — the shell was rebuilt, say. The answer
    // will not have changed.
    if (AdService.instance.wasRefused(AdService.bannerFormat)) {
      _giveUp();
      return;
    }

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = BannerAdSize.inline(width: width, maxHeight: _maxHeight);
    try {
      final height = await size.getCalculatedHeight();
      if (!mounted) return;
      setState(() => _reservedHeight = height);
    } catch (_) {
      // Keep [_fallbackHeight]; a few pixels off beats no banner at all.
    }
    // The measurement is a platform round trip, long enough to leave the
    // screen during it. An ad created past this point is never destroyed.
    if (!mounted) return;

    final ad = BannerAd(adSize: size);
    _loadStates = ad.loadStateStream.listen(_onLoadState);
    _ad = ad;
    await _load();
    // `load` has built the ad's platform view by now, but AdWidget only
    // rebuilds itself once an ad has loaded, so mount the view here. This used
    // to ride on the measurement's setState above landing in the same frame;
    // when the measurement failed, the view was never mounted and the banner
    // never requested anything.
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final ad = _ad;
    if (ad == null || !mounted) return;
    _attempts++;
    try {
      await ad.load(AdRequest(adUnitId: AdService.instance.bannerUnitId));
    } catch (e) {
      _onFailed(e);
    }
  }

  void _onLoadState(BannerAdLoadState state) {
    if (!mounted) return;
    if (state is BannerAdLoadStateLoaded) {
      _retryTimer?.cancel();
      _attempts = 0;
      setState(() {
        _loaded = true;
        _reservedHeight = state.height;
      });
    } else if (state is BannerAdLoadStateError) {
      _onFailed(state.error);
    }
  }

  void _onFailed(Object error) {
    if (!mounted) return;
    AdService.instance.reportLoadFailure(AdService.bannerFormat, error);
    // A refused unit answers every retry the same way.
    if (AdService.isPermanentFailure(error) || _attempts >= _maxAttempts) {
      _giveUp();
      return;
    }
    setState(() => _loaded = false);
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryAfter, _load);
  }

  /// Stops for the rest of the session: cancels the retry, destroys the ad
  /// and collapses the strip. A band of empty space above the nav says
  /// "broken" more than no banner does.
  void _giveUp() {
    _retryTimer?.cancel();
    _loadStates?.cancel().ignore();
    _loadStates = null;
    final ad = _ad;
    _ad = null;
    ad?.destroy().ignore();
    if (mounted) setState(() => _gaveUp = true);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    // Failures here are of no interest once the banner is gone.
    _loadStates?.cancel().ignore();
    _ad?.destroy().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ads hidden -> take up no space at all (clean screenshots).
    if (AdService.adsHidden) return const SizedBox.shrink();
    // Resolved to "never", or given up on -> same, no dead strip at the
    // bottom of the screen.
    if (_adsPossible == false || _gaveUp) return const SizedBox.shrink();

    final height = _reservedHeight?.toDouble() ?? _fallbackHeight;
    final ad = _ad;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Underneath until the ad has painted over it (see the class note).
          if (!_loaded) _placeholder(height),
          if (ad != null) AdWidget(bannerAd: ad),
        ],
      ),
    );
  }

  /// Drawn from the theme: the white-on-white it used to be vanished on the
  /// light theme, which made the reserved strip look like a layout gap.
  Widget _placeholder(double height) {
    final on = Theme.of(context).colorScheme.onSurface;
    final ink = on.withValues(alpha: 0.38);
    return Container(
      height: height,
      width: double.infinity,
      color: on.withValues(alpha: 0.04),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.ads_click, size: 16, color: ink),
          const SizedBox(width: 8),
          Text('Ad', style: TextStyle(color: ink, fontSize: 12)),
        ],
      ),
    );
  }
}
