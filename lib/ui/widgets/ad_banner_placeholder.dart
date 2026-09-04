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
/// The [AdWidget] is mounted the moment the ad object exists, not once it has
/// loaded. That order is load-bearing: `BannerAd.load` only sends its request
/// from the platform view's creation callback, so a widget that waited for
/// "loaded" before mounting the view would wait forever. Until the ad paints,
/// the view is 1dp tall and sits invisibly over the placeholder.
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

  @override
  void initState() {
    super.initState();
    // Skip entirely when ads are hidden (e.g. store screenshots).
    if (AdService.adsHidden) return;
    // Wait until the SDK is up and consent is applied before requesting.
    AdService.instance.adsAllowed.then((allowed) {
      if (!mounted) return;
      setState(() => _adsPossible = allowed);
      if (allowed) unawaited(_setup());
    });
  }

  /// Reserves the banner's height, then kicks off the first load.
  Future<void> _setup() async {
    if (_setupStarted) return;
    _setupStarted = true;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = BannerAdSize.inline(width: width, maxHeight: _maxHeight);
    try {
      final height = await size.getCalculatedHeight();
      if (!mounted) return;
      setState(() => _reservedHeight = height);
    } catch (_) {
      // Keep [_fallbackHeight]; a few pixels off beats no banner at all.
    }

    final ad = BannerAd(adSize: size);
    ad.loadStateStream.listen(_onLoadState);
    _ad = ad;
    await _load();
  }

  Future<void> _load() async {
    final ad = _ad;
    if (ad == null || !mounted) return;
    _attempts++;
    try {
      await ad.load(AdRequest(adUnitId: AdService.instance.bannerUnitId));
    } catch (_) {
      _onFailed();
    }
  }

  void _onLoadState(BannerAdLoadState state) {
    if (!mounted) return;
    if (state is BannerAdLoadStateLoaded) {
      _retryTimer?.cancel();
      setState(() {
        _loaded = true;
        _reservedHeight = state.height;
      });
    } else if (state is BannerAdLoadStateError) {
      _onFailed();
    }
  }

  void _onFailed() {
    if (!mounted) return;
    setState(() => _loaded = false);
    if (_attempts >= _maxAttempts) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryAfter, _load);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ad?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ads hidden -> take up no space at all (clean screenshots).
    if (AdService.adsHidden) return const SizedBox.shrink();
    // Resolved to "never" -> same, no dead strip at the bottom of the screen.
    if (_adsPossible == false) return const SizedBox.shrink();

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

  Widget _placeholder(double height) => Container(
        height: height,
        width: double.infinity,
        color: Colors.white10,
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.ads_click, size: 16, color: Colors.white38),
            SizedBox(width: 8),
            Text('Ad', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
}
