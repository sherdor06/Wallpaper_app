import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A reusable frosted-glass surface (blur + translucent tint).
///
/// Used for the top app bar and the per-tab headers so they share the same
/// translucent look as the bottom navigation bar — content scrolled underneath
/// shows through blurred, matching the iOS 26 aesthetic.
class FrostedBar extends StatelessWidget {
  final Widget child;

  /// Tint painted over the blur. Defaults to the same translucent glass used by
  /// the bottom navigation bar so the two bars read as one material.
  final Color color;

  const FrostedBar({
    super.key,
    required this.child,
    this.color = const Color(0x14FFFFFF), // ~8% white — matches the nav bar
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: ColoredBox(
          color: color,
          child: child,
        ),
      ),
    );
  }
}
