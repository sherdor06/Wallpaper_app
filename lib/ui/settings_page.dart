import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/image_cache.dart';
import '../services/theme_service.dart';

/// App settings / about screen: legal, storage, feedback and version info.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _privacyUrl =
      'https://pub-5fa9490de235468da94d96af1e8dfa7a.r2.dev/privacy_policy.html';
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
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Image cache cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListenableBuilder(
            listenable: ThemeService.instance,
            builder: (context, _) {
              final mode = ThemeService.instance.mode;
              return Column(
                children: [
                  for (final m in ThemeMode.values)
                    ListTile(
                      leading: Icon(_themeIcon(m)),
                      title: Text(_themeLabel(m)),
                      trailing: mode == m
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () => ThemeService.instance.setMode(m),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 0),
          const _SectionHeader('Legal'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(Uri.parse(_privacyUrl)),
          ),
          const Divider(height: 0),
          const _SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear image cache'),
            subtitle: const Text('Frees space used by downloaded thumbnails'),
            onTap: () => _clearCache(context),
          ),
          const Divider(height: 0),
          const _SectionHeader('Feedback'),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Rate the app'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(Uri.parse(_storeUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Contact us'),
            subtitle: const Text(_contactEmail),
            onTap: () => _open(Uri(
              scheme: 'mailto',
              path: _contactEmail,
              query: 'subject=Wallpapers 4K feedback',
            )),
          ),
          const Divider(height: 0),
          const _SectionHeader('About'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version;
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Wallpapers 4K — Free'),
                subtitle: Text(version == null ? '' : 'Version $version'),
              );
            },
          ),
        ],
      ),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
