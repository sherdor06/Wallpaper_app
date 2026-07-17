import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wallpaper.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/favorites_service.dart';
import '../services/image_cache.dart';
import '../services/remote_config_service.dart';
import '../services/unlock_service.dart';
import '../services/wallpaper_service.dart';
import 'widgets/badges.dart';

class DetailPage extends StatefulWidget {
  final Wallpaper wallpaper;

  const DetailPage({super.key, required this.wallpaper});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _busy = false;
  double _progress = 0;

  /// Immersive preview: tapping the image hides all chrome and the system bars
  /// so the wallpaper is shown full-screen. Tapping again restores them.
  bool _immersive = false;

  Wallpaper get _w => widget.wallpaper;

  /// A 4K wallpaper that hasn't been unlocked yet needs a rewarded ad first.
  /// Skipped entirely when the `rewarded_required_for_4k` Remote Config flag is
  /// off — then all 4K wallpapers are free to use.
  bool get _locked =>
      _w.is4k &&
      RemoteConfigService.instance.rewardedRequiredFor4k &&
      !UnlockService.instance.isUnlocked(_w.id);

  /// Ensures a 4K wallpaper is unlocked (via a rewarded ad) before proceeding.
  /// Returns true if the action may continue. Grants access when ads are
  /// unavailable so a missing/failed ad never blocks the user.
  Future<bool> _ensureUnlocked() async {
    if (!_locked) return true;
    final ok = await AdService.instance.showRewardedToUnlock();
    if (ok) {
      await UnlockService.instance.unlock(_w.id);
      AnalyticsService.logRewardedUnlock(_w.id);
      if (mounted) setState(() {});
      return true;
    }
    _snack('Kept locked — watch the short video to unlock 4K');
    return false;
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.logWallpaperView(_w.id, category: _w.category);
  }

  @override
  void dispose() {
    // Restore the system bars when leaving the preview.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _applyImage(WallpaperTarget target) async {
    final wasLocked = _locked;
    if (!await _ensureUnlocked()) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await WallpaperService.instance.setImageWallpaper(
        _w,
        target: target,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      AnalyticsService.logWallpaperSet(_w.id, target: target.value);
      // Interstitial after apply — but not right after a rewarded (no double ad).
      if (!wasLocked) await AdService.instance.maybeShowInterstitial();
      _snack('Wallpaper set (${target.value})');
    } on PlatformException catch (e) {
      _snack('Error: ${e.message}');
    } catch (_) {
      _snack('Something went wrong');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadToGallery() async {
    final wasLocked = _locked;
    if (!await _ensureUnlocked()) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await WallpaperService.instance.downloadToGallery(
        _w,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      AnalyticsService.logWallpaperDownload(_w.id);
      if (!wasLocked) await AdService.instance.maybeShowInterstitial();
      _snack('Saved to gallery');
    } catch (_) {
      _snack('Couldn\'t save');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// iOS main action: save to Photos + hint how to set it as wallpaper.
  Future<void> _saveToPhotos() async {
    final wasLocked = _locked;
    if (!await _ensureUnlocked()) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await WallpaperService.instance.downloadToGallery(
        _w,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      AnalyticsService.logWallpaperDownload(_w.id);
      if (!wasLocked) await AdService.instance.maybeShowInterstitial();
      _snack('Saved! Open Photos → Share → Use as Wallpaper');
    } on PlatformException catch (e) {
      // Surface the real reason (helps diagnose Simulator/permission issues).
      _snack(e.code == 'PERMISSION_DENIED'
          ? 'Allow Photos access in Settings to save'
          : 'Save failed: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyLive() async {
    if (!await _ensureUnlocked()) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      await WallpaperService.instance.setLiveWallpaper(
        _w,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      AnalyticsService.logWallpaperSet(_w.id, target: 'live');
      // The system live-wallpaper preview opens; the user confirms there.
      _snack('Tap "Set wallpaper" in the preview');
    } on PlatformException catch (e) {
      _snack(e.code == 'NOT_IMPLEMENTED'
          ? 'Live wallpaper is Android-only for now'
          : 'Couldn\'t set live wallpaper');
    } catch (_) {
      _snack('Couldn\'t set live wallpaper');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    const fade = Duration(milliseconds: 200);
    // Decode the preview only at screen resolution, not full 4K — this keeps
    // memory low and avoids OOM crashes on very large wallpapers.
    final decodeWidth = (MediaQuery.of(context).size.width *
            MediaQuery.of(context).devicePixelRatio)
        .round()
        .clamp(720, 1600);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Wallpaper image — tap toggles the immersive (chrome-free) preview.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleImmersive,
            child: Hero(
              tag: _w.id,
              child: CachedNetworkImage(
                imageUrl: _w.fullUrl,
                cacheManager: AppCache.full,
                memCacheWidth: decodeWidth,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 48)),
              ),
            ),
          ),

          // Top bar (back / title / download / favorite) — fades out in preview.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: _immersive,
              child: AnimatedOpacity(
                opacity: _immersive ? 0 : 1,
                duration: fade,
                child: _buildTopBar(),
              ),
            ),
          ),

          // Bottom control panel — fades out in preview.
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: _immersive,
              child: AnimatedOpacity(
                opacity: _immersive ? 0 : 1,
                duration: fade,
                child: _buildControls(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Transparent top bar over the wallpaper (replaces the Scaffold AppBar so it
  /// can fade in/out with the immersive preview).
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  _w.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: _busy ? null : _downloadToGallery,
              ),
              ListenableBuilder(
                listenable: FavoritesService.instance,
                builder: (context, _) {
                  final fav = FavoritesService.instance.isFavorite(_w.id);
                  return IconButton(
                    tooltip: 'Favorite',
                    icon: Icon(
                      fav ? Icons.favorite : Icons.favorite_border,
                      color: fav ? const Color(0xFFE53935) : Colors.white,
                    ),
                    onPressed: () => FavoritesService.instance.toggle(_w.id),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    // Subtle gradient scrim for legibility over the wallpaper (not glass).
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // LIVE / resolution badges, above the action buttons.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_w.isLive) const WallpaperBadge.live(),
                if (_w.isLive) const SizedBox(width: 6),
                WallpaperBadge(label: _w.resolution),
              ],
            ),
            if (_locked) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.lock_outline, size: 15, color: Colors.white70),
                  SizedBox(width: 6),
                  Text('4K — watch a short video to unlock',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (_busy && _progress > 0 && _progress < 1) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _progress, minHeight: 4),
              ),
              const SizedBox(height: 16),
            ],
            if (_w.isLive)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _applyLive,
                  icon: const Icon(Icons.play_circle_fill),
                  label: Text(_busy ? 'Loading...' : 'Set live wallpaper'),
                ),
              )
            else if (defaultTargetPlatform == TargetPlatform.iOS)
              // iOS can't set the wallpaper programmatically — offer Save to Photos.
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _saveToPhotos,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_busy ? 'Saving...' : 'Save to Photos'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _ApplyButton(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      primary: true,
                      onPressed: _busy ? null : () => _applyImage(WallpaperTarget.home),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ApplyButton(
                      icon: Icons.lock_rounded,
                      label: 'Lock',
                      onPressed: _busy ? null : () => _applyImage(WallpaperTarget.lock),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ApplyButton(
                      icon: Icons.smartphone_rounded,
                      label: 'Both',
                      onPressed: _busy ? null : () => _applyImage(WallpaperTarget.both),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A wallpaper-apply button. [primary] uses a filled style; others are tonal.
class _ApplyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onPressed;

  const _ApplyButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
  }
}
