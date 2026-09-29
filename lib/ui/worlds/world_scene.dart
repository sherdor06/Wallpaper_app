import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/world_composition.dart';
import 'world_weather.dart';
import 'world_glass.dart';

/// The clock repaints only the canvas. No widget builds occur on animation ticks.
class WorldScene extends StatefulWidget {
  const WorldScene({
    super.key,
    required this.image,
    required this.settings,
    this.animated = true,
  });
  final ui.Image image;
  final WorldSettings settings;
  final bool animated;

  @override
  State<WorldScene> createState() => _WorldSceneState();
}

class _WorldSceneState extends State<WorldScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WorldScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final run =
        _foreground &&
        widget.animated &&
        widget.settings.motion &&
        (widget.settings.drift > 0 ||
            widget.settings.weather != WorldWeather.clear &&
                widget.settings.intensity > 0) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    if (!run && _ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _last;
    if (delta.inMicroseconds < 33000) return;
    _last = elapsed;
    _clock.value += worldClock(
      math.min(delta.inMicroseconds / 1e6, .1),
      widget.settings,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: WorldPainter(
        image: widget.image,
        settings: widget.settings,
        clock: _clock,
      ),
      size: Size.infinite,
    ),
  );
}

/// Shared drawing path for editor, preview, thumbnails and exported stills.
/// Keep colour factors / particles in step with WorldWallpaperService.kt.
class WorldPainter extends CustomPainter {
  WorldPainter({
    required this.image,
    required this.settings,
    this.clock,
    this.time = 0,
  }) : _weather = WorldWeatherRenderer(settings),
       _glass = settings.hasGlass ? WorldGlassRenderer() : null,
       super(repaint: clock) {
    final factor = .65 + settings.glow * .65;
    final rgb = switch (settings.palette) {
      WorldPalette.original => [1.0, 1.0, 1.0],
      WorldPalette.blue => [.85, .98, 1.10],
      WorldPalette.lavender => [1.06, .91, 1.15],
      WorldPalette.amber => [1.15, 1.01, .8],
    };
    _imagePaint.colorFilter = ColorFilter.matrix([
      rgb[0] * factor,
      0,
      0,
      0,
      0,
      0,
      rgb[1] * factor,
      0,
      0,
      0,
      0,
      0,
      rgb[2] * factor,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
  final ui.Image image;
  final WorldSettings settings;
  final ValueListenable<double>? clock;
  final double time;
  final _imagePaint = Paint()..filterQuality = FilterQuality.medium;
  final WorldWeatherRenderer _weather;
  final WorldGlassRenderer? _glass;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = settings.motion ? (clock?.value ?? time) : 0.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final unit = size.width / 400;
    final cover =
        math.max(size.width / image.width, size.height / image.height) *
        settings.zoom;
    final w = image.width * cover, h = image.height * cover;
    final dx =
        (-(w - size.width) * settings.focalX +
                math.sin(t * .105) * 3 * unit * settings.drift)
            .clamp(size.width - w, 0.0);
    final dy = -(h - size.height) * settings.focalY;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dx, dy, w, h),
      _imagePaint,
    );
    canvas.scale(unit);
    final height = size.height / unit;
    _weather.paint(canvas, height, t);
    _glass?.paint(
      canvas,
      height,
      t,
      settings,
      image,
      Rect.fromLTWH(dx / unit, dy / unit, w / unit, h / unit),
      _imagePaint.colorFilter,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(WorldPainter oldDelegate) =>
      image != oldDelegate.image ||
      settings != oldDelegate.settings ||
      time != oldDelegate.time;
}

/// How far the scene's clock moves in [seconds] of wall time. The live
/// scene and the frame-by-frame export both go through this, so an exported
/// clip runs at the speed the preview showed.
double worldClock(double seconds, WorldSettings settings) =>
    settings.motion ? seconds * (.3 + settings.speed / .7) : 0;

/// Wallpaper export size for a screen: portrait, 2304 tall, the screen's
/// aspect. Even on both sides, so the Live Photo clip — H.264, which needs
/// even dimensions — can be exactly this size and the still and the clip
/// share one aspect ratio; a one-pixel mismatch between the pair is the
/// kind of thing Photos' wallpaper checks reject.
Size exportSize(Size screen) {
  final ratio =
      math.min(screen.width, screen.height) /
      math.max(screen.width, screen.height);
  const height = 2304;
  final width = ((height * ratio / 2).round() * 2).clamp(2, 2304);
  return Size(width.toDouble(), height.toDouble());
}

/// Render at wallpaper resolution, without buttons, clocks or other UI.
Future<Uint8List> exportWorld(
  ui.Image image,
  WorldSettings settings,
  Size screen, {
  double time = 0,
}) => renderWorld(image, settings, exportSize(screen), time: time);

/// One frame of the world at [size], at scene time [time], encoded as
/// [format] — PNG for a still, raw RGBA for a video frame.
Future<Uint8List> renderWorld(
  ui.Image image,
  WorldSettings settings,
  Size size, {
  double time = 0,
  ui.ImageByteFormat format = ui.ImageByteFormat.png,
}) async {
  await WorldWeatherRenderer.prepare();
  final width = size.width.round(), height = size.height.round();
  final recorder = ui.PictureRecorder();
  WorldPainter(
    image: image,
    settings: settings,
    time: time,
  ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(width, height);
    final bytes = await output.toByteData(format: format);
    if (bytes == null) throw StateError('Could not render this world.');
    return bytes.buffer.asUint8List();
  } finally {
    output?.dispose();
    picture.dispose();
  }
}
