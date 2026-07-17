import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../models/wallpaper.dart';
import '../../services/favorites_service.dart';
import '../../services/image_cache.dart';
import 'badges.dart';

/// A single wallpaper cell in the gallery grid.
///
/// Optimization: [CachedNetworkImage] loads the small [Wallpaper.thumbUrl] and,
/// via `memCacheWidth`, keeps it in memory only at the size needed on screen —
/// which significantly reduces RAM usage.
class WallpaperTile extends StatelessWidget {
  final Wallpaper wallpaper;
  final VoidCallback onTap;

  const WallpaperTile({
    super.key,
    required this.wallpaper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            CachedNetworkImage(
              imageUrl: wallpaper.thumbUrl,
              cacheManager: AppCache.thumbs,
              fit: BoxFit.cover,
              // Enough for a grid cell — full resolution isn't needed here.
              memCacheWidth: 360,
              placeholder: (_, __) => const _TilePlaceholder(),
              errorWidget: (_, __, ___) => const _TilePlaceholder(
                child: Icon(Icons.broken_image, color: Colors.white24),
              ),
            ),

            // Top-left: LIVE badge.
            if (wallpaper.isLive)
              const Positioned(top: 8, left: 8, child: WallpaperBadge.live()),

            // Top-right: resolution badge.
            Positioned(
              top: 8,
              right: 8,
              child: WallpaperBadge(label: wallpaper.resolution),
            ),

            // Bottom-right: favorite (heart) button.
            Positioned(
              bottom: 4,
              right: 4,
              child: _FavoriteButton(id: wallpaper.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart button — toggles the wallpaper in/out of favorites when tapped.
class _FavoriteButton extends StatelessWidget {
  final String id;
  const _FavoriteButton({required this.id});

  @override
  Widget build(BuildContext context) {
    // Rebuild this button whenever favorites change, so the heart reflects state
    // immediately regardless of where it was toggled.
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        final fav = FavoritesService.instance.isFavorite(id);
        final heart = Icon(
          fav ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: fav ? const Color(0xFFE53935) : Colors.white,
        );
        if (!Platform.isAndroid) {
          // iOS: liquid-glass round button; a red glow signals the favorited state.
          return GlassIconButton(
            icon: heart,
            size: 38,
            glowColor: fav ? const Color(0xFFE53935) : null,
            onPressed: () => FavoritesService.instance.toggle(id),
          );
        }
        // Android: solid scrim circle — no glass shader cost in every grid cell.
        return GestureDetector(
          onTap: () => FavoritesService.instance.toggle(id),
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0x73000000),
              shape: BoxShape.circle,
            ),
            child: Center(child: heart),
          ),
        );
      },
    );
  }
}

class _TilePlaceholder extends StatelessWidget {
  final Widget? child;
  const _TilePlaceholder({this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      color: Colors.white10,
      alignment: Alignment.center,
      child: child,
    );
  }
}
