import 'package:flutter/material.dart';

/// The colour a collection is dressed in: its section dot and "See all" on
/// the home screen, the spotlight chip, and the accent bar and chips on its
/// own page.
///
/// Only collections with a personality of their own get a custom one;
/// everything else wears the app accent. Keep the list short — an accent per
/// category stops meaning anything, and the app's own purple has to stay the
/// colour of the app.
class CollectionAccent {
  final Color color;
  final Color colorEnd;

  const CollectionAccent(this.color, this.colorEnd);

  /// The app accent, as a [CollectionAccent] so callers never branch.
  static const app = CollectionAccent(Color(0xFF6C5CE7), Color(0xFF8E7BF5));

  static const _custom = <String, CollectionAccent>{
    // Girly is the pink one; Aesthetic moved to lavender so the two rows
    // stay tellable apart at a glance.
    'girly': CollectionAccent(Color(0xFFF48FB1), Color(0xFFFFC1E3)),
    'aesthetic': CollectionAccent(Color(0xFFB39DDB), Color(0xFFE1BEE7)),
  };

  /// The accent for [categoryId]; the app accent when it has none of its own.
  static CollectionAccent of(String categoryId) => _custom[categoryId] ?? app;

  /// Only a custom accent, or null — for callers that leave the default
  /// alone (a section header that shows no dot for ordinary rows).
  static CollectionAccent? custom(String categoryId) => _custom[categoryId];

  LinearGradient get gradient => LinearGradient(colors: [color, colorEnd]);

  /// Text colour that reads on [gradient]: the pastel accents are light
  /// enough that white would vanish on them.
  Color get onColor =>
      color.computeLuminance() > 0.45 ? const Color(0xFF1A0F14) : Colors.white;
}
