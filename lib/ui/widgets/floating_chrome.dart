import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFF8E7BF5);

/// True on iOS 26+, where the native Liquid Glass controls (tab bar, popup
/// menus) are available. [Platform.operatingSystemVersion] is a free-form
/// string, so parse defensively.
bool get isIOS26OrAbove {
  if (!Platform.isIOS) return false;
  try {
    final match = RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion);
    if (match == null) return false;
    return int.parse(match.group(1)!) >= 26;
  } catch (_) {
    return false;
  }
}

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

/// One entry in a [SegmentedPill].
class SegmentedPillItem<T extends Object> {
  final T value;
  final IconData icon;

  /// Read by screen readers and shown as the tooltip — the pill itself is
  /// icon-only, so this is the only place the choice is named.
  final String label;

  const SegmentedPillItem({
    required this.value,
    required this.icon,
    required this.label,
  });
}

/// Icon-only switch between a few views, sized and dressed to sit in the
/// floating top row beside [TitlePill] and [ChromeIconButton].
///
/// **Tapping anywhere on it advances to the next item.** The segments show
/// where you are; they are not separate targets. For the two-item case this
/// is the point — the whole pill is one big toggle, and there is no dead
/// zone on the segment you are already on. With three or more it cycles,
/// which is fine for a glanceable view switch and wrong for a form control;
/// use a real segmented control for those.
///
/// Same platform split as its neighbours: iOS gets liquid glass, Android the
/// solid pill with the nav bar's sliding accent disc — so the selected segment
/// reads the same way the selected tab does, one screen-edge down. Generic
/// over [T] so it can switch anything, anywhere in the app.
class SegmentedPill<T extends Object> extends StatelessWidget {
  final List<SegmentedPillItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  /// Height and per-segment width. Defaults to the top-bar size so the pill
  /// lines up with the title beside it.
  final double size;

  const SegmentedPill({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.size = kTopBarHeight,
  }) : assert(items.length >= 2, 'A segmented pill needs at least two items');

  int get _index {
    final i = items.indexWhere((i) => i.value == value);
    return i < 0 ? 0 : i;
  }

  void _advance() => onChanged(items[(_index + 1) % items.length].value);

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return _glass(context);
    return _solid(context);
  }

  Widget _glass(BuildContext context) {
    final glyph = size * 0.5;
    // Every item advances, which keeps the package's own press-dim on
    // whichever segment was touched while still making the whole pill one
    // target. Selection is carried by colour: the group has no selected
    // state of its own, and the accent is what "chosen" means everywhere
    // else in the chrome.
    return Semantics(
      button: true,
      label: '${items[_index].label}. Tap to switch.',
      child: GlassButtonGroup.icons(
        borderRadius: size / 2,
        iconSize: glyph,
        itemPadding: EdgeInsets.all((size - glyph) / 2),
        items: [
          for (final item in items)
            GlassButtonGroupItem(
              icon: Icon(
                item.icon,
                color: item.value == value ? _accent : null,
                semanticLabel: item.label,
              ),
              onTap: _advance,
            ),
        ],
      ),
    );
  }

  Widget _solid(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glyph = size * 0.45;
    // Inset disc, like the nav bar's: it should read as sitting *inside* the
    // pill, not filling it edge to edge.
    const inset = 4.0;
    final disc = size - inset * 2;

    return Semantics(
      button: true,
      label: '${items[_index].label}. Tap to switch.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: SizedBox(
          height: size,
          width: size * items.length,
          // DecoratedBox, not Container: Container insets its child by the
          // border width, which left a 42px box for a 44px disc and pushed
          // the disc's rim over the pill's edge. DecoratedBox paints the
          // border and leaves the layout alone.
          child: DecoratedBox(
            decoration: _solidDecoration(context, radius: size / 2),
            child: Stack(
              children: [
                // The disc slides between segments rather than snapping —
                // the same motion the nav bar uses, so the two feel like one
                // system.
                AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(-1 + 2 * _index / (items.length - 1), 0),
                  child: Padding(
                    padding: const EdgeInsets.all(inset),
                    child: Container(
                      width: disc,
                      height: disc,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [_accent, _accentLight]),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: size,
                        height: size,
                        child: Icon(
                          item.icon,
                          size: glyph,
                          color: item.value == value
                              ? Colors.white
                              : (dark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating pill button with a label and an optional leading glyph — the wide
/// sibling of [ChromeIconButton].
///
/// Same platform split as the rest of this file: iOS gets liquid glass (with the
/// package's press stretch, so it feels like the nav bar it sits under), Android
/// gets the solid pill, because the glass pipeline is skipped there entirely
/// (see the `builder` in main.dart) and a lone glass widget would be the only
/// thing in the app paying for it.
class ChromePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const ChromePillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: _accent),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    if (Platform.isAndroid) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: kTopBarHeight,
          alignment: Alignment.center,
          decoration: _solidDecoration(context, radius: kTopBarHeight / 2),
          child: content,
        ),
      );
    }
    // Null width hugs the label (the package puts it straight on a SizedBox).
    return GlassButton.custom(
      onTap: onTap,
      height: kTopBarHeight,
      shape: const LiquidRoundedSuperellipse(borderRadius: kTopBarHeight / 2),
      child: content,
    );
  }
}

/// The search field in the floating row: a pill the same height as the
/// buttons beside it, with the glyph on the left and a clear button once
/// there is text. Glass on iOS, solid on Android, like every other pill.
class ChromeSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final bool autofocus;

  const ChromeSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.hint = 'Search wallpapers',
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dim = onSurface.withValues(alpha: 0.5);
    final content = Padding(
      padding: const EdgeInsets.only(left: 14, right: 6),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: dim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _accentLight,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: dim,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Rebuilds with the text so the clear button appears and goes
          // without the whole field having to.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 8)
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: dim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );

    if (Platform.isAndroid) {
      return Container(
        height: kTopBarHeight,
        decoration: _solidDecoration(context, radius: kTopBarHeight / 2),
        child: content,
      );
    }
    return GlassContainer(
      height: kTopBarHeight,
      shape: const LiquidRoundedSuperellipse(borderRadius: kTopBarHeight / 2),
      child: content,
    );
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
    if (MediaQuery.disableAnimationsOf(context)) {
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
