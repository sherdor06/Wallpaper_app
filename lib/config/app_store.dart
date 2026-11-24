/// The store this build is distributed through, fixed at build time:
///
///   flutter build apk --release --dart-define=STORE=rustore
///
/// Play is the default, so the Play bundle needs nothing extra. Each store gets
/// its own build rather than the app reading its installer at runtime: a store
/// reviewer may install the APK with tooling that records no installer, and
/// Galaxy Store and RuStore both reject an app that sends its users to another
/// store. Everything that leads to "the store" goes through [current].
enum AppStore {
  play,
  rustore,
  galaxy,
  appgallery;

  static const _packageName = 'com.sherdor.wallpapers';

  /// An unknown `STORE` value falls back to Play, the store most installs
  /// come from.
  static final AppStore current = AppStore.values.firstWhere(
    (store) => store.name == const String.fromEnvironment('STORE'),
    orElse: () => AppStore.play,
  );

  /// The app's page in this store. Where the store's app is installed, the
  /// link opens there; otherwise in the browser (AppGallery has no web page
  /// addressed by package name, so its link needs the AppGallery app).
  Uri get listing => Uri.parse(switch (this) {
    play => 'https://play.google.com/store/apps/details?id=$_packageName',
    rustore => 'https://apps.rustore.ru/app/$_packageName',
    galaxy => 'https://galaxystore.samsung.com/detail/$_packageName',
    appgallery => 'appmarket://details?id=$_packageName',
  });

  /// Whether Google Play's in-app update and review sheets can run. Play only
  /// runs them for apps it installed, and a build meant for another store
  /// must not reach for Play at all.
  bool get hasPlayFlows => this == play;
}
