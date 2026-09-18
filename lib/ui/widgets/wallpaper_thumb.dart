import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/wallpaper.dart';
import '../../services/image_cache.dart';

/// A wallpaper's thumbnail, cover-fitted, from the shared thumb cache — what
/// every card, row tile and collection cover is built on. Decoded at
/// [memCacheWidth] so a row tile does not hold a full thumb in memory. A
/// dark slab stands in while it loads and stays if it never does; a null
/// [wallpaper] (a collection with nothing in it) is the slab alone.
class WallpaperThumb extends StatelessWidget {
  final Wallpaper? wallpaper;
  final int memCacheWidth;
  final Color fallback;

  const WallpaperThumb({
    super.key,
    required this.wallpaper,
    required this.memCacheWidth,
    this.fallback = const Color(0xFF1B1B22),
  });

  @override
  Widget build(BuildContext context) {
    final w = wallpaper;
    if (w == null) return ColoredBox(color: fallback);
    return CachedNetworkImage(
      imageUrl: w.thumbUrl,
      cacheManager: AppCache.thumbs,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      placeholder: (_, __) => ColoredBox(color: fallback),
      errorWidget: (_, __, ___) => ColoredBox(color: fallback),
    );
  }
}
