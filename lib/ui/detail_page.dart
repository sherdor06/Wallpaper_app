import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/favorites_service.dart';
import '../services/image_cache.dart';
import '../services/remote_config_service.dart';
import '../services/unlock_service.dart';
import '../services/wallpaper_service.dart';
import 'widgets/badges.dart';
import 'widgets/floating_chrome.dart';

class DetailPage extends StatefulWidget {
  final Wallpaper wallpaper;

  const DetailPage({super.key, required this.wallpaper});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _busy = false;
  double _progress = 0;
  final Random _rng = Random();

  /// Immersive preview: tapping the image hides all chrome and the system bars
  /// so the wallpaper is shown full-screen. Tapping again restores them.
  bool _immersive = false;

  Wallpaper get _w => widget.wallpaper;

  /// A high-resolution wallpaper that hasn't been unlocked yet needs a rewarded
  /// ad first. Each tier has its own Remote Config flag
  /// (`rewarded_required_for_4k` / `_fhd`); turning one off makes that tier free.
  bool get _locked {
    final rc = RemoteConfigService.instance;
    final gated = (_w.is4k && rc.rewardedRequiredFor4k) ||
        (_w.isFhd && rc.rewardedRequiredForFhd);
    return gated && !UnlockService.instance.isUnlocked(_w.id);
  }

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
    _snack('Kept locked — watch the short video to unlock');
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

  /// A professional confirmation / info dialog. Returns `true` when the user
  /// taps the confirm action, and `false` on cancel or dismissal.
  Future<bool> _confirm({
    required IconData icon,
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Icon(icon, size: 30, color: scheme.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Human-readable name of the screen a wallpaper is applied to (Android).
  static String _targetName(WallpaperTarget target) {
    switch (target) {
      case WallpaperTarget.home:
        return 'Home screen';
      case WallpaperTarget.lock:
        return 'Lock screen';
      case WallpaperTarget.both:
        return 'Home and Lock screens';
    }
  }

  /// Opens a random wallpaper from the catalog, replacing the current page so
  /// the back stack stays shallow. A gentle cross-fade keeps it polished.
  Future<void> _openRandom() async {
    final all = (await WallpaperRepository.instance.fetchCatalog()).wallpapers;
    if (all.length < 2) return;
    var next = _w;
    while (next.id == _w.id) {
      next = all[_rng.nextInt(all.length)];
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => DetailPage(wallpaper: next),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _applyImage(WallpaperTarget target) async {
    // Confirm intent before changing the user's wallpaper (Android).
    final confirmed = await _confirm(
      icon: Icons.wallpaper_rounded,
      title: 'Set as wallpaper?',
      message:
          'This will replace your current wallpaper on the ${_targetName(target)}.',
      confirmLabel: 'Set wallpaper',
    );
    if (!confirmed) return;
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
    // iOS can't set the wallpaper directly — explain the download step first.
    final confirmed = await _confirm(
      icon: Icons.download_rounded,
      title: 'Download wallpaper?',
      message:
          'This wallpaper will be saved to your Photos. To set it, open Photos, '
          'tap the Share icon, then choose “Use as Wallpaper”.',
      confirmLabel: 'Download',
    );
    if (!confirmed) return;
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

          // Random-wallpaper button — pinned to a fixed spot so it never shifts
          // when the panel below changes height between wallpapers (4K hint,
          // progress bar, live vs image buttons). Thumb-friendly on the right;
          // liquid glass on iOS, simple solid circle on Android.
          Positioned(
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 224,
            child: IgnorePointer(
              ignoring: _immersive,
              child: AnimatedOpacity(
                opacity: _immersive ? 0 : 1,
                duration: fade,
                child: ChromeIconButton(
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Random wallpaper',
                  size: 58,
                  iconSize: 28,
                  onTap: () {
                    if (_busy) return;
                    // Tactile + audible feedback on press.
                    HapticFeedback.selectionClick();
                    SystemSound.play(SystemSoundType.click);
                    _openRandom();
                  },
                ),
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
              const SizedBox(height: 12),
              _UnlockPill(resolution: _w.resolution),
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
                height: 54,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _saveToPhotos,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _AdBadgedIcon(
                    icon: Icons.download_rounded,
                    showBadge: _locked,
                  ),
                  label: Text(
                    _busy
                        ? 'Saving...'
                        : _locked
                            ? 'Save to Photos  (Ad)'
                            : 'Save to Photos',
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
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
                      locked: _locked,
                      onPressed: _busy ? null : () => _applyImage(WallpaperTarget.home),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ApplyButton(
                      icon: Icons.lock_rounded,
                      label: 'Lock',
                      locked: _locked,
                      onPressed: _busy ? null : () => _applyImage(WallpaperTarget.lock),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ApplyButton(
                      icon: Icons.smartphone_rounded,
                      label: 'Both',
                      locked: _locked,
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
/// When [locked], a small play badge marks the action as rewarded-ad gated.
class _ApplyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final bool locked;
  final VoidCallback? onPressed;

  const _ApplyButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AdBadgedIcon(icon: icon, showBadge: locked, size: 22),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (locked)
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text('(Ad)',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500)),
          ),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
  }
}

/// An icon with an optional small "play" badge, marking a rewarded-ad action.
class _AdBadgedIcon extends StatelessWidget {
  final IconData icon;
  final bool showBadge;
  final double size;

  const _AdBadgedIcon({
    required this.icon,
    required this.showBadge,
    this.size = 21,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!showBadge) return Icon(icon, size: size);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: size),
        Positioned(
          right: -5,
          top: -3,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              // Ring so the badge reads clearly on any button fill.
              border: Border.all(color: scheme.onPrimary, width: 1.2),
            ),
            child: Icon(Icons.play_arrow_rounded,
                size: 8.5, color: scheme.onPrimary),
          ),
        ),
      ],
    );
  }
}

/// Explains that a short rewarded video unlocks this wallpaper — shown above
/// the action buttons so the cost is clear *before* the user taps.
class _UnlockPill extends StatelessWidget {
  final String resolution;

  const _UnlockPill({required this.resolution});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 14, 6),
      decoration: BoxDecoration(
        // Dark scrim like [WallpaperBadge] — stays readable over any wallpaper,
        // light or dark. The accent lives in the play button, not the fill.
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.play_arrow_rounded,
                size: 14, color: scheme.onPrimary),
          ),
          const SizedBox(width: 9),
          Text(
            'Watch a short video to unlock $resolution',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
