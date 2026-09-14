import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../services/home_layout_service.dart';
import 'home/collections_home.dart';
import 'home/editorial_home.dart';
import 'widgets/app_loader.dart';
import 'widgets/floating_chrome.dart';

/// Home tab: loads the catalog once and hands it to whichever layout the user
/// has chosen — curated ([EditorialHome]) or browse ([CollectionsHome]).
///
/// The switch itself lives in the shell's top row, next to the title, and
/// talks to [HomeLayoutService]; this widget only listens. That keeps the
/// chrome in one place and lets either layout be opened directly, with the
/// catalog already in hand, when the choice flips.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<Catalog> _future;

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
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
        // Both layouts scroll edge-to-edge behind the floating title row, so
        // each starts its content just below it.
        final topPadding = MediaQuery.paddingOf(context).top + kTopChrome + 8;

        return ListenableBuilder(
          listenable: HomeLayoutService.instance,
          builder: (context, _) {
            final layout = HomeLayoutService.instance.layout;
            return AnimatedSwitcher(
              // A short fade: enough to make the change feel deliberate,
              // short enough that the pill still feels instant.
              duration: const Duration(milliseconds: 180),
              child: switch (layout) {
                HomeLayout.editorial => EditorialHome(
                    key: const ValueKey(HomeLayout.editorial),
                    catalog: catalog,
                    onRefresh: _refresh,
                    topPadding: topPadding,
                  ),
                HomeLayout.collections => CollectionsHome(
                    key: const ValueKey(HomeLayout.collections),
                    catalog: catalog,
                    onRefresh: _refresh,
                    topPadding: topPadding,
                  ),
              },
            );
          },
        );
      },
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
