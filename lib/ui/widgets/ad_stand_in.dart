import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../accent.dart';

/// Which full-screen format the stand-in is standing in for.
enum AdStandInKind { interstitial, rewarded }

/// What a debug run on a simulator shows where a full-screen ad would play.
///
/// No ad is ever requested there (see `AdService`), but the *moments* still
/// have to be visible, or nobody can tell whether the frequency logic fired.
/// So this page takes the ad's place: it names the format, says why it fired
/// and which unit a release build would have used, and closes on a tap. For a
/// rewarded ad, closing counts as watching — the unlock goes through.
///
/// Debug-only by construction: the only caller is behind `kDebugMode`.
class AdStandIn extends StatelessWidget {
  final AdStandInKind kind;

  /// Why the ad fired, in the service's own words ("Wallpaper applied — 3 of
  /// every 3").
  final String trigger;

  /// The unit id a release build would have requested on this platform.
  final String unitId;

  /// The shared full-screen cooldown, so the next moment's silence is
  /// explained before it happens.
  final Duration cooldown;

  const AdStandIn({
    super.key,
    required this.kind,
    required this.trigger,
    required this.unitId,
    required this.cooldown,
  });

  /// A route that fades in over whatever screen triggered the ad and fades
  /// back out to it — the same screen, untouched, which is what a dismissed
  /// ad leaves behind.
  static Route<void> route({
    required AdStandInKind kind,
    required String trigger,
    required String unitId,
    required Duration cooldown,
  }) => PageRouteBuilder<void>(
    opaque: true,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => AdStandIn(
      kind: kind,
      trigger: trigger,
      unitId: unitId,
      cooldown: cooldown,
    ),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  bool get _rewarded => kind == AdStandInKind.rewarded;

  @override
  Widget build(BuildContext context) {
    final title = _rewarded ? 'Rewarded ad' : 'Interstitial ad';
    final icon = _rewarded
        ? Icons.card_giftcard_rounded
        : Icons.fullscreen_rounded;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      // Always dark, whatever the theme, so the status bar goes light too.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF0E0E12),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const _Caps('DEBUG · SIMULATOR · NO AD REQUESTED'),
                  const Spacer(),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [kAccent, kAccentLight],
                      ),
                    ),
                    child: Icon(icon, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'would show here in a release build',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _Details(
                    rows: [
                      ('Trigger', trigger),
                      ('Unit', unitId),
                      (
                        'Cooldown',
                        '${cooldown.inSeconds} s before the next one',
                      ),
                      if (_rewarded) ('On close', 'reward granted'),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'Tap anywhere to close',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Caps extends StatelessWidget {
  final String text;
  const _Caps(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: kAccentLight,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );
}

class _Details extends StatelessWidget {
  final List<(String, String)> rows;
  const _Details({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
