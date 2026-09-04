import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../services/favorites_service.dart';
import 'widgets/app_loader.dart';
import 'widgets/empty_state.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/wallpaper_grid.dart';

/// Favorites tab: shows only the wallpapers the user has favorited.
///
/// Rebuilds when [FavoritesService] changes (the parent shell listens to it),
/// so toggling a heart updates this list immediately.
class FavoritesTab extends StatefulWidget {
  /// Sends the user to the catalog — the empty state's way out.
  ///
  /// A callback rather than a `Navigator.pop`: this is a tab inside an
  /// [IndexedStack], not a pushed route, so there is nothing here to pop. Only
  /// the shell knows how to change tabs.
  final VoidCallback? onBrowse;

  const FavoritesTab({super.key, this.onBrowse});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  late Future<Catalog> _future;

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
  }

  Future<void> _refresh() async {
    final f = WallpaperRepository.instance.fetchCatalog(forceRefresh: true);
    // Block body so the closure returns void: an arrow would return the
    // assigned Future, which setState asserts against.
    setState(() {
      _future = f;
    });
    await f;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when favorites change so (un)favoriting updates the list live.
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        return FutureBuilder<Catalog>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoader();
            }
            final catalog = snapshot.data;
            final favs = FavoritesService.instance;
            final items = (catalog?.wallpapers ?? const [])
                .where((w) => favs.isFavorite(w.id))
                .toList();
            // No header here — start just below the floating title row while
            // still scrolling behind it.
            final topInset = MediaQuery.paddingOf(context).top;
            return WallpaperGrid(
              items: items,
              onRefresh: _refresh,
              emptyText: 'No favorites yet',
              empty: EmptyState(
                animation: 'assets/anim/empty_d_heart.json',
                headline: 'No favorites yet',
                subLine: 'Tap the heart on any wallpaper to keep it here.',
                fallbackIcon: Icons.favorite_border,
                actionLabel: widget.onBrowse == null ? null : 'Browse wallpapers',
                onAction: widget.onBrowse,
              ),
              topPadding: topInset + kTopChrome + 8,
            );
          },
        );
      },
    );
  }
}
