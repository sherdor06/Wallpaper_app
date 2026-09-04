import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'floating_chrome.dart';

/// Fallback animation used when a screen's own asset cannot be loaded. It ships
/// with the app, so it is always there.
const _fallbackAnimation = 'assets/anim/empty.json';

/// Shared empty state: a looping line-art animation over a headline, one line
/// explaining how the screen fills up, and an optional action.
///
/// One widget rather than one per screen. The only things that differ between
/// Favorites and Archive are the asset, the words, and whether there is a
/// button; keeping the geometry in a single place is what stops the two from
/// drifting apart the next time either is touched.
class EmptyState extends StatelessWidget {
  /// Bundled Lottie JSON — `assets/anim/…`, never a network fetch. An empty
  /// state is exactly the screen a user sees while offline.
  final String animation;

  final String headline;
  final String? subLine;

  /// Optional action. The button appears only when both are given.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Glyph drawn if no animation loads at all — see [_art].
  final IconData fallbackIcon;

  /// Box the animation is drawn in. 130 suits artwork that fills its canvas;
  /// raise it for a drawing that only occupies part of one, so the two states
  /// read as the same size even though their assets do not.
  ///
  /// The grid animation is the case in point: its cards cover about half the
  /// canvas width, so at 130 it looked noticeably smaller than the heart, which
  /// spans nearly all of its own.
  final double artSize;

  const EmptyState({
    super.key,
    required this.animation,
    required this.headline,
    required this.fallbackIcon,
    this.subLine,
    this.actionLabel,
    this.onAction,
    this.artSize = 130,
  });

  /// The animation, with two levels of fallback beneath it.
  ///
  /// [animation] first, then the bundled [_fallbackAnimation], then a plain
  /// glyph. An empty state is the one screen that exists to explain an absence,
  /// so it must never be the thing that breaks — and a missing asset is a silent
  /// failure at runtime, not a compile error.
  Widget _art(BuildContext context) {
    final muted = Theme.of(context).disabledColor;
    return Lottie.asset(
      animation,
      width: artSize,
      height: artSize,
      repeat: true,
      errorBuilder: (_, __, ___) => Lottie.asset(
        _fallbackAnimation,
        width: artSize,
        height: artSize,
        repeat: true,
        errorBuilder: (_, __, ___) => SizedBox(
          width: artSize,
          height: artSize,
          child: Center(
            child: Icon(fallbackIcon, size: artSize * 0.42, color: muted),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _art(context),
        const SizedBox(height: 10),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        if (subLine != null) ...[
          const SizedBox(height: 6),
          // Held narrow so the line breaks near the middle instead of running
          // the full width of a tablet.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              subLine!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          ChromePillButton(
            label: actionLabel!,
            icon: Icons.grid_view_rounded,
            onTap: onAction!,
          ),
        ],
      ],
    );
  }
}
