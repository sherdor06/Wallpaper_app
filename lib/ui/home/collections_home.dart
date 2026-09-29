import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../models/collection.dart';
import '../widgets/wallpaper_thumb.dart';
import '../worlds/worlds_page.dart';
import '../widgets/wallpaper_grid.dart' show gridColumnsFor;
import 'collection_page.dart';

/// The browse home: one card per category, tap into the one you want.
///
/// Replaces the chip row's job with something that can be seen rather than
/// read. Categories are ordered by size, fullest first, and the thin ones are
/// left out altogether (see [Collection.isDestination]).
class CollectionsHome extends StatelessWidget {
  final Catalog catalog;
  final Future<void> Function() onRefresh;
  final double topPadding;

  const CollectionsHome({
    super.key,
    required this.catalog,
    required this.onRefresh,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    final collections = catalog.destinations();
    final bottom = MediaQuery.paddingOf(context).bottom + 8;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topPadding)),
            const SliverToBoxAdapter(child: WorldsDiscoveryCard()),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, bottom),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // Same column rule as the wallpaper grid, so a tablet gets more
                  // cards rather than two enormous ones.
                  crossAxisCount: gridColumnsFor(constraints.maxWidth),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.9,
                ),
                itemCount: collections.length,
                itemBuilder: (context, i) => _CollectionCard(
                  collection: collections[i],
                  onTap: () => openCollection(context, collections[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover image, name, tagline. The cover is [Collection.cover] — the first
/// *titled* wallpaper, since the auto-titled ones are the likeliest to be
/// filed in the wrong category and a Space card wearing a car is worse than
/// no card.
class _CollectionCard extends StatelessWidget {
  final Collection collection;
  final VoidCallback onTap;
  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tagline = collection.tagline;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            WallpaperThumb(wallpaper: collection.cover, memCacheWidth: 360),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.4, 1],
                  colors: [Color(0x000E0E12), Color(0xE00E0E12)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (tagline != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
