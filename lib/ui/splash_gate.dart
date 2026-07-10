import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'home_shell.dart';

/// Animated splash: plays the logo animation once on the dark brand background,
/// then hands off to [HomeShell]. Shown right after the (static) native splash.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with TickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const HomeShell();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: Center(
        child: Lottie.asset(
          'assets/anim/splash_logo.json',
          controller: _controller,
          width: 220,
          height: 220,
          onLoaded: (composition) {
            _controller
              ..duration = composition.duration
              ..forward();
          },
          // If the asset fails to load, don't trap the user on the splash.
          errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_done) setState(() => _done = true);
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
