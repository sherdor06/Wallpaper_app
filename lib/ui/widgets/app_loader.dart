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
      ),
    );
  }
}
