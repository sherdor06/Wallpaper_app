import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../models/world_composition.dart';

/// Rain, snow, clouds and fog in a 400-unit-wide viewport. Every number here
/// has a twin in WorldWeatherRenderer.kt; keep the two equal. Nothing random,
/// decoded or blurred happens on a frame.
class WorldWeatherRenderer {
  WorldWeatherRenderer(this.settings)
    : _rainTails = [
        for (final count in _rainCounts)
          Float32List(_scaled(count, settings) * 4),
      ],
      _rainHeads = [
        for (final count in _rainCounts)
          Float32List(_scaled(count, settings) * 4),
      ] {
    final tint = _paletteTint(settings.palette);
    ui.Color tinted(int r, int g, int b) => ui.Color.fromARGB(
      255,
      (r * tint[0]).round(),
      (g * tint[1]).round(),
      (b * tint[2]).round(),
    );
    _cloudShadow = ui.ColorFilter.mode(tinted(70, 74, 98), ui.BlendMode.modulate);
    _cloudLight = ui.ColorFilter.mode(
      tinted(176, 170, 206),
      ui.BlendMode.modulate,
    );
    _mistTint = ui.ColorFilter.mode(tinted(150, 150, 168), ui.BlendMode.modulate);
    _fogColor = tinted(196, 198, 212);
  }

  final WorldSettings settings;
  final List<Float32List> _rainTails, _rainHeads;
  late final ui.ColorFilter _cloudShadow, _cloudLight, _mistTint;
  late final ui.Color _fogColor;
  ui.Shader? _fogShader;
  double _fogHeight = 0;
  final _paint = ui.Paint()..isAntiAlias = true;
  final _cloudPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  static const cloudAsset = 'assets/worlds/weather_clouds.png';

  // Far, middle and near layers. Far rain is fine and faint; near rain is
  // thick, soft and sparse, like drops passing out of focus.
  static const _rainCounts = [300, 140, 44];
  static const _rainSpeed = [300.0, 460.0, 640.0];
  static const _rainLength = [12.0, 20.0, 34.0];
  static const _rainWidth = [.4, .65, 1.2];
  static const _rainTailAlpha = [.10, .16, .11];
  static const _rainHeadAlpha = [.22, .34, .22];
  static const _rainWind = [.8, 1.0, 1.25];

  // Far, middle, near and out-of-focus flakes.
  static const _snowCounts = [260, 130, 44, 10];
  static const _snowFall = [12.0, 22.0, 36.0, 48.0];
  static const _snowRadius = [.75, 1.4, 2.6, 8.0];
  static const _snowAlpha = [.6, .8, .9, .24];
  static const _snowSway = [3.0, 6.0, 10.0, 16.0];
  static const _snowWind = [5.0, 9.0, 14.0, 20.0];

  static const _layerSlots = 320;

  static int _scaled(int count, WorldSettings settings) =>
      (count * settings.intensity).round();

  static ui.Image? _cloudTexture;
  static ui.Shader? _cloudShader;
  static Future<void>? _preparing;

  /// One shared 768x384 texture (1.125 MiB decoded), kept for the session.
  static Future<void> prepare() => _preparing ??= _loadTexture();

  static Future<void> _loadTexture() async {
    try {
      final data = await rootBundle.load(cloudAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        _cloudTexture = (await codec.getNextFrame()).image;
        _cloudShader = ui.ImageShader(
          _cloudTexture!,
          ui.TileMode.repeated,
          ui.TileMode.clamp,
          _identity,
        );
      } finally {
        codec.dispose();
      }
    } catch (_) {
      _preparing = null;
      rethrow;
    }
  }

  static final _particles = _makeParticles();
  static List<_Particle> _makeParticles() {
    var seed = 38401;
    double next() {
      seed = seed * 16807 % 2147483647;
      return (seed - 1) / 2147483646;
    }

    return List.generate(
      _layerSlots * 4,
      (_) => _Particle(next(), next(), next(), next(), next() * math.pi * 2),
      growable: false,
    );
  }

  static final _flakeShader = ui.Gradient.radial(
    ui.Offset.zero,
    1,
    const [ui.Color(0xFFF4F8FF), ui.Color(0xDDF4F8FF), ui.Color(0x00F4F8FF)],
    const [0, .45, 1],
  );
  static final _bokehShader = ui.Gradient.radial(
    ui.Offset.zero,
    1,
    const [ui.Color(0xFFF4F8FF), ui.Color(0x80F4F8FF), ui.Color(0x00F4F8FF)],
    const [0, .6, 1],
  );

