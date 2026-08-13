import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        showCupertinoModalPopup;
import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../services/history_service.dart';
import 'detail_page.dart';
import 'widgets/app_loader.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/wallpaper_grid.dart' show gridColumnsFor;
import 'widgets/wallpaper_tile.dart';

const _accent = Color(0xFF6C5CE7);

/// Archive: the wallpapers the user has applied or saved, most recent first.
///
/// Tiles are smaller than the main grid (3 columns) since this is a lookup
/// screen — tapping one reopens it. Entries can be removed one batch at a time
/// via multi-select, or all at once.
///
/// The overflow menu is platform-specific: iOS 26+ gets the native Liquid Glass
/// [CNPopupMenuButton] (the same menu style as Messages), everything else gets
/// the Material [PopupMenuButton].
///
/// On iOS this is a tab inside [HomeShell] rather than a pushed route, so it
/// reports selection mode through [onSelectingChanged]: the shell's nav bar has
/// to get out of the way, otherwise it covers the selection bar this page hangs
/// off its own Scaffold. Android pushes it as a normal route and passes nothing.
class ArchivePage extends StatefulWidget {
  /// Fired when multi-select is entered or left. Only the embedded (tab) use
  /// needs it — a pushed route sits above the shell and covers it anyway.
  final ValueChanged<bool>? onSelectingChanged;

  const ArchivePage({super.key, this.onSelectingChanged});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late Future<Catalog> _future;

  /// Multi-select mode: tiles toggle instead of opening.
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  /// How many archive entries currently resolve against the catalog — the menu
  /// labels its destructive entry with this, so it is kept in step in build().
  int _visibleCount = 0;

  @override
  void initState() {
    super.initState();
    _future = WallpaperRepository.instance.fetchCatalog();
  }

