import 'package:flutter/material.dart';

import '../../models/wallpaper.dart';
import '../widgets/wallpaper_grid.dart';

/// One category's wallpapers, pushed from a collection card or a section's
/// "See all". A plain pushed page with an app bar, like Archive — the floating
/// chrome belongs to the shell's tabs, and this sits above the shell.
class CategoryPage extends StatelessWidget {
  final String title;
  final List<Wallpaper> items;

  const CategoryPage({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: WallpaperGrid(
        items: items,
        emptyText: 'Nothing here yet',
      ),
    );
  }
}
