import 'dart:async';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/favorites_service.dart';
import '../services/history_service.dart';
import '../services/image_cache.dart';
import '../services/push_service.dart';
import '../services/remote_config_service.dart';
import '../services/review_service.dart';
import '../services/unlock_service.dart';
import '../services/wallpaper_service.dart';
import 'accent.dart';
import 'widgets/badges.dart';
import 'widgets/floating_chrome.dart';

const _accentDim = Color(0xFF5A4BC8);
const _success = Color(0xFF7EE2AC);
const _warning = Color(0xFFF0A35E);

// Not a duration: the ad SDK reports neither an ad's length nor the time left.
const _chipIdleLabel = 'Watch ad';
const _chipPlayingLabel = 'Playing';

const _doneHold = Duration(milliseconds: 2500);
const _cancelledHold = Duration(milliseconds: 3000);

// The catalog stores only the resolution label, not the pixel size.
const _dimensions = <String, String>{
  '4K': '2160 × 3840',
  'FHD': '1080 × 1920',
  'HD': '720 × 1280',
};

/// `locked` doubles as idle: an ungated wallpaper simply shows no price chip.
enum _SaveState { locked, watching, downloading, done, cancelled }

class DetailPage extends StatefulWidget {
  final Wallpaper wallpaper;

  const DetailPage({super.key, required this.wallpaper});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _busy = false;
  // Outside setState: Dio reports progress many times a second, and only the
  // fill bar and the percentage read it.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final Random _rng = Random();
  bool _immersive = false;
  _SaveState _saveState = _SaveState.locked;
  Timer? _holdTimer;
  int? _fileBytes;
  WallpaperTarget? _activeTarget;

  Wallpaper get _w => widget.wallpaper;

  bool get _gated {
    // Without ad credentials the unlock is granted at once, so the gate would
    // announce a cost it never collects.
    if (!AdService.instance.rewardedAvailable) return false;
    final rc = RemoteConfigService.instance;
    return (_w.is4k && rc.rewardedRequiredFor4k) ||
        (_w.isFhd && rc.rewardedRequiredForFhd);
  }

  bool get _locked => _gated && !UnlockService.instance.isUnlocked(_w.id);

