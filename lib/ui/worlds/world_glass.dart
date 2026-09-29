import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/world_composition.dart';

/// Foreground moisture fixed to the glass, independent of background drift.
/// Analytic lifecycles keep preview, stills and video frames deterministic.
/// Keep geometry/seed in sync with WorldGlassRenderer.kt.
class WorldGlassRenderer {
  final _paint = ui.Paint()..isAntiAlias = true;
  final _lensPaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final _trail = ui.Path();

  static final _drops = _particles();
  static List<_GlassParticle> _particles() {
    var seed = 81731;
    double next() {
      seed = seed * 16807 % 2147483647;
      return (seed - 1) / 2147483646;
    }

    return List.generate(
      72,
      (_) => _GlassParticle(next(), next(), next(), next(), next()),
      growable: false,
    );
  }

  static final _bead = ui.Path()
    ..moveTo(0, -1)
    ..cubicTo(.52, -.98, .78, -.48, .9, .12)
    ..cubicTo(1.02, .77, .52, 1, 0, 1)
    ..cubicTo(-.58, 1, -1, .64, -.84, .07)
    ..cubicTo(-.68, -.5, -.47, -.94, 0, -1)
    ..close();
  static final _highlight = ui.Path()
    ..moveTo(-.57, -.15)
    ..cubicTo(-.52, -.61, -.22, -.8, .12, -.77);
  static final _caustic = ui.Path()
    ..moveTo(-.45, .69)
    ..quadraticBezierTo(.14, .98, .59, .51);
  static final _snow = ui.Path()
    ..addOval(const ui.Rect.fromLTWH(-.4, -.4, .8, .8))
    ..addOval(const ui.Rect.fromLTWH(-.77, -.2, .64, .64))
    ..addOval(const ui.Rect.fromLTWH(-.14, -.69, .68, .68))
    ..addOval(const ui.Rect.fromLTWH(.22, -.12, .56, .56))
    ..addOval(const ui.Rect.fromLTWH(-.52, -.64, .52, .52))
    ..addOval(const ui.Rect.fromLTWH(-.16, .19, .62, .62))
    ..addOval(const ui.Rect.fromLTWH(-.64, .27, .42, .42));
  static final _waterShader = ui.Gradient.radial(
    const ui.Offset(-.3, -.4),
    1.6,
    const [ui.Color(0x18FFFFFF), ui.Color(0x07121C29), ui.Color(0x65101927)],
    const [0, .55, 1],
  );
  static final _softIceShader = ui.Gradient.radial(ui.Offset.zero, 1.2, const [
    ui.Color(0x9CE6EFF8),
    ui.Color(0x00E6EFF8),
  ]);

