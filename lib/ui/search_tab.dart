import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import 'widgets/app_loader.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/wallpaper_grid.dart';

/// Height of the search header: 8 + GlassSearchBar (44) + 8.
const double _searchHeaderHeight = 60;

/// Search tab: a glass search bar on top + matching wallpapers below.
/// Embedded in the bottom-nav shell (no scaffold of its own).
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late Future<Catalog> _future;
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Wallpaper> _filter(Catalog c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return c.wallpapers;
    return c.wallpapers
        .where((w) =>
            w.title.toLowerCase().contains(q) ||
            w.category.toLowerCase().contains(q) ||
            w.tags.any((t) => t.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final grid = FutureBuilder<Catalog>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoader();
        }
        final catalog = snapshot.data;
        if (catalog == null) return const SizedBox.shrink();
        return WallpaperGrid(
          items: _filter(catalog),
          emptyText: 'Nothing found',
          topPadding: _headerTopInset(context),
        );
      },
    );

    // Both platforms: the grid fills the tab (edge-to-edge) and scrolls behind
    // the floating chrome; the search field floats just below the title row.
    final topInset = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        Positioned.fill(child: grid),
        Positioned(
          top: topInset + kTopChrome,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _searchField(),
          ),
        ),
      ],
    );
  }

  /// Grid top inset: status bar + floating title row + search header height.
  double _headerTopInset(BuildContext context) =>
      MediaQuery.of(context).padding.top + kTopChrome + _searchHeaderHeight;

  /// Search input: liquid [GlassSearchBar] on iOS, a solid theme-aware field
  /// on Android (no glass shader — jank-free; near-opaque so it stays readable
  /// while floating over the photos).
  Widget _searchField() {
    if (!Platform.isAndroid) {
      return GlassSearchBar(
        controller: _controller,
        placeholder: 'Search wallpapers...',
        onChanged: (v) => setState(() => _query = v),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = dark ? Colors.white54 : Colors.black45;
    return TextField(
      controller: _controller,
      onChanged: (v) => setState(() => _query = v),
      style: TextStyle(color: dark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search wallpapers...',
        hintStyle: TextStyle(color: hint),
        prefixIcon: Icon(Icons.search, color: hint),
        filled: true,
        fillColor: dark ? const Color(0xF21C1C26) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
