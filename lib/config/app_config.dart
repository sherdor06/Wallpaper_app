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
      defaultValue: 'https://pub-5fa9490de235468da94d96af1e8dfa7a.r2.dev',
    ),
  );

  /// Catalog JSON URL (the `catalog.json` on R2).
  static String get catalogUrl => '$cdnBaseUrl/catalog.json';

  /// Whether a remote CDN base URL is configured. If not, the bundled sample is used.
  static bool get hasRemoteCatalog => cdnBaseUrl.isNotEmpty;

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
