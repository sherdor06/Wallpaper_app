import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Small chip badge — for the "4K", "LIVE", "PRO" labels shown over a wallpaper.
class WallpaperBadge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;

  const WallpaperBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = Colors.black54,
  });

  /// Live (video) wallpaper badge.
  const WallpaperBadge.live({Key? key})
      : this(key: key, label: 'LIVE', icon: Icons.play_circle_fill, color: const Color(0xCCE53935));

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color == Colors.black54 ? Colors.white : color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
    if (!Platform.isAndroid) {
      // iOS: liquid-glass background; the icon keeps its accent color (red=LIVE)
      // so the meaning stays readable through the glass.
      return GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
        child: content,
      );
    }
    // Android: solid dark scrim pill — readable over any photo, and no glass
    // shader cost in every grid cell (this badge is drawn dozens of times).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: content,
    );
  }
}
