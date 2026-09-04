import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Branded loading indicator (Lottie) used instead of CircularProgressIndicator
/// wherever the catalog/content is loading.
class AppLoader extends StatelessWidget {
  final double size;

  const AppLoader({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/anim/loading.json',
        width: size,
        height: size,
        repeat: true,
        // A decode failure must not take the screen with it — this sits in the
        // loading path of every tab, so falling back to a plain spinner keeps
        // the app usable even if the asset is ever corrupted or missing.
        errorBuilder: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}
