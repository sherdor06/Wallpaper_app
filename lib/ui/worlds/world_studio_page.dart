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

  /// Whether the editor sheet shows the open tab's controls. It starts
  /// folded — handle, tabs and the preview button — so the world is the
  /// first thing seen, nearly whole, rather than half a panel of sliders.
  bool _expanded = false;
  WorldSettings get _settings => _world.settings;
  bool get _dirty =>
      _settings != _baseline ||
      (!_world.isAsset && !_service.contains(_world.id));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  void _setExpanded(bool value) {
    if (value != _expanded) setState(() => _expanded = value);
  }

  /// A tab opens the sheet on itself; the tab that is already open folds it
  /// away again, the way a Maps card closes when you pick the same place.
  void _selectTab(_StudioTab tab) => setState(() {
    if (_expanded && tab == _tab) {
      _expanded = false;
    } else {
      _tab = tab;
      _expanded = true;
    }
  });

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
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: _leaving || (!_dirty && !_preview && _busy == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
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
              // Touching the picture folds the open sheet, so a look at the
              // whole world is one tap away. Below the chrome and the sheet,
              // which keep their own taps.
              if (_expanded && _image != null && !_preview)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setExpanded(false),
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
              // Over the scene, not the app's background: the pills take
              // light content wherever their glass turns dark with it.
              ChromeOverImage(
                child: Align(
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
                              // Without this the Align takes every pixel of
                              // height the outer Align offers — the whole screen
                              // — and the Row grows with it, centring Back, Undo
                              // and Save halfway down, behind the editor panel.
                              heightFactor: 1,
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
                                if (_busy == null) unawaited(_save());
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_image != null && _preview)
                ChromeSheet(
                  key: const ValueKey('preview'),
                  header: Builder(builder: _previewHeader),
                )
              else if (_image != null)
                ChromeSheet(
                  key: const ValueKey('editor'),
                  header: Builder(builder: _editorHeader),
                  body: Builder(builder: _editorBody),
                  expanded: _expanded,
                  onExpandedChanged: _setExpanded,
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

  /// Always on show, folded or open: the tabs, then the one action that
  /// finishes the job. The sheet draws its own handle above this.
  Widget _editorHeader(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (final tab in _StudioTab.values)
              Expanded(child: _tabButton(context, tab)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: SizedBox(
          width: double.infinity,
          height: 46,
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
      ),
    ],
  );

  /// The open tab's controls, revealed when the sheet is pulled up.
  Widget _editorBody(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reset sits with the controls it resets; folded away, there is
        // nothing on show for it to reset.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontSize: 12.5),
            ),
            onPressed: () => _change(
              _world.isAsset
                  ? const WorldSettings()
                  : const WorldSettings(palette: WorldPalette.original),
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Reset'),
          ),
        ),
        _tabControls(context),
      ],
    ),
  );

  /// One tab. Nothing reads as selected while the sheet is folded — there
  /// are no controls on show for it to be selected into.
  Widget _tabButton(BuildContext context, _StudioTab tab) {
    final theme = Theme.of(context);
    final active = _expanded && tab == _tab;
    // kAccentLight is the accent for dark surfaces. On the light theme's pale
    // capsule it falls under 3:1, so the label takes the deeper accent there.
    final accent = theme.brightness == Brightness.dark ? kAccentLight : kAccent;
    final color = active ? accent : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: active,
        child: InkWell(
          onTap: () => _selectTab(tab),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: active
                  ? kAccent.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  switch (tab) {
                    _StudioTab.scene => Icons.crop_rounded,
                    _StudioTab.atmosphere => Icons.cloud_outlined,
                    _StudioTab.light => Icons.wb_twilight_rounded,
                    _StudioTab.motion => Icons.air_rounded,
                  },
                  size: 19,
                  color: color,
                ),
                const SizedBox(height: 3),
                Text(
                  switch (tab) {
                    _StudioTab.scene => 'Scene',
                    _StudioTab.atmosphere => 'Atmosphere',
                    _StudioTab.light => 'Light',
                    _StudioTab.motion => 'Motion',
                  },
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabControls(BuildContext context) => switch (_tab) {
    _StudioTab.scene => Column(
      children: [
        _slider(
          context,
          'Zoom',
          _settings.zoom,
          1.04,
          1.6,
          '${_settings.zoom.toStringAsFixed(2)}×',
          (v) => _settings.copyWith(zoom: v),
        ),
        _slider(
          context,
          'Horizontal',
          _settings.focalX,
          0,
          1,
          '${(_settings.focalX * 100).round()}%',
          (v) => _settings.copyWith(focalX: v),
        ),
        _slider(
          context,
          'Vertical',
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
        _choiceRow([
          for (final weather in WorldWeather.values)
            _choice(
              context,
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
              onTap: () => _change(_settings.copyWith(weather: weather)),
            ),
        ]),
        if (_settings.weather == WorldWeather.rain ||
            _settings.weather == WorldWeather.snow) ...[
          const SizedBox(height: 8),
          _choiceRow([
            for (final view in WorldWeatherView.values)
              _choice(
                context,
                label: view == WorldWeatherView.openAir
                    ? 'Open air'
                    : 'Through glass',
                icon: view == WorldWeatherView.openAir
                    ? Icons.air_rounded
                    : Icons.window_outlined,
                selected: view == _settings.weatherView,
                onTap: () => _change(_settings.copyWith(weatherView: view)),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        _slider(
          context,
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
        _choiceRow([
          for (final palette in WorldPalette.values)
            _choice(
              context,
              label: switch (palette) {
                WorldPalette.original => 'Original',
                WorldPalette.blue => 'Blue hour',
                WorldPalette.lavender => 'Lavender',
                WorldPalette.amber => 'Amber',
              },
              selected: palette == _settings.palette,
              onTap: () => _change(_settings.copyWith(palette: palette)),
              swatch: switch (palette) {
                WorldPalette.original => const Color(0xFFB2B5C0),
                WorldPalette.blue => const Color(0xFF637FC5),
                WorldPalette.lavender => const Color(0xFFB29BE7),
                WorldPalette.amber => const Color(0xFFD6A674),
              },
            ),
        ]),
        const SizedBox(height: 6),
        _slider(
          context,
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
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const Expanded(
                child: Text('Living scene', style: TextStyle(fontSize: 13)),
              ),
              Switch.adaptive(
                value: _settings.motion,
                onChanged: (v) => _change(_settings.copyWith(motion: v)),
              ),
            ],
          ),
        ),
        if (MediaQuery.disableAnimationsOf(context))
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Motion is paused by your device’s Reduce Motion setting.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        _slider(
          context,
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
          context,
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
  };

  /// Label, track and value on one line — half the height of a label row
  /// stacked over its slider, which is most of what made the sheet tall.
  Widget _slider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    String display,
    WorldSettings Function(double) change, {
    bool enabled = true,
  }) => Opacity(
    opacity: enabled ? 1 : .4,
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
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
          SizedBox(
            width: 46,
            child: Text(
              display,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// One line of choices. It scrolls sideways rather than wrapping, so a
  /// long set never adds a second row of sheet over the picture.
  Widget _choiceRow(List<Widget> choices) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, choice) in choices.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          choice,
        ],
      ],
    ),
  );

  Widget _choice(
    BuildContext context, {
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
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
          if (swatch != null) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  /// Everything the preview needs, in one folded sheet: which screen to see
  /// it on, then the single decision — keep this world — with the lesser
  /// ways out beneath it. As little as possible over the picture being judged.
  Widget _previewHeader(BuildContext context) {
    final secondary = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12.5),
    );
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final home in [false, true])
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: _homePreview == home
                          ? kAccent.withValues(alpha: .18)
                          : Colors.transparent,
                      foregroundColor: scheme.onSurface,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
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
          const SizedBox(height: 10),
          Text(
            _service.supportsLiveWallpaper
                ? 'Confirm in your device’s wallpaper preview.'
                : _service.supportsLivePhoto
                ? 'Saves a Live Photo. In Photos, choose it as your Lock Screen — it moves when you wake your iPhone.'
                : 'Save a still image, then set it as wallpaper in Photos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
            spacing: 2,
            children: [
              TextButton.icon(
                style: secondary,
                onPressed: () => setState(() => _preview = false),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Edit'),
              ),
              // Where the primary control saves motion, a still is still
              // worth offering — for the Home Screen, say.
              if (_service.supportsLiveWallpaper || _service.supportsLivePhoto)
                TextButton.icon(
                  style: secondary,
                  onPressed: () => _export(),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Save image'),
                ),
              TextButton.icon(
                style: secondary,
                onPressed: () => _export(share: true),
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: const Text('Share image'),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
