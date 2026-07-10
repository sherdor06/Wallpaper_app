import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Capped on-disk image caches so the cache never grows unbounded (wallpaper
/// full-size images are large — up to a few MB each). `flutter_cache_manager`
/// automatically evicts the oldest entries once a cap is reached, so this *is*
/// the app's automatic cache clearing — no manual action needed.
///
/// Two pools, because their sizes differ a lot:
///   - [thumbs]: many small grid thumbnails.
///   - [full]:  a few large full-size images (tightly capped).
class AppCache {
  AppCache._();

  /// Grid thumbnails — small, so we can keep more of them.
  static final CacheManager thumbs = CacheManager(
    Config(
      'wp_thumbs',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 300,
    ),
  );

  /// Full-size (up to 4K) images — large, so tightly capped and short-lived.
  /// ~40 objects keeps the disk footprint bounded (auto-evicted).
  static final CacheManager full = CacheManager(
    Config(
      'wp_full',
      stalePeriod: const Duration(days: 3),
      maxNrOfCacheObjects: 40,
    ),
  );

  /// Empties both pools (Settings → Clear cache).
  static Future<void> clear() async {
    await Future.wait([thumbs.emptyCache(), full.emptyCache()]);
  }
}