  /// The light the weather leaves on the scene, as a colour matrix applied
  /// after the palette: rain darkens and cools, snow lifts and pales, fog
  /// flattens contrast, clouds dim. Identity at zero intensity.
  static List<double> grade(WorldSettings settings, List<double> palette) {
    final k = settings.weather == WorldWeather.clear ? 0.0 : settings.intensity;
    final (saturation, gain, lift, tint) = switch (settings.weather) {
      WorldWeather.rain => (1 - .30 * k, 1 - .16 * k, 8 * k, [.96, .99, 1.05]),
      WorldWeather.snow => (1 - .35 * k, 1 - .04 * k, 22 * k, [.97, 1.0, 1.06]),
      WorldWeather.fog => (1 - .40 * k, 1 - .28 * k, 40 * k, [1.0, 1.0, 1.02]),
      WorldWeather.clouds => (
        1 - .22 * k,
        1 - .12 * k,
        4 * k,
        [.98, .99, 1.02],
      ),
      WorldWeather.clear => (1.0, 1.0, 0.0, [1.0, 1.0, 1.0]),
    };
    const luma = [.2126, .7152, .0722];
    final matrix = <double>[];
    for (var row = 0; row < 3; row++) {
      // At zero intensity every factor is exactly 1, so the tint drops out.
      final scale = gain * (1 + (tint[row] - 1) * k);
      for (var column = 0; column < 3; column++) {
        final mix =
            (1 - saturation) * luma[column] +
            (row == column ? saturation : 0);
        matrix.add(scale * mix * palette[column]);
      }
      matrix.addAll([0, lift]);
    }
    matrix.addAll([0, 0, 0, 1, 0]);
    return matrix;
  }

  // Clouds and mist take the palette's colour instead of a flat grey.
  static List<double> _paletteTint(WorldPalette palette) => switch (palette) {
    WorldPalette.original => [1.0, 1.0, 1.0],
    WorldPalette.blue => [.88, .96, 1.0],
    WorldPalette.lavender => [.96, .90, 1.0],
    WorldPalette.amber => [1.0, .94, .82],
  };

  void paint(ui.Canvas canvas, double height, double time) {
    if (settings.intensity <= 0) return;
    switch (settings.weather) {
      case WorldWeather.clear:
        return;
      case WorldWeather.rain:
        _mist(canvas, height, time, .35);
        _rain(canvas, height, time);
      case WorldWeather.snow:
        _mist(canvas, height, time, .3);
        _snow(canvas, height, time);
      case WorldWeather.fog:
        _mist(canvas, height, time, 1);
        _groundFog(canvas, height);
      case WorldWeather.clouds:
        _clouds(canvas, height, time);
    }
    _cloudPaint
      ..blendMode = ui.BlendMode.srcOver
      ..colorFilter = null;
  }

