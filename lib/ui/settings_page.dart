import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_service.dart';
import '../services/consent_service.dart';
import '../services/push_service.dart';
import '../services/image_cache.dart';
import '../services/theme_service.dart';
import 'widgets/adaptive_settings.dart';
import 'widgets/consent_dialog.dart';

/// App settings / about screen: legal, storage, feedback and version info.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Served from the Pages CDN, not the old r2.dev bucket: R2 is a paid add-on
  /// that gets deactivated if the Cloudflare bill lapses, and a dead privacy
  /// policy URL is a store-compliance failure. Pages is on the free tier and is
  /// already where the app reads its catalog from.
  static const _privacyUrl = 'https://wallpapers-cdn.pages.dev/privacy';
  static const _storeUrl =
      'https://play.google.com/store/apps/details?id=com.sherdor.wallpapers';
  static const _contactEmail = 'sherdor0605@gmail.com';

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _clearCache(BuildContext context) async {
    await Future.wait([
      AppCache.clear(), // capped wallpaper thumb + full caches
      DefaultCacheManager().emptyCache(), // legacy default cache
    ]);
    // Also drop decoded images held in memory.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (context.mounted) showSettingsToast(context, 'Image cache cleared');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Settings',
      children: [
        SettingsSection(
          header: 'Appearance',
          children: [
            ListenableBuilder(
              listenable: ThemeService.instance,
              builder: (context, _) {
                final mode = ThemeService.instance.mode;
                return Column(
                  children: [
                    for (final m in ThemeMode.values)
                      SettingsRow(
                        icon: _themeIcon(m),
                        title: _themeLabel(m),
                        choice: true,
                        checked: mode == m,
                        onTap: () => ThemeService.instance.setMode(m),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        const SettingsSection(
          header: 'Notifications',
          children: [_PushRow()],
        ),
        SettingsSection(
          header: 'Legal',
          children: [
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              external: true,
              onTap: () => _open(Uri.parse(_privacyUrl)),
            ),
            // Only where consent was actually asked for. GDPR requires
            // withdrawal to be as easy as granting; showing this to a user who
            // was never asked would just raise a question they do not have.
            if (ConsentService.instance.appliesHere)
              const _AdPersonalisationRow(),
          ],
        ),
        SettingsSection(
          header: 'Storage',
          children: [
            SettingsRow(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear image cache',
              subtitle: 'Frees space used by downloaded thumbnails',
              onTap: () => _clearCache(context),
            ),
          ],
        ),
        SettingsSection(
          header: 'Feedback',
          children: [
            SettingsRow(
              icon: Icons.star_outline,
              title: 'Rate the app',
              external: true,
              onTap: () => _open(Uri.parse(_storeUrl)),
            ),
            SettingsRow(
              icon: Icons.mail_outline,
              title: 'Contact us',
              subtitle: _contactEmail,
              external: true,
              onTap: () => _open(Uri(
                scheme: 'mailto',
                path: _contactEmail,
                query: 'subject=Wavely feedback',
              )),
            ),
          ],
        ),
        SettingsSection(
          header: 'About',
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version;
                return SettingsRow(
                  icon: Icons.info_outline,
                  title: 'Wavely',
                  subtitle: version == null ? null : 'Version $version',
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

String _themeLabel(ThemeMode m) => switch (m) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

IconData _themeIcon(ThemeMode m) => switch (m) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

/// Notification switch.
///
/// Turning it on runs the same permission request the app makes after a couple
/// of applies — someone reaching for this switch has answered that question
/// themselves, so the "ask only once" guard does not apply.
///
/// A denied system permission cannot be re-requested from inside the app, so
/// the switch reports what actually happened rather than the tap.
class _PushRow extends StatelessWidget {
  const _PushRow();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PushService.instance,
      builder: (context, _) {
        final on = PushService.instance.enabled;
        return SettingsSwitchRow(
          icon: Icons.notifications_outlined,
          title: 'New wallpaper alerts',
          subtitle: on ? 'On — we will tell you when new wallpapers land' : 'Off',
          value: on,
          onChanged: (want) async {
            if (!want) {
              await PushService.instance.disable();
              return;
            }
            final granted = await PushService.instance.requestPermission();
            if (granted || !context.mounted) return;
            // Blocked at the OS level; the app cannot prompt again.
            showSettingsToast(
              context,
              'Notifications are blocked in system settings for this app.',
            );
          },
        );
      },
    );
  }
}

/// The consent row, kept stateful on its own so the rest of the page can stay
/// stateless — it is the only thing here that has to redraw after a tap.
class _AdPersonalisationRow extends StatefulWidget {
  const _AdPersonalisationRow();

  @override
  State<_AdPersonalisationRow> createState() => _AdPersonalisationRowState();
}

class _AdPersonalisationRowState extends State<_AdPersonalisationRow> {
  @override
  Widget build(BuildContext context) {
    final granted = ConsentService.instance.granted == true;
    return SettingsRow(
      icon: Icons.ads_click_outlined,
      title: 'Ad personalisation',
      subtitle: granted ? 'Personalised ads allowed' : 'Personalised ads turned off',
      onTap: () async {
        await showConsentDialog(context);
        if (!context.mounted) return;
        setState(() {});
        // The SDK is already running by now, so the new answer has to be pushed
        // to it — reading it at init only would strand the change until the
        // next cold start.
        await AdService.instance
            .updateUserConsent(ConsentService.instance.granted == true);
      },
    );
  }
}

