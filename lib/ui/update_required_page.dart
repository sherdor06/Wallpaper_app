import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../services/update_service.dart';
import 'accent.dart';

/// The hard stop for a build below `update_min_build`.
///
/// Shown in place of the home screen, so there is nothing behind it to go back
/// to; the back gesture leaves the app, the one other way out. Drawn on the
/// splash's own dark ground with the same logo, as the end of the launch it
/// interrupts rather than an error screen.
class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({super.key});

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage>
    with SingleTickerProviderStateMixin {
  /// Where the logo stops. The splash animation fades the logo out over its
  /// last frames (78–94 of 96) to hand over to the home screen; played to the
  /// end here, it left an empty space above the title.
  static const _holdAt = 0.6;

  late final AnimationController _logo = AnimationController(vsync: this);

  @override
  void dispose() {
    _logo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Light bar icons over the dark ground, whatever the app theme says.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: _page(),
    );
  }

  Widget _page() {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Lottie.asset(
                'assets/anim/splash_logo.json',
                width: 160,
                height: 160,
                controller: _logo,
                onLoaded: (composition) {
                  _logo
                    ..duration = composition.duration
                    ..animateTo(_holdAt).ignore();
                },
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.system_update_rounded,
                  size: 72,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Update required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'This version of Wavely is no longer supported. Update to the '
                'latest version to keep using the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: UpdateService.instance.updateNow,
                  child: const Text('Update'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
