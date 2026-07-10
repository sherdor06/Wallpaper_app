import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_service.dart';

/// Bottom AdMob banner (always shown — ads are the only monetization).
/// While the banner loads (or if it fails), a neutral placeholder keeps the
/// layout stable. The unit id comes from [AdService] (real in release, test in
/// debug); the banner only loads once ad consent has been resolved.
class AdBannerPlaceholder extends StatefulWidget {
  const AdBannerPlaceholder({super.key});

  @override
  State<AdBannerPlaceholder> createState() => _AdBannerPlaceholderState();
}

class _AdBannerPlaceholderState extends State<AdBannerPlaceholder> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Skip loading entirely when ads are hidden (e.g. store screenshots).
    if (AdService.adsHidden) return;
    // Wait until ad consent is resolved before requesting the banner.
    AdService.instance.adsAllowed.then((allowed) {
      if (allowed && mounted) _loadBanner();
    });
  }

  void _loadBanner() {
    final banner = BannerAd(
      adUnitId: AdService.instance.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _banner = banner;
    banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ads hidden -> take up no space at all (clean screenshots).
    if (AdService.adsHidden) return const SizedBox.shrink();

    if (_loaded && _banner != null) {
      return SizedBox(
        width: _banner!.size.width.toDouble(),
        height: _banner!.size.height.toDouble(),
        child: AdWidget(ad: _banner!),
      );
    }

    // Loading / failed -> neutral placeholder keeps the layout stable.
    return Container(
      height: 56,
      width: double.infinity,
      color: Colors.white10,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.ads_click, size: 16, color: Colors.white38),
          SizedBox(width: 8),
          Text('Ad', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}
