import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/consent_service.dart';

/// The GDPR ad-personalisation prompt, shown once to EEA/UK users.
///
/// Two things about the layout are legal requirements rather than taste:
/// refusing is exactly as easy as accepting (same row, same weight, no dimmed
/// "no" button), and the dialog cannot be dismissed by tapping outside or by
/// the back gesture — a dismissal is neither consent nor refusal, and silently
/// treating it as either is what regulators object to.
///
/// Returns once [ConsentService.record] has stored the answer, which is also
/// what releases the ad SDK to start (see `AdService.init`).
Future<void> showConsentDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ConsentDialog(),
  );
}

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog();

  static const _privacyUrl = 'https://wallpapers-cdn.pages.dev/privacy';

  Future<void> _answer(BuildContext context, bool granted) async {
    await ConsentService.instance.record(granted);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.privacy_tip_outlined, size: 30),
        title: const Text('Personalised ads', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wavely is free because of ads. With your permission, our ad '
              'partner Yandex may use your device advertising ID to show ads '
              'that are more relevant to you.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'You can say no. Ads will still appear, they just will not be '
              'personalised — and you can change this any time in Settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(_privacyUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
        // Equal weight on both answers — see the class note.
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          OutlinedButton(
            onPressed: () => _answer(context, false),
            child: const Text('No thanks'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            onPressed: () => _answer(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
