import 'dart:async';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/favorites_service.dart';
import '../services/history_service.dart';
import '../services/image_cache.dart';
import '../services/remote_config_service.dart';
import '../services/unlock_service.dart';
import '../services/wallpaper_service.dart';
import 'widgets/badges.dart';
import 'widgets/floating_chrome.dart';

const _accent = Color(0xFF6C5CE7);
const _accentDim = Color(0xFF5A4BC8);
const _accentLight = Color(0xFF8B7BF0);
const _success = Color(0xFF7EE2AC);
const _warning = Color(0xFFF0A35E);

/// What the price chip says.
///
/// Deliberately not a duration: the AdMob SDK reports neither the length of a
/// loaded ad nor the time left in one — `RewardedAd.show` takes only
/// `onUserEarnedReward` — so any number here would be a guess presented as fact.
///
/// Singular, and phrased as the action rather than the ad format ("Rewarded
/// ads" is AdMob's name for the category): this chip is a price on one tap, and
/// a plural would promise a queue of ads that never comes.
const _chipIdleLabel = 'Watch ad';
const _chipPlayingLabel = 'Playing';

/// How long the save button holds its terminal states before returning to idle.
const _doneHold = Duration(milliseconds: 2500);
const _cancelledHold = Duration(milliseconds: 3000);


/// Pixel dimensions implied by a catalog `resolution` label. The catalog stores
/// only the label (`4K` / `FHD` / `HD`) — no width, height or byte size — so the
/// badge row derives dimensions here and fetches the size separately.
const _dimensions = <String, String>{
  '4K': '2160 × 3840',
  'FHD': '1080 × 1920',
  'HD': '720 × 1280',
};

