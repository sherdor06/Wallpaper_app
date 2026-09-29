import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/world_composition.dart';
import '../../services/worlds_service.dart';
import '../accent.dart';
import '../widgets/floating_chrome.dart';
import 'world_scene.dart';

enum _StudioTab { scene, atmosphere, light, motion }

class WorldStudioPage extends StatefulWidget {
  const WorldStudioPage({super.key, required this.world});
  final WorldComposition world;
  @override
  State<WorldStudioPage> createState() => _WorldStudioPageState();
}

class _WorldStudioPageState extends State<WorldStudioPage> {
  final _service = WorldsService.instance;
  late WorldComposition _world = widget.world;
  late WorldSettings _baseline = widget.world.settings;
  final List<WorldSettings> _undo = [];
  ui.Image? _image;
  String? _error;
  String? _busy;
  final _exportProgress = ValueNotifier<double?>(null);
  bool _preview = false;
  bool _homePreview = false;
  bool _leaving = false;
  _StudioTab _tab = _StudioTab.atmosphere;
  WorldSettings get _settings => _world.settings;
  bool get _dirty =>
      _settings != _baseline ||
      (!_world.isAsset && !_service.contains(_world.id));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final image = await _service.loadImage(_world, maxDimension: 2304);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'This photo is unavailable. Please choose it again.',
        );
      }
    }
  }

  @override
  void dispose() {
    _exportProgress.dispose();
    _image?.dispose();
    unawaited(_service.discardDraft(_world));
    super.dispose();
  }

  void _remember() {
    if (_undo.lastOrNull != _settings) _undo.add(_settings);
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void _change(WorldSettings value, {bool remember = true}) {
    if (value == _settings) return;
    if (remember) _remember();
    setState(() => _world = _world.copyWith(settings: value));
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<bool> _save() async {
    final choice = await showDialog<({String title, bool copy})>(
      context: context,
      builder: (_) => _NameDialog(
        title: _world.title,
        existing: _service.contains(_world.id),
      ),
    );
    if (choice == null || !mounted) return false;
    setState(() => _busy = 'Saving world');
    try {
      final saved = await _service.save(
        _world,
        title: choice.title,
        asCopy: choice.copy,
      );
      if (!mounted) return true;
      setState(() {
        _world = saved;
        _baseline = saved.settings;
      });
      _notice('Saved to My worlds');
      return true;
    } catch (_) {
      _notice('Could not save this world. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _leave() async {
    if (_busy != null || _leaving) return;
    if (_preview) {
      setState(() => _preview = false);
      return;
    }
    if (_dirty) {
      final decision = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save your world?'),
          content: const Text('Keep this atmosphere and return to it anytime.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || decision == null || decision == 'cancel') return;
      if (decision == 'save' && !await _save()) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    // Let PopScope publish the new value before requesting the pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _export({bool share = false}) async {
    final image = _image;
    if (image == null || _busy != null) return;
    final size = MediaQuery.sizeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = share ? 'Preparing image' : 'Saving image');
    try {
      final bytes = await exportWorld(image, _settings, size);
      if (share) {
        final file = await _service.writeExport(bytes);
        if (!mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: _world.title,
            text: 'Made with Wavely Worlds',
            sharePositionOrigin: origin,
          ),
        );
        // Receivers may still be reading this file after the share sheet closes.
        // The service removes aged exports on a later startup.
      } else {
        await _service.saveStill(bytes);
        _notice('Image saved. You can now set it as your wallpaper.');
      }
    } on PlatformException catch (e) {
      _notice(
        e.code == 'PERMISSION_DENIED' || e.code == 'photo_access_denied'
            ? 'Allow photo access in Settings, then try again.'
            : 'Could not finish. Please try again.',
      );
    } catch (_) {
      _notice(
        'Could not finish. Please check available storage and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// iOS: the world goes to Photos as a Live Photo — the only "live" route
  /// the platform allows — and the user picks it as the Lock Screen there.
  Future<void> _saveLive() async {
    final image = _image;
    if (image == null || _busy != null) return;
    final size = MediaQuery.sizeOf(context);
    _exportProgress.value = 0;
    setState(() => _busy = 'Rendering Live Photo');
    try {
      await _service.saveLivePhoto(
        image,
        _settings,
        size,
        onProgress: (p) {
          if (mounted) _exportProgress.value = p;
        },
      );
      _notice(
        'Live Photo saved. In Photos, set it as your Lock Screen wallpaper.',
      );
    } on PlatformException catch (e) {
      _notice(
        e.code == 'PERMISSION_DENIED'
            ? 'Allow photo access in Settings, then try again.'
            : 'Could not save the Live Photo. Please try again.',
      );
    } catch (_) {
      _notice(
        'Could not finish. Please check available storage and try again.',
      );
    } finally {
      if (mounted) {
        _exportProgress.value = null;
        setState(() => _busy = null);
      }
    }
  }

  Future<void> _apply() async {
    if (_busy != null) return;
    setState(() => _busy = 'Opening wallpaper preview');
    try {
      final applied = await _service.applyLive(_world);
      if (applied) _notice('Your world is now your wallpaper');
    } catch (_) {
      _notice(
        'Could not open the wallpaper preview. You can still save an image.',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: _leaving || (!_dirty && !_preview && _busy == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1120),
        body: LayoutBuilder(
          builder: (context, bounds) => Stack(
            fit: StackFit.expand,
            children: [
              if (_image != null)
                Semantics(
                  label:
                      '${_world.title}, ${_settings.weather.name} atmosphere',
                  image: true,
                  child: WorldScene(
                    image: _image!,
                    settings: _settings,
                    animated: _busy == null,
                  ),
                )
              else if (_error == null)
                const Center(
                  child: CircularProgressIndicator(color: kAccentLight),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x850B1120),
                        Color(0x000B1120),
                        Color(0x000B1120),
                        Color(0x550B1120),
                      ],
                      stops: [0, .25, .65, 1],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_image != null && !_preview && bounds.maxHeight > 660)
                Positioned(
                  left: 28,
                  right: 28,
                  top: media.padding.top + 87,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WAVELY  /  WORLDS',
                          style: TextStyle(
                            color: Color(0xFFD1C9E7),
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _world.title == 'Midnight Express'
                              ? 'Midnight\nExpress'
                              : _world.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'InstrumentSerif',
                            fontSize: 56,
                            height: .98,
                            color: Color(0xFFF4F0FB),
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_preview && _image != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: media.padding.top + 95,
                  child: IgnorePointer(
                    child: _PreviewFurniture(home: _homePreview),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        ChromeIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: _leave,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TitlePill(text: 'Worlds'),
                            ),
                          ),
                        ),
                        if (_image != null && !_preview) ...[
                          ChromeIconButton(
                            icon: Icons.undo_rounded,
                            tooltip: 'Undo',
                            onTap: () {
                              if (_undo.isNotEmpty && _busy == null) {
                                setState(
                                  () => _world = _world.copyWith(
                                    settings: _undo.removeLast(),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChromeIconButton(
                            icon: _service.contains(_world.id) && !_dirty
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            tooltip: 'Save world',
                            onTap: () {
                              if (_busy == null) _save();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_image != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: bounds.maxHeight * (_preview ? .48 : .55),
                    ),
                    child: _preview
                        ? _previewControls()
                        : Container(
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  14,
                                  22,
                                  14,
                                ),
                                child: _editorControls(),
                              ),
                            ),
                          ),
                  ),
                ),
              if (_busy != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x66000000),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                child: ValueListenableBuilder<double?>(
                                  valueListenable: _exportProgress,
                                  builder: (context, progress, _) => Text(
                                    progress == null
                                        ? _busy!
                                        : progress == 1
                                        ? 'Saving to Photos'
                                        : 'Rendering Live Photo ${(progress * 100).round()}%',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorControls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Make it yours',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _change(
              _world.isAsset
                  ? const WorldSettings()
                  : const WorldSettings(palette: WorldPalette.original),
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('Reset'),
          ),
        ],
      ),
      Row(
        children: [
          for (final tab in _StudioTab.values)
            Expanded(
              child: Semantics(
                selected: tab == _tab,
                child: InkWell(
                  onTap: () => setState(() => _tab = tab),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: tab == _tab
                              ? kAccentLight
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          switch (tab) {
                            _StudioTab.scene => Icons.crop_rounded,
                            _StudioTab.atmosphere => Icons.cloud_outlined,
                            _StudioTab.light => Icons.wb_twilight_rounded,
                            _StudioTab.motion => Icons.air_rounded,
                          },
                          size: 20,
                          color: tab == _tab
                              ? kAccentLight
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (tab) {
                            _StudioTab.scene => 'Scene',
                            _StudioTab.atmosphere => 'Atmosphere',
                            _StudioTab.light => 'Light',
                            _StudioTab.motion => 'Motion',
                          },
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: tab == _tab
                                ? kAccentLight
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: switch (_tab) {
          _StudioTab.scene => Column(
            children: [
              _slider(
                'Zoom',
                _settings.zoom,
                1.04,
                1.6,
                '${_settings.zoom.toStringAsFixed(2)}×',
                (v) => _settings.copyWith(zoom: v),
              ),
              _slider(
                'Horizontal position',
                _settings.focalX,
                0,
                1,
                '${(_settings.focalX * 100).round()}%',
                (v) => _settings.copyWith(focalX: v),
              ),
              _slider(
                'Vertical position',
                _settings.focalY,
                0,
                1,
                '${(_settings.focalY * 100).round()}%',
                (v) => _settings.copyWith(focalY: v),
              ),
            ],
          ),
          _StudioTab.atmosphere => Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final weather in WorldWeather.values)
                    _choice(
                      label: switch (weather) {
                        WorldWeather.clear => 'Clear',
                        WorldWeather.rain => 'Rain',
                        WorldWeather.fog => 'Fog',
                        WorldWeather.clouds => 'Clouds',
                        WorldWeather.snow => 'Snow',
                      },
                      icon: switch (weather) {
                        WorldWeather.clear => Icons.nightlight_outlined,
                        WorldWeather.rain => Icons.water_drop_outlined,
                        WorldWeather.fog => Icons.blur_on_rounded,
                        WorldWeather.clouds => Icons.cloud_outlined,
                        WorldWeather.snow => Icons.ac_unit_rounded,
                      },
                      selected: weather == _settings.weather,
                      onTap: () =>
                          _change(_settings.copyWith(weather: weather)),
                    ),
                ],
              ),
              if (_settings.weather == WorldWeather.rain ||
                  _settings.weather == WorldWeather.snow) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final view in WorldWeatherView.values)
                      _choice(
                        label: view == WorldWeatherView.openAir
                            ? 'Open air'
                            : 'Through glass',
                        icon: view == WorldWeatherView.openAir
                            ? Icons.air_rounded
                            : Icons.window_outlined,
                        selected: view == _settings.weatherView,
                        onTap: () =>
                            _change(_settings.copyWith(weatherView: view)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _slider(
                switch (_settings.weather) {
                  WorldWeather.fog => 'Mist density',
                  WorldWeather.clouds => 'Cloud cover',
                  WorldWeather.snow => 'Snowfall',
                  WorldWeather.clear || WorldWeather.rain => 'Rainfall',
                },
                _settings.intensity,
                0,
                1,
                '${(_settings.intensity * 100).round()}%',
                (v) => _settings.copyWith(intensity: v),
                enabled: _settings.weather != WorldWeather.clear,
              ),
            ],
          ),
          _StudioTab.light => Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in WorldPalette.values)
                    _choice(
                      label: switch (palette) {
                        WorldPalette.original => 'Original',
                        WorldPalette.blue => 'Blue hour',
                        WorldPalette.lavender => 'Lavender',
                        WorldPalette.amber => 'Amber',
                      },
                      selected: palette == _settings.palette,
                      onTap: () =>
                          _change(_settings.copyWith(palette: palette)),
                      swatch: switch (palette) {
                        WorldPalette.original => const Color(0xFFB2B5C0),
                        WorldPalette.blue => const Color(0xFF637FC5),
                        WorldPalette.lavender => const Color(0xFFB29BE7),
                        WorldPalette.amber => const Color(0xFFD6A674),
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _slider(
                'Brightness',
                _settings.glow,
                0,
                1,
                '${(_settings.glow * 100).round()}%',
                (v) => _settings.copyWith(glow: v),
              ),
            ],
          ),
          _StudioTab.motion => Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Living scene', style: TextStyle(fontSize: 14)),
                  ),
                  Switch.adaptive(
                    value: _settings.motion,
                    onChanged: (v) => _change(_settings.copyWith(motion: v)),
                  ),
                ],
              ),
              if (MediaQuery.disableAnimationsOf(context))
                const Text(
                  'Motion is paused by your device’s Reduce Motion setting.',
                  style: TextStyle(fontSize: 12),
                ),
              _slider(
                'Speed',
                _settings.speed,
                0,
                1,
                _settings.speed < .45
                    ? 'Slow'
                    : _settings.speed < .75
                    ? 'Steady'
                    : 'Fast',
                (v) => _settings.copyWith(speed: v),
                enabled: _settings.motion,
              ),
              _slider(
                'Camera drift',
                _settings.drift,
                0,
                1,
                '${(_settings.drift * 100).round()}%',
                (v) => _settings.copyWith(drift: v),
                enabled: _settings.motion,
              ),
            ],
          ),
        },
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => setState(() => _preview = true),
          icon: const Icon(Icons.crop_free_rounded, size: 19),
          label: const Text('Preview wallpaper'),
        ),
      ),
    ],
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String display,
    WorldSettings Function(double) change, {
    bool enabled = true,
  }) => Opacity(
    opacity: enabled ? 1 : .4,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            Text(
              display,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: kAccentLight,
              semanticFormatterCallback: (_) => display,
              onChangeStart: enabled ? (_) => _remember() : null,
              onChanged: enabled
                  ? (v) => _change(change(v), remember: false)
                  : null,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? swatch,
  }) => Semantics(
    selected: selected,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? kAccent.withValues(alpha: .12)
            : Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(
          color: selected
              ? kAccentLight
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          if (swatch != null) ...[
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
    ),
  );

  Widget _previewControls() => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xE51B1C2A),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final home in [false, true])
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: _homePreview == home
                          ? const Color(0xFF3A364C)
                          : Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onPressed: () => setState(() => _homePreview = home),
                    child: Text(
                      home ? 'Home screen' : 'Lock screen',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _service.supportsLiveWallpaper
                      ? 'Confirm in your device’s wallpaper preview.'
                      : _service.supportsLivePhoto
                      ? 'Saves a Live Photo. In Photos, choose it as your Lock Screen — it moves when you wake your iPhone.'
                      : 'Save a still image, then set it as wallpaper in Photos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _service.supportsLiveWallpaper
                        ? _apply
                        : _service.supportsLivePhoto
                        ? _saveLive
                        : () => _export(),
                    icon: Icon(
                      _service.supportsLiveWallpaper
                          ? Icons.wallpaper_rounded
                          : _service.supportsLivePhoto
                          ? Icons.motion_photos_on_rounded
                          : Icons.save_alt_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _service.supportsLiveWallpaper
                          ? 'Set live wallpaper'
                          : _service.supportsLivePhoto
                          ? 'Save Live Photo'
                          : 'Save to Photos',
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _preview = false),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('Edit'),
                    ),
                    // Where the primary control saves motion, a still is
                    // still worth offering — for the Home Screen, say.
                    if (_service.supportsLiveWallpaper ||
                        _service.supportsLivePhoto)
                      TextButton.icon(
                        onPressed: () => _export(),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Save image'),
                      ),
                    TextButton.icon(
                      onPressed: () => _export(share: true),
                      icon: const Icon(Icons.ios_share_rounded, size: 16),
                      label: const Text('Share image'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.existing});
  final String title;
  final bool existing;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.title);
  bool _copy = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, (title: _controller.text.trim(), copy: _copy));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save world'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _submit(),
        ),
        if (widget.existing)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save as a new world'),
            value: _copy,
            onChanged: (v) => setState(() => _copy = v ?? false),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

class _PreviewFurniture extends StatelessWidget {
  const _PreviewFurniture({required this.home});
  final bool home;
  @override
  Widget build(BuildContext context) {
    if (home) {
      return Column(
        children: [
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var col = 0; col < 4; col++)
                    Column(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0x35FFFFFF),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: const Color(0x40FFFFFF)),
                          ),
                          child: Icon(
                            _icons[row * 4 + col],
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _labels[row * 4 + col],
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      );
    }
    final now = DateTime.now();
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    return Column(
      children: [
        Text(
          date,
          style: const TextStyle(fontSize: 16, color: Color(0xFFE9E3F6)),
        ),
        Text(
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 88,
            color: Color(0xFFF0EAF9),
            fontWeight: FontWeight.w500,
            letterSpacing: -4,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  static const _icons = [
    Icons.calendar_today,
    Icons.camera_alt_outlined,
    Icons.photo_outlined,
    Icons.map_outlined,
    Icons.music_note_outlined,
    Icons.wb_sunny_outlined,
    Icons.notes_rounded,
    Icons.settings_outlined,
  ];
  static const _labels = [
    'Calendar',
    'Camera',
    'Photos',
    'Maps',
    'Music',
    'Weather',
    'Notes',
    'Settings',
  ];
}
