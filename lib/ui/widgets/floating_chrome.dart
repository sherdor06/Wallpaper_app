import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFF8E7BF5);

/// Height of the floating top-bar pills (title + settings button).
const double kTopBarHeight = 44;

/// Total vertical space the floating top bar occupies below the status bar
/// (pill height + 8 top gap). Tabs add this to their scroll top padding so
/// content starts below the chrome while still scrolling behind it.
const double kTopChrome = kTopBarHeight + 8;

/// Floating pill showing the current tab title.
///
/// iOS → liquid glass; Android → solid theme-aware pill (no blur — no jank),
/// styled like [CircleNavBar]. Both platforms get the orbiting gradient arc.
class TitlePill extends StatelessWidget {
  final String text;

  const TitlePill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    // The pill body differs per platform (glass vs solid), but the animated
    // orbiting arc wraps both so Android matches the iOS motion.
    final Widget pill = Platform.isAndroid
        ? Container(
            height: kTopBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: _solidDecoration(context, radius: 22),
            child: label,
          )
        : GlassContainer(
            height: kTopBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: const LiquidRoundedSuperellipse(borderRadius: 22),
            alignment: Alignment.center,
            child: label,
          );
    // A soft gradient arc slowly orbits the pill's border (both platforms).
    return _OrbitingGlow(child: pill);
  }
}

/// Floating round icon button (settings, etc.).
///
/// iOS → [GlassIconButton]; Android → solid theme-aware circle.
class ChromeIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Diameter of the button. Defaults to the top-bar size; pass a larger value
  /// for a more prominent, easier-to-tap control (e.g. the detail "random" FAB).
  final double size;

  /// Glyph size. Defaults to ~half the button so it scales with [size].
  final double? iconSize;

  const ChromeIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = kTopBarHeight,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = iconSize ?? size * 0.5;
    Widget button;
    if (!Platform.isAndroid) {
      button = GlassIconButton(
        icon: Icon(icon),
        onPressed: onTap,
        size: size,
        iconSize: glyph,
      );
    } else {
      final dark = Theme.of(context).brightness == Brightness.dark;
      button = GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: _solidDecoration(context, radius: size / 2),
          child: Icon(
            icon,
            size: glyph,
            color: dark ? Colors.white70 : Colors.black87,
          ),
        ),
      );
    }
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Continuously rotating gradient arc ("comet") around its [child] — decorates
/// the title pill on both platforms. Respects reduced motion (freezes when
/// animations are off).
class _OrbitingGlow extends StatefulWidget {
  final Widget child;

  const _OrbitingGlow({required this.child});

  @override
  State<_OrbitingGlow> createState() => _OrbitingGlowState();
}

class _OrbitingGlowState extends State<_OrbitingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system reduced-motion setting.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary keeps the per-frame repaint limited to the pill itself.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          foregroundPainter: _OrbitBorderPainter(progress: _controller.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Paints a short bright gradient arc sweeping around the pill's border, with a
/// soft blurred glow underneath it.
class _OrbitBorderPainter extends CustomPainter {
  final double progress;

  const _OrbitBorderPainter({required this.progress});

  // Transparent ends of the arc use the accent hue (not black) so the fade
  // into the glass edge stays clean instead of turning gray.
  static const _transparent = Color(0x006C5CE7);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1),
      Radius.circular(size.height / 2),
    );
    final gradient = SweepGradient(
      transform: GradientRotation(progress * 2 * math.pi),
      colors: const [
        _transparent,
        _transparent,
        _accent,
        _accentLight,
        Colors.white70,
        _transparent,
      ],
      stops: const [0.0, 0.55, 0.75, 0.88, 0.95, 1.0],
    );
    // Soft glow underneath the arc.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Crisp arc on top.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_OrbitBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Solid pill/circle decoration used on Android (matches [CircleNavBar]).
BoxDecoration _solidDecoration(BuildContext context, {required double radius}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark ? const Color(0xF21C1C26) : Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
        color: dark ? const Color(0x14FFFFFF) : const Color(0x14000000)),
    boxShadow: [
      BoxShadow(
        color: dark ? const Color(0x59000000) : const Color(0x1F000000),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ],
  );
}
