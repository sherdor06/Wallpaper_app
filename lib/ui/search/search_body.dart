import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../models/wallpaper.dart';
import '../../services/search_service.dart';
import '../home/collection_accent.dart';
import '../widgets/wallpaper_grid.dart';

/// Everything under the search field, on both platforms.
///
/// No query yet: the last few searches and a set of chips to browse from —
/// the collections and the moods, since those are what search can actually
/// find. With a query: the count, the filters the words resolved to, and
/// the grid. The field itself belongs to the caller (a page on Android, the
/// native tab bar on iOS), which is why this is a body and not a screen.
class SearchBody extends StatelessWidget {
  final Catalog catalog;
  final String query;

  /// A chip or a recent search was tapped: the caller puts it in the field.
  final ValueChanged<String> onQuery;

  /// Room to leave above the content for whatever floats over it.
  final double topPadding;

  const SearchBody({
    super.key,
    required this.catalog,
    required this.query,
    required this.onQuery,
    required this.topPadding,
  });

  /// Collections offered as chips: the ones big enough to be a destination.
  static const _minItems = 12;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 8;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _Browse(catalog: catalog, onQuery: onQuery, topPadding: topPadding);
    }
    final result = SearchService.search(catalog, trimmed);
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: topPadding)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ResultHeader(result: result),
          ),
        ),
        if (result.items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Nothing(query: trimmed),
          )
        else
          SliverWallpaperGrid(items: result.items),
        SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final SearchResult result;
  const _ResultHeader({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = result.items.length;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '$n',
              style: TextStyle(
                  color: scheme.onSurface, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: n == 1 ? ' result' : ' results'),
          ]),
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final f in result.filters)
          _Tag(
            label: f.label,
            color: f.kind == SearchFilterKind.collection
                ? CollectionAccent.of(f.id).color
                : scheme.primary,
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style:
              TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}

class _Nothing extends StatelessWidget {
  final String query;
  const _Nothing({required this.query});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 40, color: scheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Nothing for "$query"',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a collection or a mood — Girly, Nature, Dark, Light.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The empty-query screen: recents, then chips for what search can find.
class _Browse extends StatelessWidget {
  final Catalog catalog;
  final ValueChanged<String> onQuery;
  final double topPadding;
  const _Browse(
      {required this.catalog, required this.onQuery, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final w in catalog.wallpapers) {
      counts[w.category] = (counts[w.category] ?? 0) + 1;
    }
    final collections = [
      for (final c in catalog.categories)
        if ((counts[c.id] ?? 0) >= SearchBody._minItems) c,
    ]..sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));

    return ListenableBuilder(
      listenable: SearchService.instance,
      builder: (context, _) {
        final recent = SearchService.instance.recent;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              16, topPadding, 16, MediaQuery.paddingOf(context).bottom + 16),
          children: [
            if (recent.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(child: _Caps('Recent')),
                  GestureDetector(
                    onTap: SearchService.instance.clearRecent,
                    child: Text(
                      'Clear',
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              for (final r in recent)
                InkWell(
                  onTap: () => onQuery(r),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 18,
                            color: scheme.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurface.withValues(alpha: 0.85),
                                  fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
            ],
            _Caps('Collections'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in collections)
                  _BrowseChip(
                    label: c.name,
                    accent: CollectionAccent.custom(c.id)?.color,
                    onTap: () => onQuery(c.name),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _Caps('Mood'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in kMoodOrder)
                  _BrowseChip(
                      label: moodLabel(m), onTap: () => onQuery(moodLabel(m))),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Caps extends StatelessWidget {
  final String text;
  const _Caps(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
}

class _BrowseChip extends StatelessWidget {
  final String label;
  final Color? accent;
  final VoidCallback onTap;
  const _BrowseChip({required this.label, this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = dark ? const Color(0x14FFFFFF) : const Color(0x0F000000);
    final text = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85);
    return GestureDetector(
      onTap: onTap,
      // No `alignment` here: inside a Wrap that would make the box take the
      // whole line. The row centres its own contents.
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: idle,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: idle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (accent != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    color: text, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
