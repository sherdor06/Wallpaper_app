import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../services/history_service.dart';
import 'detail_page.dart';
import 'widgets/app_loader.dart';
import 'widgets/wallpaper_tile.dart';

/// Archive: the wallpapers the user has applied or saved, most recent first.
///
/// Tiles are smaller than the main grid (3 columns) since this is a lookup
/// screen — tapping one reopens it, and "Clear" empties the history.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late Future<Catalog> _future;

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.delete_sweep_outlined, size: 30),
        title: const Text('Clear archive?', textAlign: TextAlign.center),
        content: const Text(
          'This only clears the list of recently used wallpapers. Your favorites '
          'and any wallpaper you have set stay untouched.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await HistoryService.instance.clear();
  }

  void _open(Wallpaper w) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(wallpaper: w)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HistoryService.instance,
      builder: (context, _) {
        final history = HistoryService.instance;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Archive'),
            actions: [
              if (!history.isEmpty)
                IconButton(
                  tooltip: 'Clear archive',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _confirmClear,
                ),
            ],
          ),
          body: FutureBuilder<Catalog>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppLoader();
              }
              if (history.isEmpty) return const _Empty();

              // Resolve ids against the catalog, preserving history order.
              // Wallpapers removed from the catalog are skipped.
              final byId = {
                for (final w in snapshot.data?.wallpapers ?? const <Wallpaper>[])
                  w.id: w,
              };
              final items = [
                for (final id in history.ids)
                  if (byId[id] != null) byId[id]!,
              ];
              if (items.isEmpty) return const _Empty();

              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                    10, 10, 10, 10 + MediaQuery.of(context).padding.bottom),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 9 / 16,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => WallpaperTile(
                  wallpaper: items[i],
                  onTap: () => _open(items[i]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 46, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text('No wallpapers yet',
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 4),
          Text(
            'Wallpapers you set or save appear here.',
            style: TextStyle(
                color: Theme.of(context).hintColor.withValues(alpha: 0.7),
                fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