  @override
  void initState() {
    super.initState();
    AnalyticsService.logWallpaperView(_w.id, category: _w.category);
    unawaited(_fetchFileSize());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _progress.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _fetchFileSize() async {
    final bytes = await WallpaperService.instance.fileSize(_w.fullUrl);
    if (bytes != null && mounted) setState(() => _fileBytes = bytes);
  }

  /// Shares a link rather than the file: a link opens the wallpaper in the
  /// friend's app, or sends them to the store.
  Future<void> _share() async {
    final url = DeepLinkService.shareUrlFor(_w.id);
    // iPad throws without an origin rect.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        uri: url,
        subject: _w.title,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    AnalyticsService.logShare(_w.id);
  }

  Future<void> _openRandom() async {
    final all = (await WallpaperRepository.instance.fetchCatalog()).wallpapers;
    if (all.length < 2) return;
    var next = _w;
    while (next.id == _w.id) {
      next = all[_rng.nextInt(all.length)];
    }
    // The least intrusive interstitial slot: the screen changes anyway.
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

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

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

  /// Plays the rewarded ad for a locked wallpaper. False when it was not
  /// finished; a missing or failed ad never blocks the user.
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

  /// Unlocks, then marks the page busy. False when the ad was not finished,
  /// or the user left the page while it played.
  Future<bool> _begin({bool panel = false}) async {
    if (!await _ensureUnlocked() || !mounted) return false;
    if (panel) _setSaveState(_SaveState.downloading);
    setState(() {
      _busy = true;
      _progress.value = 0;
    });
    return true;
  }

  void _end() {
    if (mounted) setState(() => _busy = false);
  }

  // The download outlives the page, and a disposed notifier throws.
  void _onProgress(double value) {
    if (mounted) _progress.value = value;
  }

  /// Runs an apply or a save, then what follows one: history, the
  /// notification prompt, a possible interstitial and the review sheet. With
  /// [panel] the save control reports the outcome; otherwise [doneSnack] does.
  Future<void> _runSave(
    Future<void> Function() job, {
    bool panel = false,
    String? doneSnack,
    required String failSnack,
  }) async {
    if (!await _begin(panel: panel)) return;
    try {
      await job();
      unawaited(HistoryService.instance.add(_w.id));
      unawaited(PushService.instance.maybeAskPermission());
      final adPlayed = await AdService.instance.maybeShowInterstitial();
      if (panel) {
        _setSaveState(_SaveState.done, revertAfter: _doneHold);
      } else if (doneSnack != null) {
        _snack(doneSnack);
      }
      if (!adPlayed) unawaited(ReviewService.instance.maybeAsk());
    } catch (e) {
      if (panel) _setSaveState(_SaveState.locked);
      _snack(
        e is PlatformException && e.code == 'PERMISSION_DENIED'
            ? 'Allow photo access in Settings to save'
            : failSnack,
      );
    } finally {
      _end();
    }
  }

  Future<void> _applyImage(WallpaperTarget target) {
    _activeTarget = target;
    return _runSave(
      () async {
        await WallpaperService.instance.setImageWallpaper(
          _w,
          target: target,
          onProgress: _onProgress,
        );
        AnalyticsService.logWallpaperSet(_w.id, target: target.name);
      },
      panel: true,
      failSnack: "Couldn't set the wallpaper",
    );
  }

  Future<void> _saveToGallery({bool panel = false}) => _runSave(
        () async {
          await WallpaperService.instance.downloadToGallery(
            _w,
            onProgress: _onProgress,
          );
          AnalyticsService.logWallpaperDownload(_w.id);
        },
        panel: panel,
        doneSnack: 'Saved to gallery',
        failSnack: "Couldn't save",
      );

  Future<void> _saveToPhotos() => _saveToGallery(panel: true);

  // No interstitial or prompts here: the system preview is already on top.
  Future<void> _applyLive() async {
    if (!await _begin()) return;
    try {
      await WallpaperService.instance.setLiveWallpaper(
        _w,
        onProgress: _onProgress,
      );
      AnalyticsService.logWallpaperSet(_w.id, target: 'live');
      unawaited(HistoryService.instance.add(_w.id));
      _snack('Tap "Set wallpaper" in the preview');
    } catch (_) {
      _snack("Couldn't set live wallpaper");
    } finally {
      _end();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _targetName(WallpaperTarget target) => switch (target) {
        WallpaperTarget.home => 'Home screen',
        WallpaperTarget.lock => 'Lock screen',
        WallpaperTarget.both => 'Home and Lock screens',
      };

  @override
  Widget build(BuildContext context) {
    const fade = Duration(milliseconds: 200);
    // Decoded at screen resolution, not full 4K, to keep memory low.
    final decodeWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(720, 1600);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
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
          // Pinned, so it never moves when the panel changes height.
          Positioned(
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 224,
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
                    unawaited(HapticFeedback.selectionClick());
                    unawaited(SystemSound.play(SystemSoundType.click));
                    unawaited(_openRandom());
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share, color: Colors.white),
                onPressed: _share,
              ),
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: _busy ? null : _saveToGallery,
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
                  label: Text(_busy ? 'Loading…' : 'Set live wallpaper'),
                ),
              )
            else if (defaultTargetPlatform == TargetPlatform.iOS)
              // iOS apps cannot set the wallpaper.
              _buildSaveButton(
                idleLabel: 'Save to Photos',
                doneLabel: 'Saved to Photos',
                onTap: _saveToPhotos,
              )
            else
              _buildSaveButton(
                idleLabel: 'Set as wallpaper',
                doneLabel: 'Wallpaper set',
                onTap: _pickTargetAndApply,
              ),
            const SizedBox(height: 11),
            // Always rendered: the panel keeps one height in every state.
            _buildSubLine(),
          ],
        ),
      ),
    );
  }

  /// The first badge confirms the unlock while the file downloads, but only
  /// where there was a gate to pass.
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

  /// The frame is built once and only its interior cross-fades, so the button
  /// never resizes between states.
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
                  unawaited(HapticFeedback.selectionClick());
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
                if (_saveState == _SaveState.downloading)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: kAccentGradient,
                          ),
                        ),
                        builder: (context, value, child) =>
                            FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value.clamp(0.0, 1.0),
                          child: child,
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
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (context, value, _) => Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (chip != null) chip,
        ],
      ),
    );
  }

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
      color: kAccent,
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
            for (final (target, icon) in const [
              (WallpaperTarget.home, Icons.home_rounded),
              (WallpaperTarget.lock, Icons.lock_rounded),
              (WallpaperTarget.both, Icons.smartphone_rounded),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(_targetName(target)),
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

/// Unlike [WallpaperBadge], it can switch to a success look to confirm the
/// unlock in place.
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
