import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../../models/world_composition.dart';

/// Coordinates are in a 400-unit viewport, shared with WorldWeatherRenderer.kt.
/// No random generation, texture decoding or blur passes happen on a frame.
class WorldWeatherRenderer {
  WorldWeatherRenderer(this.settings)
    : _rainTails = [
        for (final count in _rainCounts)
          Float32List((count * settings.intensity).round() * 4),
      ],
      _rainHeads = [
        for (final count in _rainCounts)
          Float32List((count * settings.intensity).round() * 4),
      ];

  final WorldSettings settings;
  final List<Float32List> _rainTails, _rainHeads;
  final _paint = ui.Paint()..isAntiAlias = true;
  final _cloudPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  static const cloudAsset = 'assets/worlds/weather_clouds.png';
  static const _rainCounts = [64, 46, 24];
  static const _snowCounts = [64, 42, 22];
  static ui.Image? _cloudTexture;
  static ui.Shader? _cloudShader;
  static Future<void>? _preparing;

  /// One shared 768x384 texture (1.125 MiB decoded), retained for Worlds.
  /// Editor, thumbnails and video export all use this same bounded cache.
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
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
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
      192,
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

  void paint(ui.Canvas canvas, double height, double time) {
    if (settings.intensity <= 0) return;
    switch (settings.weather) {
      case WorldWeather.clear:
        return;
      case WorldWeather.rain:
        _clouds(canvas, height, time, mist: true, strength: .15);
        _rain(canvas, height, time);
      case WorldWeather.snow:
        _clouds(canvas, height, time, mist: true, strength: .12);
        _snow(canvas, height, time);
      case WorldWeather.fog:
        _clouds(canvas, height, time, mist: true, strength: 1);
      case WorldWeather.clouds:
        _clouds(canvas, height, time, mist: false, strength: 1);
    }
  }

  void _clouds(
    ui.Canvas canvas,
    double height,
    double time, {
    required bool mist,
    required double strength,
  }) {
    final texture = _cloudTexture;
    if (texture == null) return;
    _cloudPaint.shader = _cloudShader;
    for (var layer = 0; layer < 2; layer++) {
      final width = mist ? 860.0 + layer * 180 : 680.0 + layer * 160;
      final bandHeight = height * (mist ? .62 : .38);
      final y = height * (mist ? .12 + layer * .34 : -.13 + layer * .14);
      final x =
          ((time * (mist ? 3.5 : 5.0) * (layer + 1) + layer * 291) % width) -
          width;
      _cloudPaint.color = ui.Color.fromRGBO(
        255,
        255,
        255,
        settings.intensity * strength * (mist ? .34 : .78 - layer * .16),
      );
      // Repeat sampling interpolates across the seam without translucent
      // image-rectangle edges. Only two cloud draws for the whole viewport.
      final scaleX = width / texture.width;
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scaleX, bandHeight / texture.height);
      canvas.drawRect(
        ui.Rect.fromLTWH(
          -x / scaleX,
          0,
          400 / scaleX,
          texture.height.toDouble(),
        ),
        _cloudPaint,
      );
      canvas.restore();
    }
  }

  void _rain(ui.Canvas canvas, double height, double time) {
    final slant = .16 + math.sin(time * .13) * .025;
    _paint.shader = null;
    _paint.strokeCap = ui.StrokeCap.round;
    for (var layer = 0; layer < 3; layer++) {
      final tails = _rainTails[layer], heads = _rainHeads[layer];
      for (var i = 0; i < tails.length ~/ 4; i++) {
        final p = _particles[layer * 64 + i];
        final velocity = (140 + layer * 145) * (.8 + p.speed * .4);
        final y =
            (p.y * (height + 120) + time * velocity) % (height + 120) - 60;
        final x = (p.x * 520 + time * velocity * .16) % 520 - 60;
        final length = (9 + layer * 12) * (.7 + p.size * .6);
        final startX = x - length * slant, startY = y - length;
        final splitX = x - length * slant * .25, splitY = y - length * .25;
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
        ..strokeWidth = .4 + layer * .3
        ..color = ui.Color.fromRGBO(195, 215, 235, .13 + layer * .07);
      canvas.drawRawPoints(ui.PointMode.lines, tails, _paint);
      _paint.color = ui.Color.fromRGBO(220, 234, 248, .23 + layer * .12);
      canvas.drawRawPoints(ui.PointMode.lines, heads, _paint);
    }
  }

  void _snow(ui.Canvas canvas, double height, double time) {
    for (var layer = 0; layer < 3; layer++) {
      final count = (_snowCounts[layer] * settings.intensity).round();
      _paint
        ..shader = layer == 2 ? _flakeShader : null
        ..color = ui.Color.fromRGBO(239, 246, 255, .38 + layer * .22);
      for (var i = 0; i < count; i++) {
        final p = _particles[layer * 64 + i];
        final velocity = (12 + layer * 17) * (.7 + p.speed * .6);
        final sway = math.sin(time * (.45 + p.speed * .4) + p.phase);
        final x =
            (p.x * 460 + time * (6 + layer * 5) + sway * (5 + layer * 4)) %
                460 -
            30;
        final y = (p.y * (height + 40) + time * velocity) % (height + 40) - 20;
        final radius = (.55 + layer * .75) * (.7 + p.size * .8);
        if (layer == 2) {
          // Soft foreground flakes use a cached gradient, not a blur layer.
          canvas.save();
          canvas.translate(x, y);
          canvas.scale(radius * 1.6, radius * 1.35);
          canvas.drawCircle(ui.Offset.zero, 1, _paint);
          canvas.restore();
        } else {
          canvas.drawCircle(ui.Offset(x, y), radius, _paint);
        }
      }
    }
    _paint.shader = null;
  }
}

class _Particle {
  const _Particle(this.x, this.y, this.size, this.speed, this.phase);
  final double x, y, size, speed, phase;
}