/// The save control's five states. `locked` doubles as the idle state: when the
/// wallpaper is not gated it simply renders without the price chip.
enum _SaveState { locked, watching, downloading, done, cancelled }

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

  _SaveState _saveState = _SaveState.locked;

  /// Returns [_SaveState.done] / [_SaveState.cancelled] to idle after their hold.
  Timer? _holdTimer;

  /// Byte size of the full-resolution file, once a HEAD request resolves it.
  /// Null until then (and if the request fails) — the badge row omits the size
  /// rather than guessing.
  int? _fileBytes;

  /// Which screen the last Android apply targeted, so the done sub-line can
  /// name it back to the user. Null only until the first apply of the session.
  WallpaperTarget? _activeTarget;

  Wallpaper get _w => widget.wallpaper;

  /// Whether the rewarded gate applies to this wallpaper at all, regardless of
  /// whether it has already been unlocked. Each tier has its own Remote Config
  /// flag (`rewarded_required_for_4k` / `_fhd`); turning one off makes that tier
  /// free. Everything that mentions the ad to the user hangs off this.
  bool get _gated {
    // Nothing to charge with while the ad SDK has no credentials (or ads are
    // switched off): `showRewardedToUnlock` grants the unlock immediately in
    // that state, so the gate would announce a cost it never collects. Dropping
    // it here removes the whole affordance at once — the "Watch ad" chip, the
    // "Playing" state, the pause before the download, and the "unlocked" badge.
    if (!AdService.instance.rewardedAvailable) return false;
    final rc = RemoteConfigService.instance;
    return (_w.is4k && rc.rewardedRequiredFor4k) ||
        (_w.isFhd && rc.rewardedRequiredForFhd);
  }

  /// A gated wallpaper the user hasn't paid for yet — a rewarded ad comes first.
  bool get _locked => _gated && !UnlockService.instance.isUnlocked(_w.id);

  /// Ensures a gated wallpaper is unlocked (via a rewarded ad) before
  /// proceeding. Grants access when ads are unavailable, so a missing or failed
  /// ad never blocks the user.
  ///
  /// Drives the save control through [_SaveState.watching] and reports whether
  /// the action may continue. The refusal is rendered in the panel — the button
  /// itself says the video wasn't finished — so nothing is surfaced as a snack.
  Future<bool> _ensureUnlocked() async {
    if (!_locked) return true;
    _setSaveState(_SaveState.watching);
    final ok = await AdService.instance.showRewardedToUnlock();
    if (ok) {
      await UnlockService.instance.unlock(_w.id);
      AnalyticsService.logRewardedUnlock(_w.id);
      if (mounted) setState(() {});
      return true;
    }
    _setSaveState(_SaveState.cancelled, revertAfter: _cancelledHold);
    return false;
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.logWallpaperView(_w.id, category: _w.category);
    _fetchFileSize();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    // Restore the system bars when leaving the preview.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Reads the full-resolution file's size from its `Content-Length`. The
  /// catalog carries no size field, and a HEAD costs one small round trip, so
  /// the badge row can show a real number instead of an estimate. Failure is
  /// silent — [_fileBytes] stays null and the badge drops the size.
  Future<void> _fetchFileSize() async {
    try {
      final res = await Dio().head<void>(_w.fullUrl);
      final len = int.tryParse(res.headers.value('content-length') ?? '');
      if (len != null && len > 0 && mounted) setState(() => _fileBytes = len);
    } catch (_) {
      // Offline or the CDN withheld the header — leave it unknown.
    }
  }

  /// Moves the save control to [next], cancelling whatever hold was pending.
  /// [revertAfter] schedules the return to idle for the terminal states.
  void _setSaveState(_SaveState next, {Duration? revertAfter}) {
    if (!mounted) return;
    _holdTimer?.cancel();
    setState(() => _saveState = next);
    if (revertAfter != null) {
      _holdTimer = Timer(revertAfter, () {
        if (mounted) setState(() => _saveState = _SaveState.locked);
      });
    }
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
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
    // Shuffling is the app's tightest loop and the screen is about to change
    // anyway, which makes this the least intrusive interstitial slot — and the
    // one that keeps the format earning now that almost every wallpaper is
    // rewarded-gated (the apply path alone fires far too rarely).
    await AdService.instance.maybeShowInterstitialOnBrowse();
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

  /// Applies the wallpaper. The target sheet already named the screen and is
  /// dismissible, so there is no second confirmation dialog here.
  Future<void> _applyImage(WallpaperTarget target) async {
    if (!await _ensureUnlocked()) return;
    // The unlock above can hold a full-screen rewarded ad for half a minute,
    // and the user is free to leave during it. Touching state after that would
    // be setState() on a disposed widget.
    if (!mounted) return;
    _setSaveState(_SaveState.downloading);
    setState(() {
      _busy = true;
      _progress = 0;
      _activeTarget = target; // the fill runs in the button that was tapped
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
      HistoryService.instance.add(_w.id);
      // Unconditional: AdService's shared full-screen cooldown suppresses this
      // when the unlock above just played a rewarded ad, so there is no need to
      // gate it on the wallpaper having been unlocked.
      await AdService.instance.maybeShowInterstitial();
      _setSaveState(_SaveState.done, revertAfter: _doneHold);
    } on PlatformException catch (e) {
      _setSaveState(_SaveState.locked);
      _snack('Error: ${e.message}');
    } catch (_) {
      _setSaveState(_SaveState.locked);
      _snack('Something went wrong');
    } finally {
      // _activeTarget deliberately survives this block: the done sub-line names
      // the screen back to the user, and that line is still on show for
      // [_doneHold] after the apply returns. Clearing it here made every apply
      // read "Applied to your home screen" regardless of what was picked. The
      // next apply overwrites it, and no other state reads it.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadToGallery() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return; // see _applyImage — the ad gives the user time to leave
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
      HistoryService.instance.add(_w.id);
      await AdService.instance.maybeShowInterstitial();
      _snack('Saved to gallery');
    } catch (_) {
      _snack('Couldn\'t save');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// iOS main action: save to Photos.
  ///
  /// No confirmation step — the button already states what it will do and what
  /// it costs, and the panel spells out the Photos → Share route once the file
  /// has landed. A dialog in between only asked the user to agree twice.
  Future<void> _saveToPhotos() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return; // see _applyImage — the ad gives the user time to leave
    _setSaveState(_SaveState.downloading);
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
      HistoryService.instance.add(_w.id);
      await AdService.instance.maybeShowInterstitial();
      // Success is reported inside the panel, not as a snack.
      _setSaveState(_SaveState.done, revertAfter: _doneHold);
    } on PlatformException catch (e) {
      // Real errors still snack — the panel only speaks about the ad/save flow.
      _setSaveState(_SaveState.locked);
      _snack(e.code == 'PERMISSION_DENIED'
          ? 'Allow Photos access in Settings to save'
          : 'Save failed: ${e.message ?? e.code}');
    } catch (e) {
      _setSaveState(_SaveState.locked);
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyLive() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return; // see _applyImage — the ad gives the user time to leave
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
      HistoryService.instance.add(_w.id);
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
            _buildBadgeRow(),
            const SizedBox(height: 13),
            if (_w.isLive)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _applyLive,
                  icon: const Icon(Icons.play_circle_fill),
                  label: Text(_busy ? 'Loading...' : 'Set live wallpaper'),
                ),
              )
            else if (defaultTargetPlatform == TargetPlatform.iOS)
              // iOS can't set the wallpaper programmatically — offer Save to Photos.
              _buildSaveButton(
                idleLabel: 'Save to Photos',
                doneLabel: 'Saved to Photos',
                onTap: _saveToPhotos,
              )
            else
              // Android takes the same single control; which screen it applies
              // to is asked in a sheet instead of spending three buttons on it.
              _buildSaveButton(
                idleLabel: 'Set as wallpaper',
                doneLabel: 'Wallpaper set',
                onTap: _pickTargetAndApply,
              ),
            const SizedBox(height: 11),
            // Always rendered, so the panel height never moves between states —
            // the shuffle FAB above it must stay put.
            _buildSubLine(),
          ],
        ),
      ),
    );
  }

  /// Resolution / dimensions / size. The first badge turns into a `… unlocked`
  /// confirmation while the file downloads — but only where an unlock was ever
  /// required, otherwise it would celebrate passing a gate that wasn't there.
  Widget _buildBadgeRow() {
    final unlockedNow = _gated &&
        (_saveState == _SaveState.downloading ||
            _saveState == _SaveState.done);
    final detail = [
      _dimensions[_w.resolution],
      if (_fileBytes != null) _formatBytes(_fileBytes!),
    ].whereType<String>().join(' · ');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_w.isLive) ...[
          const WallpaperBadge.live(),
          const SizedBox(width: 6),
        ],
        _PanelBadge(
          label: unlockedNow ? '${_w.resolution} unlocked' : _w.resolution,
          highlight: unlockedNow,
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(width: 6),
          _PanelBadge(label: detail),
        ],
      ],
    );
  }

  static String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  /// The single glass action control, used on both platforms. The frame is
  /// built once and only its interior cross-fades, so the button cannot resize
  /// as states change.
  Widget _buildSaveButton({
    required String idleLabel,
    required String doneLabel,
    required VoidCallback onTap,
  }) {
    final done = _saveState == _SaveState.done;
    final busy = _saveState == _SaveState.watching ||
        _saveState == _SaveState.downloading;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Ink(
            decoration: BoxDecoration(
              gradient: done
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _success.withValues(alpha: 0.30),
                        _success.withValues(alpha: 0.14),
                      ],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x42FFFFFF), Color(0x1FFFFFFF)],
                    ),
              border: Border.all(
                color: done
                    ? _success.withValues(alpha: 0.55)
                    : const Color(0x57FFFFFF),
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 22,
                    offset: Offset(0, 8)),
              ],
            ),
            child: Stack(
              children: [
                // Progress runs behind the interior, clipped to the frame.
                if (_saveState == _SaveState.downloading)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                colors: [_accent, _accentLight]),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _saveInterior(
                        idleLabel: idleLabel, doneLabel: doneLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveInterior({
    required String idleLabel,
    required String doneLabel,
  }) {
    final chip = _saveChip();
    final padding = EdgeInsets.only(left: 18, right: chip == null ? 18 : 8);
    final glyph = defaultTargetPlatform == TargetPlatform.iOS
        ? Icons.download_rounded
        : Icons.wallpaper_rounded;

    late final IconData icon;
    late final String label;
    late final double opacity;
    switch (_saveState) {
      case _SaveState.watching:
        icon = glyph;
        label = idleLabel;
        opacity = 0.62;
      case _SaveState.downloading:
        icon = glyph;
        label = 'Downloading…';
        opacity = 1;
      case _SaveState.done:
        icon = Icons.check_rounded;
        label = doneLabel;
        opacity = 1;
      case _SaveState.locked:
      case _SaveState.cancelled:
        icon = glyph;
        label = idleLabel;
        opacity = 1;
    }

    return Padding(
      key: ValueKey(_saveState),
      padding: padding,
      child: Row(
        children: [
          if (_saveState == _SaveState.done)
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: _success, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  size: 15, color: Color(0xFF10331F)),
            )
          else
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: opacity)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: opacity),
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.15,
              ),
            ),
          ),
          if (_saveState == _SaveState.downloading)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          if (chip != null) chip,
        ],
      ),
    );
  }

  /// The price chip: what the wallpaper costs, stated once. Absent entirely once
  /// the wallpaper is unlocked — no ad affordance survives the unlock.
  Widget? _saveChip() {
    if (_saveState == _SaveState.watching) {
      return _chipBox(
        color: _accentDim,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              backgroundColor: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 7),
          _chipText(_chipPlayingLabel),
        ]),
      );
    }
    final idle =
        _saveState == _SaveState.locked || _saveState == _SaveState.cancelled;
    if (!idle || !_locked) return null;
    return _chipBox(
      color: _accent,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        _chipText(_chipIdleLabel),
      ]),
    );
  }

  static Widget _chipBox({required Color color, required Widget child}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(11)),
        child: child,
      );

  static Widget _chipText(String s) => Text(
        s,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      );

  /// Asks which screen to apply to, then applies. The sheet names the target
  /// explicitly, so it stands in for the old confirmation dialog rather than
  /// being followed by one.
  Future<void> _pickTargetAndApply() async {
    final target = await showModalBottomSheet<WallpaperTarget>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text('Set as wallpaper',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Replaces your current wallpaper',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final (target, icon, label) in const [
              (WallpaperTarget.home, Icons.home_rounded, 'Home screen'),
              (WallpaperTarget.lock, Icons.lock_rounded, 'Lock screen'),
              (
                WallpaperTarget.both,
                Icons.smartphone_rounded,
                'Home and Lock screens'
              ),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(ctx).pop(target),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _applyImage(target);
  }

  /// One line under the button. Always present — only its text changes — so the
  /// panel keeps a fixed height across every state.
  Widget _buildSubLine() {
    late final String text;
    late final Color color;
    late final FontWeight weight;
    switch (_saveState) {
      case _SaveState.watching:
        text = 'Saves automatically when the video ends';
        color = Colors.white.withValues(alpha: 0.60);
        weight = FontWeight.w500;
      case _SaveState.done:
        text = defaultTargetPlatform == TargetPlatform.iOS
            ? 'Photos → Share → “Use as Wallpaper”'
            : 'Applied to your ${_targetName(_activeTarget ?? WallpaperTarget.home).toLowerCase()}';
        color = Colors.white.withValues(alpha: 0.72);
        weight = FontWeight.w500;
      case _SaveState.cancelled:
        text = 'Video not finished — ${_w.resolution} stays locked';
        color = _warning;
        weight = FontWeight.w600;
      case _SaveState.locked:
      case _SaveState.downloading:
        text = _restingSubLine();
        color = Colors.white.withValues(alpha: 0.60);
        weight = FontWeight.w500;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        text,
        key: ValueKey(text),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, fontWeight: weight, color: color),
      ),
    );
  }

  /// The line shown before the tap and while the file transfers.
  ///
  /// The two platforms promise different things and cannot share one sentence:
  /// iOS puts a file in Photos, Android writes the wallpaper itself onto a
  /// screen the target sheet asks about. Both keep "full resolution" — that is
  /// the part the user is deciding on.
  String _restingSubLine() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Saved at full resolution to your Photos';
    }
    final target = _activeTarget;
    if (_saveState == _SaveState.downloading && target != null) {
      return 'Applying at full resolution to your '
          '${_targetName(target).toLowerCase()}';
    }
    return 'Full resolution — you choose Home or Lock screen';
  }
}

/// Badge used in the detail panel. Unlike [WallpaperBadge] it can switch to a
/// success treatment, which the row uses to confirm the unlock in place.
class _PanelBadge extends StatelessWidget {
  final String label;
  final bool highlight;

  const _PanelBadge({required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(14),
        border: highlight
            ? Border.all(color: _success.withValues(alpha: 0.50))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight ? _success : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}


