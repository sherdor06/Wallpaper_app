import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../services/search_service.dart';
import '../widgets/floating_chrome.dart';
import 'search_body.dart';

/// Search as its own screen: the field in the floating row, the
/// [SearchBody] under it.
///
/// Two homes. Android and iOS before 26 push it from the search button in
/// the home chrome, with a back button beside the field. iOS 26+ keeps it as
/// the tab bar's fifth tab ([asTab]): no back button, and the field waits
/// for a tap rather than raising the keyboard on every visit.
class SearchPage extends StatefulWidget {
  final bool asTab;
  const SearchPage({super.key, this.asTab = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  late final Future<Catalog> _catalog = WallpaperRepository.instance
      .fetchCatalog();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String q) {
    if (_controller.text != q) {
      _controller.text = q;
      _controller.selection = TextSelection.collapsed(offset: q.length);
    }
    setState(() => _query = q);
  }

  /// A chip, a recent, or the keyboard's search key: worth remembering.
  void _commit(String q) {
    _set(q);
    unawaited(SearchService.instance.remember(q));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FutureBuilder<Catalog>(
            future: _catalog,
            builder: (context, snap) {
              final catalog = snap.data;
              if (catalog == null) return const SizedBox.shrink();
              return SearchBody(
                catalog: catalog,
                query: _query,
                onQuery: _commit,
                topPadding: top + kTopChrome + 8,
              );
            },
          ),
          Positioned(
            top: top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                if (!widget.asTab) ...[
                  ChromeIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 18,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ChromeSearchField(
                    controller: _controller,
                    autofocus: !widget.asTab,
                    onChanged: (q) => setState(() => _query = q),
                    onSubmitted: _commit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
