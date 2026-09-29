import 'dart:async' show unawaited;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/world_composition.dart';
import '../../services/worlds_service.dart';
import '../accent.dart';
import '../widgets/floating_chrome.dart';
import 'world_scene.dart';
import 'world_studio_page.dart';

void openWorlds(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const WorldsPage()));

/// One entry point shared by both home layouts; the main navigation stays put.
class WorldsDiscoveryCard extends StatelessWidget {
  const WorldsDiscoveryCard({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Semantics(
      button: true,
      label: 'Explore Wavely Worlds',
      child: Material(
        color: const Color(0xFF101729),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openWorlds(context),
          child: SizedBox(
            height: 148,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  WorldComposition.midnight.imagePath,
                  fit: BoxFit.cover,
                  alignment: const Alignment(.5, .12),
                  cacheWidth: 800,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xF5111528),
                        Color(0x95111528),
                        Color(0x20111528),
                      ],
                      stops: [0, .55, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'WAVELY  /  WORLDS',
                              style: TextStyle(
                                color: Color(0xFFCEC3EE),
                                fontSize: 10,
                                letterSpacing: 1.6,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'A little world.\nMade by you.',
                              style: TextStyle(
                                fontFamily: 'InstrumentSerif',
                                fontSize: 30,
                                height: 1.02,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0x33FFFFFF),
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: const Icon(
                          Icons.arrow_outward_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WorldsPage extends StatefulWidget {
  const WorldsPage({super.key});
  @override
  State<WorldsPage> createState() => _WorldsPageState();
}

class _WorldsPageState extends State<WorldsPage> {
  final _service = WorldsService.instance;
  late final _ready = _service.init();
  bool _importing = false;

  Future<void> _open(WorldComposition world) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => WorldStudioPage(world: world)));
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final world = await _service.pickPhoto();
      if (!mounted) {
        if (world != null) await _service.discardDraft(world);
        return;
      }
      if (world != null) await _open(world);
    } on PlatformException catch (e) {
      _message(
        e.code == 'photo_access_denied'
            ? 'Allow photo access in Settings, then try again.'
            : 'Could not open that photo. Please choose another.',
      );
    } catch (_) {
      _message('Could not import that photo. Please choose a smaller image.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _remove(WorldComposition world) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this world?'),
        content: Text(
          '“${world.title}” will be removed from My worlds. Your original photo and current wallpaper stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service.delete(world.id);
      } catch (_) {
        _message('Could not delete this world. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListenableBuilder(
              listenable: _service,
              builder: (context, _) => CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.paddingOf(context).top + kTopChrome + 30,
                      20,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        const Text(
                          'Your own\nlittle escape.',
                          style: TextStyle(
                            fontFamily: 'InstrumentSerif',
                            fontSize: 46,
                            height: 1.02,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Start with a scene or a photo. Shape the atmosphere, light and motion.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Semantics(
                          button: true,
                          label: 'Create Midnight Express world',
                          child: Material(
                            color: const Color(0xFF101729),
                            borderRadius: BorderRadius.circular(24),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _open(WorldComposition.midnight),
                              child: SizedBox(
                                height: 270,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      WorldComposition.midnight.imagePath,
                                      fit: BoxFit.cover,
                                      alignment: const Alignment(0, .1),
                                      cacheWidth: 1000,
                                    ),
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x000B1120),
                                            Color(0xE60B1120),
                                          ],
                                          stops: [.2, 1],
                                        ),
                                      ),
                                    ),
                                    const Positioned(
                                      top: 18,
                                      left: 18,
                                      child: Text(
                                        'FEATURED WORLD',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                    ),
                                    const Positioned(
                                      left: 20,
                                      bottom: 22,
                                      right: 20,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Midnight Express',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        'InstrumentSerif',
                                                    fontSize: 35,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  'A quiet journey after dark',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_outward_rounded,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: _importing || _service.loadError != null
                              ? null
                              : _import,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: kAccent.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: _importing
                                    ? const Padding(
                                        padding: EdgeInsets.all(13),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: kAccentLight,
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _importing
                                          ? 'Opening photo…'
                                          : 'Start with your photo',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Your photo stays on this device',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 20),
                            ],
                          ),
                        ),
                        if (_service.loadError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Column(
                              children: [
                                Text(_service.loadError!),
                                TextButton(
                                  onPressed: _service.retryLoad,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 28),
                        const Text(
                          'My worlds',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_service.saved.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 32),
                            child: Text(
                              'Save a world in the studio and it will be waiting here.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) => SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: constraints.crossAxisExtent > 650
                              ? 3
                              : 2,
                          childAspectRatio: .68,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final world = _service.saved[i];
                          return _SavedWorldCard(
                            key: ValueKey(world.id),
                            world: world,
                            onTap: () => _open(world),
                            onDelete: () => _remove(world),
                          );
                        }, childCount: _service.saved.length),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ChromeIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 10),
                const TitlePill(text: 'Worlds'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SavedWorldCard extends StatefulWidget {
  const _SavedWorldCard({
    super.key,
    required this.world,
    required this.onTap,
    required this.onDelete,
  });
  final WorldComposition world;
  final VoidCallback onTap, onDelete;
  @override
  State<_SavedWorldCard> createState() => _SavedWorldCardState();
}

class _SavedWorldCardState extends State<_SavedWorldCard> {
  ui.Image? _image;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_SavedWorldCard old) {
    super.didUpdateWidget(old);
    if (old.world.imagePath != widget.world.imagePath) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final image = await WorldsService.instance.loadImage(
        widget.world,
        maxDimension: 512,
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      final previous = _image;
      setState(() => _image = image);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      final previous = _image;
      setState(() => _image = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
      });
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Edit ${widget.world.title}',
    child: Material(
      color: const Color(0xFF131928),
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_image != null)
              RepaintBoundary(
                child: CustomPaint(
                  painter: WorldPainter(
                    image: _image!,
                    settings: widget.world.settings,
                  ),
                ),
              )
            else
              const Center(
                child: Icon(Icons.landscape_outlined, color: Colors.white38),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xE60B1120)],
                  stops: [.4, 1],
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                onPressed: widget.onDelete,
                tooltip: 'Delete world',
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 15,
              child: Text(
                widget.world.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
