import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import 'widgets/app_loader.dart';
import 'widgets/frosted_bar.dart';
import 'widgets/wallpaper_grid.dart';

const _allCategory = 'all';
const _accent = Color(0xFF6C5CE7);

/// Height of the horizontal category chip row.
const double _categoryBarHeight = 48;

/// Home tab: category filter row + the wallpaper grid.
class HomeTab extends StatefulWidget {
  /// Incremented by the shell each time the Home tab is selected; when it
  /// changes, the category filter resets to "All".
  final int resetSignal;

  const HomeTab({super.key, this.resetSignal = 0});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<Catalog> _future;
  String _selected = _allCategory;

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selecting the Home tab resets the category filter to "All".
    if (oldWidget.resetSignal != widget.resetSignal) _selected = _allCategory;
  }

  void _reload() {
    setState(() {
      _future = WallpaperRepository.instance.fetchCatalog(forceRefresh: true);
    });
  }

  Future<void> _refresh() async {
    final f = WallpaperRepository.instance.fetchCatalog(forceRefresh: true);
    // Block body so the closure returns void (not the assigned Future).
    setState(() {
      _future = f;
    });
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Catalog>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoader();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorRetry(onRetry: _reload);
        }
        final catalog = snapshot.data!;
        final items = _selected == _allCategory
            ? catalog.wallpapers
            : catalog.wallpapers.where((w) => w.category == _selected).toList();

        final categoryBar = _CategoryBar(
          categories: catalog.categories,
          selected: _selected,
          onSelected: (id) => setState(() => _selected = id),
        );

        // Android: simple Column (solid app bar takes its own space).
        if (Platform.isAndroid) {
          return Column(
            children: [
              categoryBar,
              Expanded(
                child: WallpaperGrid(
                  items: items,
                  onRefresh: _refresh,
                  emptyText: 'No wallpapers in this category',
                ),
              ),
            ],
          );
        }

        // iOS: grid fills the tab and scrolls behind the translucent app bar;
        // the category chips float in a frosted header just below it. With
        // extendBodyBehindAppBar, MediaQuery.padding.top already equals the app
        // bar's bottom (status bar + toolbar) — no extra kToolbarHeight.
        final topInset = MediaQuery.of(context).padding.top;
        return Stack(
          children: [
            Positioned.fill(
              child: WallpaperGrid(
                items: items,
                onRefresh: _refresh,
                emptyText: 'No wallpapers in this category',
                topPadding: topInset + _categoryBarHeight,
              ),
            ),
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: FrostedBar(child: categoryBar),
            ),
          ],
        );
      },
    );
  }
}

/// Horizontal chip row: a pinned "All" chip + auto-scrolling category chips.
///
/// The category chips slowly drift to the end and back (a marquee) so users
/// notice there are more topics; "All" stays fixed on the left. Auto-scroll
/// pauses while the user touches the row and resumes after a short idle. It is
/// skipped when reduced-motion is on or all chips already fit on screen.
class _CategoryBar extends StatefulWidget {
  final List<WallpaperCategory> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<_CategoryBar> {
  final ScrollController _scroll = ScrollController();
  bool _autoOn = false;
  bool _looping = false;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void didUpdateWidget(covariant _CategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New categories (pull-to-refresh) change the scroll extent — restart.
    if (oldWidget.categories.length != widget.categories.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    }
  }

  void _maybeStart() {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    _autoOn = true;
    _runLoop();
  }

  /// Ping-pong the scroll offset end-to-end at a slow, steady speed.
  Future<void> _runLoop() async {
    if (_looping) return;
    _looping = true;
    while (mounted && _autoOn && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) break; // everything fits — nothing to scroll
      final target = _scroll.offset < max / 2 ? max : 0.0;
      final ms = ((target - _scroll.offset).abs() / 28 * 1000)
          .clamp(2000, 40000)
          .toInt(); // ~28 px/s
      await _scroll.animateTo(
        target,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeInOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    _looping = false;
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Pinned "All" — never scrolls.
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Center(
              child: _CategoryChip(
                label: 'All',
                selected: widget.selected == _allCategory,
                onTap: () => widget.onSelected(_allCategory),
              ),
            ),
          ),
          // Auto-scrolling categories. Touching pauses; releasing resumes.
          Expanded(
            child: Listener(
              onPointerDown: (_) {
                _autoOn = false;
                _resumeTimer?.cancel();
                // Stop the in-flight marquee instantly so THIS tap lands on a
                // chip. Otherwise the moving list wins the gesture arena and the
                // first tap only halts the scroll (selection needs a 2nd tap).
                if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
              },
              onPointerUp: (_) {
                _resumeTimer?.cancel();
                _resumeTimer = Timer(const Duration(seconds: 3), _maybeStart);
              },
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: widget.categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final c = widget.categories[index];
                  return Center(
                    child: _CategoryChip(
                      label: c.name,
                      selected: widget.selected == c.id,
                      onTap: () => widget.onSelected(c.id),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A category chip: liquid [GlassChip] on iOS, a plain solid pill on Android
/// (no glass shader — keeps the tab bar light and jank-free).
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return GlassChip(label: label, selected: selected, onTap: onTap);
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text('Couldn\'t load catalog', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