  /// Draws the texture across the viewport: [width] units per repeat,
  /// [bandHeight] tall at [y], scrolled by [x].
  void _band(
    ui.Canvas canvas,
    double x,
    double y,
    double width,
    double bandHeight,
  ) {
    final texture = _cloudTexture!;
    final scaleX = width / texture.width;
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scaleX, bandHeight / texture.height);
    canvas.drawRect(
      ui.Rect.fromLTWH(-x / scaleX, 0, 400 / scaleX, texture.height.toDouble()),
      _cloudPaint,
    );
    canvas.restore();
  }

  // A cloud is drawn twice: its body darkens the sky beneath it (multiply)
  // and its upper edge catches light (screen), which gives it volume.
  void _clouds(ui.Canvas canvas, double height, double time) {
    if (_cloudTexture == null) return;
    final k = settings.intensity;
    _cloudPaint.shader = _cloudShader;
    for (var layer = 0; layer < 2; layer++) {
      final width = 680.0 + layer * 160;
      final bandHeight = height * (.40 + layer * .06);
      final y = height * (-.14 + layer * .15);
      final x = ((time * 5.0 * (layer + 1) + layer * 291) % width) - width;
      final depth = 1 - layer * .25;
      _cloudPaint
        ..blendMode = ui.BlendMode.multiply
        ..colorFilter = _cloudShadow
        ..color = ui.Color.fromRGBO(255, 255, 255, .55 * k * depth);
      _band(canvas, x, y + bandHeight * .03, width, bandHeight);
      _cloudPaint
        ..blendMode = ui.BlendMode.screen
        ..colorFilter = _cloudLight
        ..color = ui.Color.fromRGBO(255, 255, 255, .42 * k * depth);
      _band(canvas, x, y - bandHeight * .04, width, bandHeight);
    }
  }

  // Luminous mist: screened, so it glows over a night scene instead of
  // laying grey paint over it.
  void _mist(ui.Canvas canvas, double height, double time, double strength) {
    if (_cloudTexture == null) return;
    final k = settings.intensity;
    _cloudPaint
      ..shader = _cloudShader
      ..blendMode = ui.BlendMode.screen
      ..colorFilter = _mistTint;
    for (var layer = 0; layer < 2; layer++) {
      final width = 860.0 + layer * 180;
      final x = ((time * 3.5 * (layer + 1) + layer * 291) % width) - width;
      _cloudPaint.color = ui.Color.fromRGBO(
        255,
        255,
        255,
        .42 * k * strength * (1 - layer * .2),
      );
      _band(canvas, x, height * (.18 + layer * .32), width, height * .62);
    }
  }

  // Fog settles: densest at the ground, thinning upwards.
  void _groundFog(ui.Canvas canvas, double height) {
    if (_fogHeight != height) {
      _fogHeight = height;
      _fogShader = ui.Gradient.linear(
        ui.Offset(0, height * .42),
        ui.Offset(0, height),
        [
          _fogColor.withValues(alpha: 0),
          _fogColor.withValues(alpha: .42 * settings.intensity),
        ],
      );
    }
    _paint
      ..shader = _fogShader
      ..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, 400, height), _paint);
    _paint.shader = null;
  }

  void _rain(ui.Canvas canvas, double height, double time) {
    // Gusts: two slow waves, so the slant never repeats in an obvious beat.
    final wind =
        .10 + math.sin(time * .23) * .05 + math.sin(time * .61 + 1.3) * .03;
    _paint
      ..shader = null
      ..strokeCap = ui.StrokeCap.round;
    for (var layer = 0; layer < 3; layer++) {
      final tails = _rainTails[layer], heads = _rainHeads[layer];
      final slant = wind * _rainWind[layer];
      for (var i = 0; i < tails.length ~/ 4; i++) {
        final p = _particles[layer * _layerSlots + i];
        final velocity = _rainSpeed[layer] * (.85 + p.speed * .3);
        final y =
            (p.y * (height + 160) + time * velocity) % (height + 160) - 80;
        final x = (p.x * 520 + time * velocity * slant) % 520 - 60;
        final length = _rainLength[layer] * (.75 + p.size * .5);
        final startX = x - length * slant, startY = y - length;
        final splitX = x - length * slant * .3, splitY = y - length * .3;
        final index = i * 4;
        tails[index] = startX;
        tails[index + 1] = startY;
        tails[index + 2] = splitX;
        tails[index + 3] = splitY;
        heads[index] = splitX;
        heads[index + 1] = splitY;
        heads[index + 2] = x;
        heads[index + 3] = y;
      }
      _paint
        ..strokeWidth = _rainWidth[layer]
        ..color = ui.Color.fromRGBO(190, 205, 225, _rainTailAlpha[layer]);
      canvas.drawRawPoints(ui.PointMode.lines, tails, _paint);
      _paint.color = ui.Color.fromRGBO(225, 235, 248, _rainHeadAlpha[layer]);
      canvas.drawRawPoints(ui.PointMode.lines, heads, _paint);
    }
  }

  void _snow(ui.Canvas canvas, double height, double time) {
    for (var layer = 0; layer < 4; layer++) {
      final count = _scaled(_snowCounts[layer], settings);
      _paint.shader = switch (layer) {
        0 => null,
        3 => _bokehShader,
        _ => _flakeShader,
      };
      for (var i = 0; i < count; i++) {
        final p = _particles[layer * _layerSlots + i];
        // Flakes of one layer still differ: some are nearer than others.
        _paint.color = ui.Color.fromRGBO(
          239,
          246,
          255,
          _snowAlpha[layer] * (.6 + p.size * .4),
        );
        final radius = _snowRadius[layer] * (.7 + p.size * .6);
        final fall = _snowFall[layer] * (.7 + p.speed * .6);
        // Two frequencies make each flake flutter rather than swing.
        final rate = .35 + p.speed * .35;
        final sway =
            math.sin(time * rate + p.phase) +
            math.sin(time * rate * 2.3 + p.phase * 1.7) * .4;
        final span = 400 + radius * 2 + 60;
        final x =
            (p.x * span + time * _snowWind[layer] + sway * _snowSway[layer]) %
                span -
            radius -
            30;
        final drop = height + radius * 2 + 40;
        final y = (p.y * drop + time * fall) % drop - radius - 20;
        if (layer == 0) {
          canvas.drawCircle(ui.Offset(x, y), radius, _paint);
        } else {
          canvas.save();
          canvas.translate(x, y);
          canvas.scale(radius * 1.3, radius * 1.55);
          canvas.drawCircle(ui.Offset.zero, 1, _paint);
          canvas.restore();
        }
      }
    }
    _paint.shader = null;
  }
}

final _identity = Float64List.fromList(const [
  1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1, //
]);

class _Particle {
  const _Particle(this.x, this.y, this.size, this.speed, this.phase);
  final double x, y, size, speed, phase;
}
