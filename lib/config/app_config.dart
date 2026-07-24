/// App configuration (provided at compile time via `--dart-define`).
///
/// The CDN base URL is not hardcoded — so test/prod can be switched easily.
/// Run with:
///   flutter run --dart-define=CDN_BASE_URL=https://cdn.myapp.com
///   flutter build apk --dart-define=CDN_BASE_URL=https://cdn.myapp.com
///
/// If `CDN_BASE_URL` is not provided, the default below (a dev r2.dev URL) is used.
/// When it is empty, the app falls back to the bundled sample catalog
/// (assets/catalog.sample.json) so it still works before R2 is configured.
class AppConfig {
  AppConfig._();

  /// Cloudflare R2/CDN base URL. A trailing `/` is stripped automatically.
  ///
  /// The default is a dev r2.dev public URL. For production, override it with a
  /// custom domain: `flutter build apk --dart-define=CDN_BASE_URL=https://cdn.myapp.com`
  static final String cdnBaseUrl = _trimSlash(
    const String.fromEnvironment(
      'CDN_BASE_URL',
      // Cloudflare Pages (free, unlimited bandwidth + CDN — no r2.dev throttle).
      // Deploy new content with: wrangler pages deploy scripts/out
      //   --project-name=wallpapers-cdn --branch=main
      defaultValue: 'https://wallpapers-cdn.pages.dev',
    ),
  );

  /// Catalog JSON URL (the `catalog.json` on R2).
  static String get catalogUrl => '$cdnBaseUrl/catalog.json';

  /// Whether a remote CDN base URL is configured. If not, the bundled sample is used.
  static bool get hasRemoteCatalog => cdnBaseUrl.isNotEmpty;

  /// Yandex AppMetrica API key (provided at build time). When empty, AppMetrica
  /// is skipped entirely. Create an app at https://appmetrica.yandex.com and pass
  /// its key:
  ///   flutter build apk --dart-define=APPMETRICA_API_KEY=xxxxxxxx-xxxx-xxxx-...
  static const String appMetricaApiKey = String.fromEnvironment(
    'APPMETRICA_API_KEY',
    defaultValue: 'c94e6a6e-c3cc-4482-9e48-0ab8c93f8aa0',
  );

  /// Whether Yandex AppMetrica is configured (a key was provided).
  static bool get hasAppMetrica => appMetricaApiKey.isNotEmpty;

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