  void paint(
    ui.Canvas canvas,
    double height,
    double time,
    WorldSettings settings,
    ui.Image image,
    ui.Rect imageRect,
    ui.ColorFilter? colorFilter,
  ) {
    if (!settings.hasGlass || settings.intensity <= 0) return;
    _lensPaint.colorFilter = colorFilter;
    final snow = settings.weather == WorldWeather.snow;
    final count = ((snow ? 28 : 40) * settings.intensity).round();
    for (var i = 0; i < count; i++) {
      final p = _drops[i];
      final duration = snow ? 11 + p.speed * 9 : 9 + p.speed * 8;
      final life = ((time / duration) + p.phase) % 1;
      final opacity = _smooth(life / .035) * (1 - _smooth((life - .86) / .14));
      final anchorX = 12 + p.x * 376;
      final anchorY = 12 + p.y * (height - 36);
      if (snow) {
        final landing = 1 - _smooth(life / .12);
        final melt = _smooth((life - .52) / .35);
        final x = anchorX - landing * (8 + p.size * 10);
        final y = anchorY - landing * 17 + melt * melt * 12;
        final radius = (3 + p.size * 3.8) * (1 - melt * .68);
        if (melt > 0) {
          _drop(
            canvas,
            image,
            imageRect,
            x,
            y,
            1.2 + p.size * 1.6,
            1.5 + p.size * 2.1,
            opacity * melt * .8,
          );
        }
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(p.phase * math.pi * 2);
        canvas.scale(radius);
        _paint
          ..style = ui.PaintingStyle.fill
          ..shader = _softIceShader
          ..color = ui.Color.fromRGBO(255, 255, 255, opacity * (1 - melt) * .6);
        canvas.drawCircle(ui.Offset.zero, 1.2, _paint);
        _paint
          ..shader = null
          ..color = ui.Color.fromRGBO(
            235,
            244,
            252,
            opacity * (1 - melt) * .78,
          );
        canvas.drawPath(_snow, _paint);
        canvas.restore();
      } else {
        // Surface tension holds the bead, then gravity accelerates its slide.
        final slide = ((life - .48) / .52).clamp(0.0, 1.0);
        final travel = slide * slide * (65 + p.speed * 150);
        final x = anchorX + math.sin(slide * 7 + p.phase * 6) * slide * 2;
        final y = anchorY + travel;
        final radius = (1.6 + p.size * 3) * (.82 + .18 * _smooth(life / .48));
        if (travel > 2) {
          _trail
            ..reset()
            ..moveTo(anchorX, anchorY)
            ..cubicTo(
              anchorX + 1,
              anchorY + travel * .35,
              x - 1,
              y - travel * .2,
              x,
              y,
            );
          _paint
            ..shader = null
            ..style = ui.PaintingStyle.stroke
            ..strokeCap = ui.StrokeCap.round
            ..strokeWidth = radius * .7
            ..color = ui.Color.fromRGBO(18, 30, 42, opacity * .16);
          canvas.drawPath(_trail, _paint);
          _paint
            ..strokeWidth = .55
            ..color = ui.Color.fromRGBO(215, 231, 247, opacity * .24);
          canvas.drawPath(_trail, _paint);
        }
        _drop(
          canvas,
          image,
          imageRect,
          x,
          y,
          radius,
          radius * (1.2 + slide * .85),
          opacity,
        );
      }
    }
    // Small attached beads sell the glass plane between larger sliding drops.
    if (!snow) {
      for (var i = 40; i < 40 + (32 * settings.intensity).round(); i++) {
        final p = _drops[i];
        final opacity = .4 + .18 * math.sin(time * .24 + p.phase * 6);
        _drop(
          canvas,
          image,
          imageRect,
          8 + p.x * 384,
          8 + p.y * (height - 16),
          .6 + p.size,
          .8 + p.size,
          opacity,
        );
      }
    }
  }

  void _drop(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect imageRect,
    double x,
    double y,
    double rx,
    double ry,
    double opacity,
  ) {
    if (opacity < .005) return;
    // Sample a smaller piece of the already cropped scene through the bead.
    // Only the bead's pixels are redrawn; no full-screen blur or saveLayer.
    final scaleX = image.width / imageRect.width;
    final scaleY = image.height / imageRect.height;
    final source = ui.Rect.fromCenter(
      center: ui.Offset(
        (x - imageRect.left - rx * .18) * scaleX,
        (y - imageRect.top - ry * .22) * scaleY,
      ),
      width: rx * 2 * scaleX / 1.65,
      height: ry * 2 * scaleY / 1.65,
    );
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(rx, ry);
    canvas.save();
    canvas.clipPath(_bead);
    _lensPaint.color = ui.Color.fromRGBO(255, 255, 255, opacity * .88);
    canvas.drawImageRect(
      image,
      source,
      const ui.Rect.fromLTWH(-1, -1, 2, 2),
      _lensPaint,
    );
    canvas.restore();
    _paint
      ..style = ui.PaintingStyle.fill
      ..shader = _waterShader
      ..color = ui.Color.fromRGBO(255, 255, 255, opacity);
    canvas.drawPath(_bead, _paint);
    _paint
      ..shader = null
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = .1
      ..color = ui.Color.fromRGBO(10, 20, 31, opacity * .4);
    canvas.drawPath(_bead, _paint);
    _paint
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = .12
      ..color = ui.Color.fromRGBO(237, 247, 255, opacity * .65);
    canvas.drawPath(_highlight, _paint);
    _paint
      ..strokeWidth = .09
      ..color = ui.Color.fromRGBO(214, 235, 252, opacity * .5);
    canvas.drawPath(_caustic, _paint);
    canvas.restore();
  }

  static double _smooth(double value) {
    final v = value.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }
}

class _GlassParticle {
  const _GlassParticle(this.x, this.y, this.size, this.speed, this.phase);
  final double x, y, size, speed, phase;
}
