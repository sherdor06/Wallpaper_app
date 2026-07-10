import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../services/favorites_service.dart';
import 'widgets/app_loader.dart';
import 'widgets/wallpaper_grid.dart';

/// Favorites tab: shows only the wallpapers the user has favorited.
///
/// Rebuilds when [FavoritesService] changes (the parent shell listens to it),
/// so toggling a heart updates this list immediately.
class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

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
    setState(() => _future = f);
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
            // No header here — just clear the translucent app bar. With
            // extendBodyBehindAppBar, padding.top already equals the bar bottom.
            final topInset = MediaQuery.of(context).padding.top;
            return WallpaperGrid(
              items: items,
              onRefresh: _refresh,
              emptyText: 'No favorites yet',
              topPadding: topInset,
            );
          },
        );
      },
    );
  }
}
