import 'package:flutter/material.dart';

import '../../models/collection.dart';
import '../../models/wallpaper.dart';
import '../widgets/floating_chrome.dart';
import '../widgets/wallpaper_thumb.dart';
import '../widgets/wallpaper_grid.dart';
import 'collection_accent.dart';

/// Pushes [collection]'s page. Shared by every card, row header and chip
/// that leads to a collection, so the transition is the same everywhere.
void openCollection(BuildContext context, Collection collection) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CollectionPage(collection: collection)),
  );
}

/// One collection's wallpapers, pushed from a card, a section's "See all" or
/// the spotlight.
///
/// A cover, the name and tagline over it, then the grid — with a row of mood
/// chips between them when the items carry moods (see [Wallpaper.moods]).
/// The header collapses into a plain title bar as the grid scrolls, so the
/// page is the cover for a second and a grid after that.
///
/// The collection's own accent (see [CollectionAccent]) colours the bar under
/// the name and the selected chip, nothing else: the page belongs to the
/// collection, the app still belongs to the app.
class CollectionPage extends StatefulWidget {
  final Collection collection;

  const CollectionPage({super.key, required this.collection});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  /// Selected mood, or null for everything.
  String? _mood;

  /// Fewest items a mood needs before it earns a chip: a chip that filters
  /// down to two wallpapers is a dead end, not a filter.
  static const _minPerMood = 6;

  /// Moods offered as chips, in [kMoodOrder]. Empty — no chip row — unless at
  /// least two moods qualify; one chip alone is just "All" said twice.
  late final List<String> _moods = () {
    final counts = <String, int>{};
    for (final w in widget.collection.items) {
      for (final m in w.moods) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }
    final out = [
      for (final m in kMoodOrder)
        if ((counts[m] ?? 0) >= _minPerMood) m,
    ];
    return out.length >= 2 ? out : const <String>[];
  }();

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final accent = CollectionAccent.of(collection.id);
    final mood = _mood;
    final items = mood == null
        ? collection.items
        : collection.items.where((w) => w.moods.contains(mood)).toList();
    final bottom = MediaQuery.paddingOf(context).bottom + 8;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _Header(collection: collection, accent: accent),
          if (_moods.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _MoodBar(
                moods: _moods,
                selected: mood,
                accent: accent,
                onChanged: (m) => setState(() => _mood = m),
                background: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          SliverWallpaperGrid(items: items),
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }
}

/// The collapsing cover. Built on [SliverAppBar] for the pinning and the
/// status-bar handling; everything visible is drawn here, because the stock
/// [FlexibleSpaceBar] scales its title and positions it per platform, and
/// this header needs the name to sit still and fade.
class _Header extends StatelessWidget {
  final Collection collection;
  final CollectionAccent accent;

  const _Header({required this.collection, required this.accent});

  static const _expanded = 300.0;

  @override
  Widget build(BuildContext context) {
    final name = collection.name;
    final tagline = collection.tagline;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // The name sits on the part of the scrim that has become the page, so
    // it takes the page's text colour — white on the dark theme, near-black
    // on the light one, where white would sink into the background.
    final onBg = Theme.of(context).colorScheme.onSurface;
    final top = MediaQuery.paddingOf(context).top;
    final minHeight = kToolbarHeight + top;
    final maxHeight = _expanded + top;

    // The layers that do not change as the bar collapses, built once here
    // rather than in the LayoutBuilder below, which runs every scroll frame.
    final cover = WallpaperThumb(
      wallpaper: collection.cover,
      memCacheWidth: 800,
      fallback: bg,
    );
    // Two scrims: a light one at the top so the back button reads, and one
    // dissolving into the page so the name does.
    final scrim = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.3, 0.65, 1],
          colors: [
            bg.withValues(alpha: 0.35),
            bg.withValues(alpha: 0),
            bg.withValues(alpha: 0.55),
            bg,
          ],
        ),
      ),
    );

    return SliverAppBar(
      expandedHeight: _expanded,
      pinned: true,
      stretch: true,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 16 + kTopBarHeight + 8,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Center(
          child: ChromeIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // 1 fully open, 0 collapsed to the toolbar.
          final t =
              ((constraints.maxHeight - minHeight) / (maxHeight - minHeight))
                  .clamp(0.0, 1.0);
          final open = Curves.easeIn.transform(t);
          return Stack(
            fit: StackFit.expand,
            children: [
              cover,
              scrim,
              // Solid as the bar collapses, so the pinned toolbar is a bar
              // and not a strip of somebody's photo.
              ColoredBox(color: bg.withValues(alpha: 1 - open)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Opacity(
                  opacity: open,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: accent.gradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onBg,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (tagline != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onBg.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // The collapsed title, centred in the toolbar like every other
              // pushed page's.
              Positioned(
                top: top,
                left: 0,
                right: 0,
                height: kToolbarHeight,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1 - open,
                    child: Center(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: onBg,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pinned chip row under the header: "All" plus one chip per mood.
class _MoodBar extends SliverPersistentHeaderDelegate {
  final List<String> moods;
  final String? selected;
  final CollectionAccent accent;
  final ValueChanged<String?> onChanged;
  final Color background;

  const _MoodBar({
    required this.moods,
    required this.selected,
    required this.accent,
    required this.onChanged,
    required this.background,
  });

  static const _height = 50.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_MoodBar old) =>
      old.selected != selected ||
      old.moods != moods ||
      old.background != background;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ColoredBox(
      color: background,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            accent: accent,
            onTap: () => onChanged(null),
          ),
          for (final m in moods) ...[
            const SizedBox(width: 8),
            _Chip(
              label: moodLabel(m),
              selected: selected == m,
              accent: accent,
              onTap: () => onChanged(m),
            ),
          ],
        ],
      ),
    );
  }
}

/// One mood chip. Selection cross-fades between the idle tint and the
/// accent — both plain colours, so the transition really interpolates (a
/// gradient against no gradient cannot, and used to blink) — and the chip
/// gives a little under the finger while it is held.
class _Chip extends StatefulWidget {
  final String label;
  final bool selected;
  final CollectionAccent accent;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _pressed = false;

  static const _settle = Duration(milliseconds: 260);
  static const _press = Duration(milliseconds: 110);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = dark ? const Color(0x14FFFFFF) : const Color(0x0F000000);
    final idleText = dark ? const Color(0xD9FFFFFF) : Colors.black87;
    final selected = widget.selected;
    final accent = widget.accent;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: _press,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _settle,
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.color : idle,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? accent.color : idle),
          ),
          child: AnimatedDefaultTextStyle(
            duration: _settle,
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: selected ? accent.onColor : idleText,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
