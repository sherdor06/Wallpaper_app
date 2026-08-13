import 'package:applovin_max/applovin_max.dart';
import 'package:flutter/material.dart';

import '../../services/ad_service.dart';

/// Bottom banner (always shown — ads are the only monetization).
///
/// [MaxAdView] is a real widget rather than an overlay, so it sits in the
/// Scaffold's bottom column like any other child; MAX's own `createBanner`
/// pins to the screen edge and would float over the nav bar instead.
///
/// While the banner loads (or if it fails) a neutral placeholder of the same
/// height keeps the layout from shifting — the nav bar sits directly above it.
class AdBannerPlaceholder extends StatefulWidget {
  const AdBannerPlaceholder({super.key});

  @override
  State<AdBannerPlaceholder> createState() => _AdBannerPlaceholderState();
}

class _AdBannerPlaceholderState extends State<AdBannerPlaceholder> {
  /// Standard MAX banner height. Fixed so the placeholder and the loaded ad
  /// occupy the same space.
  static const _height = 50.0;

  bool _allowed = false;
  bool _failed = false;

  /// Null until [AdService.adsAllowed] answers. `false` means no ad will ever
  /// arrive in this session — the SDK is off, or its credentials are still
  /// placeholders — and the widget collapses instead of reserving space.
  ///
  /// That distinction matters for shipping ahead of the ad network: the app can
  /// go to the store before AppLovin approves it, and users must not be left
  /// looking at an empty grey strip where a banner will one day be.
  bool? _adsPossible;

  @override
  void initState() {
    super.initState();
    // Skip entirely when ads are hidden (e.g. store screenshots).
    if (AdService.adsHidden) return;
    // Wait until the SDK is up and consent is resolved before mounting the view.
    AdService.instance.adsAllowed.then((allowed) {
      if (!mounted) return;
      setState(() {
        _adsPossible = allowed;
        _allowed = allowed;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ads hidden -> take up no space at all (clean screenshots).
    if (AdService.adsHidden) return const SizedBox.shrink();
    // Resolved to "never" -> same, no dead strip at the bottom of the screen.
    if (_adsPossible == false) return const SizedBox.shrink();

    if (_allowed && !_failed) {
      return SizedBox(
        height: _height,
        child: MaxAdView(
          adUnitId: AdService.instance.bannerUnitId,
          adFormat: AdFormat.banner,
          listener: AdViewAdListener(
            onAdLoadedCallback: (_) {
              if (_failed && mounted) setState(() => _failed = false);
            },
            // No fill: fall back to the placeholder rather than leaving a hole.
            // MAX keeps retrying behind the view, so a later fill recovers.
            onAdLoadFailedCallback: (_, __) {
              if (mounted) setState(() => _failed = true);
            },
            onAdClickedCallback: (_) {},
            onAdExpandedCallback: (_) {},
            onAdCollapsedCallback: (_) {},
          ),
        ),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() => Container(
        height: _height,
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
