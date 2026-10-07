import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../services/consent_service.dart';
import '../services/update_service.dart';
import 'home_shell.dart';
import 'update_required_page.dart';
import 'widgets/consent_dialog.dart';

/// Animated splash: plays the logo animation once on the dark brand background,
/// then hands off to [HomeShell]. Shown right after the (static) native splash.
///
/// Also the place the consent dialog is raised, for EEA/UK users on their first
/// launch. It waits for the splash rather than racing it: the ad SDK is blocked
/// on the answer anyway, and a modal thrown over a playing animation reads as a
/// glitch. The update offer comes after it, and a build below the supported
/// floor gets [UpdateRequiredPage] instead of the home screen.
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
        _afterSplash();
      }
    });
  }

  /// What follows the splash, once the grid is behind it: the consent dialog
  /// if this user has to be asked at all, then the update offer. In turn,
  /// never stacked — Play's update sheet over an open consent dialog would ask
  /// two questions at once. Deferred to the next frame so [HomeShell] is
  /// mounted and the modal has something to sit over.
  void _afterSplash() {
    if (UpdateService.instance.need == UpdateNeed.required) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ConsentService.instance.isRequired && mounted) {
        await showConsentDialog(context);
      }
      await _offerUpdate();
    });
  }

  /// Play shows its own sheet for the offer; what is left here is the
  /// follow-up — restart once the download is in, or the store page where Play
  /// cannot run the flow. A snack bar, as Play's guidelines suggest: it waits
  /// at the bottom without stopping anything.
  Future<void> _offerUpdate() async {
    if (UpdateService.instance.need != UpdateNeed.suggested) return;
    // Let the home screen settle before anything else claims the screen.
    await Future<void>.delayed(const Duration(seconds: 2));
    final result = await UpdateService.instance.offer();
    if (!mounted || result == OfferResult.nothing) return;
    final downloaded = result == OfferResult.downloaded;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        persist: true,
        showCloseIcon: true,
        content: Text(
          downloaded
              ? 'Update downloaded'
              : 'A new version of Wavely is available',
        ),
        action: SnackBarAction(
          label: downloaded ? 'Restart' : 'Update',
          onPressed: downloaded
              ? UpdateService.instance.installDownloaded
              : UpdateService.instance.openStore,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return UpdateService.instance.need == UpdateNeed.required
          ? const UpdateRequiredPage()
          : const HomeShell();
    }

    // Light bar icons over the dark ground, whatever the app theme says.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: _splash(),
    );
  }

  Widget _splash() {
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
              if (!mounted || _done) return;
              setState(() => _done = true);
              _afterSplash();
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