  void _enterSelection() {
    setState(() {
      _selecting = true;
      _selected.clear();
    });
    widget.onSelectingChanged?.call(true);
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    widget.onSelectingChanged?.call(false);
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  /// Material confirmation for destructive actions (Android / iOS < 26).
  /// iOS 26+ uses [_confirmSheet] instead.
  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Icon(icon, size: 30),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Applies the removal. [_runDestructive] confirms before calling this.
  Future<void> _removeSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    await HistoryService.instance.removeAll(_selected);
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $n from archive')),
    );
  }

  /// iOS destructive confirmation: an action sheet, the platform's own companion
  /// to a menu — it slides up from the edge (never a centred dialog) and states
  /// what is about to happen, with the destructive choice in red.
  Future<bool> _confirmSheet({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: CupertinoActionSheet(
          title: Text(title),
          message: Text(message),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  /// Runs the destructive action for the current mode, confirming first.
  Future<void> _runDestructive() async {
    final n = _selecting ? _selected.length : _visibleCount;
    if (n == 0) return;
    if (_selecting) {
      final ok = isIOS26OrAbove
          ? await _confirmSheet(
              title: n == 1 ? 'Remove wallpaper?' : 'Remove $n wallpapers?',
              message: 'They leave the archive only — your favorites and the '
                  'wallpaper you have set stay untouched.',
              confirmLabel: n == 1 ? 'Remove' : 'Remove $n',
            )
          : await _confirmDestructive(
              title: n == 1 ? 'Remove wallpaper?' : 'Remove $n wallpapers?',
              message: 'They leave the archive only — your favorites and the '
                  'wallpaper you have set stay untouched.',
              confirmLabel: 'Remove',
              icon: Icons.delete_outline,
            );
      if (ok) await _removeSelected();
      return;
    }
    final ok = isIOS26OrAbove
        ? await _confirmSheet(
            title: 'Clear archive?',
            message: 'This clears the list of recently used wallpapers only. '
                'Your favorites and any wallpaper you have set stay untouched.',
            confirmLabel: 'Clear All ($n)',
          )
        : await _confirmDestructive(
            title: 'Clear archive?',
            message: 'This clears the list of recently used wallpapers only. '
                'Your favorites and any wallpaper you have set stay untouched.',
            confirmLabel: 'Clear All',
            icon: Icons.delete_sweep_outlined,
          );
    if (!ok) return;
    await HistoryService.instance.clear();
    if (mounted) _exitSelection();
  }

  void _open(Wallpaper w) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(wallpaper: w)),
    );
  }

  /// The overflow menu, shown while browsing. Selection mode has no top-bar
  /// actions — they live in [_selectionBar] at the bottom instead.
  ///
  /// iOS 26+ gets the native Liquid Glass menu; its destructive entry is marked
  /// `isDestructive`, so iOS paints the label itself in the system red.
  Widget _overflowMenu(int count) {
    final has = count > 0;
    final error = Theme.of(context).colorScheme.error;

    if (isIOS26OrAbove) {
      // Entries are built in step with their handlers so indices can never
      // drift as the menu changes.
      final items = <CNPopupMenuEntry>[
        CNPopupMenuItem(
          label: 'Select',
          icon: const CNSymbol('checkmark.circle'),
          enabled: has,
        ),
        const CNPopupMenuDivider(),
        CNPopupMenuItem(
          label: has ? 'Clear All ($count)' : 'Clear All',
          icon: CNSymbol('trash', color: error),
          enabled: has,
          // Applies UIMenuElement.Attributes.destructive, so iOS paints the
          // label itself in the system red — not just the glyph.
          isDestructive: true,
        ),
      ];
      final handlers = <VoidCallback?>[_enterSelection, null, _runDestructive];

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: CNPopupMenuButton.icon(
          buttonIcon: const CNSymbol('ellipsis', size: 18),
          buttonStyle: CNButtonStyle.glass,
          size: 36,
          tint: _accent,
          items: items,
          onSelected: (i) {
            if (i >= 0 && i < handlers.length) handlers[i]?.call();
          },
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      enabled: has,
      onSelected: (v) => v == 'select' ? _enterSelection() : _runDestructive(),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'select',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline),
            title: Text('Select'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_sweep_outlined, color: error),
            title: Text(has ? 'Clear All ($count)' : 'Clear All',
                style: TextStyle(color: error)),
          ),
        ),
      ],
    );
  }

  AppBar _buildAppBar(List<Wallpaper> items) {
    if (!_selecting) {
      return AppBar(
        title: const Text('Archive'),
        actions: [_overflowMenu(items.length)],
      );
    }
    // Selection actions live in the bottom bar (Photos-style), so the top bar
    // stays down to just leaving the mode and the running count.
    return AppBar(
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text(
          _selected.isEmpty ? 'Select items' : '${_selected.length} selected'),
    );
  }

  /// Bottom action bar shown while selecting — the pattern Photos/Files use,
  /// keeping the destructive action within thumb reach instead of the far top
  /// corner. Liquid glass on iOS 26+, a solid Material bar elsewhere.
  Widget _selectionBar(List<Wallpaper> items) {
    final scheme = Theme.of(context).colorScheme;
    final n = _selected.length;
    final allSelected = items.isNotEmpty && n == items.length;
    final removeLabel = n == 0 ? 'Remove' : 'Remove ($n)';

    void toggleAll() => setState(() {
          _selected
            ..clear()
            ..addAll(allSelected ? const <String>[] : items.map((w) => w.id));
        });

    final Widget bar;
    if (isIOS26OrAbove) {
      bar = CNGlassButtonGroup(
        spacing: 10,
        buttons: [
          CNButtonData(
            label: allSelected ? 'Deselect All' : 'Select All',
            icon: CNSymbol(
                allSelected ? 'checkmark.circle.fill' : 'checkmark.circle'),
            onPressed: items.isEmpty ? null : toggleAll,
            enabled: items.isNotEmpty,
            tint: _accent,
          ),
          CNButtonData(
            label: removeLabel,
            icon: CNSymbol('trash', color: scheme.error),
            onPressed: n == 0 ? null : _runDestructive,
            enabled: n > 0,
            tint: scheme.error,
          ),
        ],
      );
    } else {
      bar = Row(
        children: [
          TextButton.icon(
            onPressed: items.isEmpty ? null : toggleAll,
            icon: Icon(allSelected
                ? Icons.check_circle
                : Icons.check_circle_outline),
            label: Text(allSelected ? 'Deselect all' : 'Select all'),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: n == 0 ? null : _runDestructive,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: Text(removeLabel),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isIOS26OrAbove
            ? Colors.transparent
            : Theme.of(context).scaffoldBackgroundColor,
        border: isIOS26OrAbove
            ? null
            : Border(
                top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: SafeArea(top: false, child: bar),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HistoryService.instance,
      builder: (context, _) {
        return FutureBuilder<Catalog>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            // Resolve ids against the catalog, preserving history order.
            // Wallpapers removed upstream are skipped rather than left dead.
            final byId = {
              for (final w in snapshot.data?.wallpapers ?? const <Wallpaper>[])
                w.id: w,
            };
            final items = [
              for (final id in HistoryService.instance.ids)
                if (byId[id] != null) byId[id]!,
            ];
            // Kept in a field so the menu's destructive label can read it
            // outside of build (e.g. from _runDestructive).
            _visibleCount = items.length;
            return Scaffold(
              appBar: _buildAppBar(items),
              bottomNavigationBar:
                  _selecting ? _selectionBar(items) : null,
              // Leaving selection mode with the system back gesture feels more
              // natural than popping the whole page.
              body: PopScope(
                canPop: !_selecting,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _exitSelection();
                },
                child: loading
                    ? const AppLoader()
                    : items.isEmpty
                        ? const _Empty()
                        : _buildGrid(items),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGrid(List<Wallpaper> items) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: EdgeInsets.fromLTRB(
            10, 10, 10, 10 + MediaQuery.of(context).padding.bottom),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // Smaller target than the main grid — this is a lookup screen, so it
          // favours seeing more history at once over big previews. Same
          // width-driven rule, so a tablet gets more columns instead of
          // stretched tiles.
          crossAxisCount:
              gridColumnsFor(constraints.maxWidth, target: 130, min: 3, max: 8),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 9 / 16,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final w = items[i];
          final selected = _selected.contains(w.id);
          return _SelectableTile(
            wallpaper: w,
            selecting: _selecting,
            selected: selected,
            onTap: () => _selecting ? _toggle(w.id) : _open(w),
            // Long-press is the familiar way into selection mode on both
            // platforms; it selects the item you pressed.
            onLongPress: () {
              if (!_selecting) _enterSelection();
              _toggle(w.id);
            },
          );
        },
      ),
    );
  }
}

/// A grid tile that can show a selection state on top of [WallpaperTile].
class _SelectableTile extends StatelessWidget {
  final Wallpaper wallpaper;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SelectableTile({
    required this.wallpaper,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: onLongPress,
      child: AnimatedScale(
        scale: selected ? 0.92 : 1,
        duration: const Duration(milliseconds: 140),
        child: Stack(
          fit: StackFit.expand,
          children: [
            WallpaperTile(wallpaper: wallpaper, onTap: onTap),
            if (selecting)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: selected
                        ? Border.all(color: scheme.primary, width: 3)
                        : null,
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.18)
                        : Colors.black.withValues(alpha: 0.15),
                  ),
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 22,
                    color: selected ? scheme.primary : Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ),
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
