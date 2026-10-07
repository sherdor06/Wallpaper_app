import 'dart:convert';
import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'remote_config_service.dart';

/// What this build owes the user about updating.
enum UpdateNeed {
  /// Current, or nothing to say.
  none,

  /// A newer build is out; offer it, once in a while, and let them decline.
  suggested,

  /// This build is below the supported floor; the app stops until updated.
  required,
}

/// Tells users of older builds that a newer one is out.
///
/// Two halves, on purpose. **Whether** to ask is decided remotely, by build
/// number (the `+N` in pubspec), through Remote Config: `update_latest_build`
/// for a polite offer and `update_min_build` for a hard stop. A minor fix need
/// not nag anyone, and a build found to be broken can be shut out within the
/// hour without shipping anything. Builds are compared rather than version
/// names because releases often share a name (1.0.2+6, 1.0.2+7).
///
/// **How** to update is Google Play's own in-app flow. The offer is the
/// flexible one: Play's sheet, a download in the background while the app
/// stays usable, then a restart the user chooses. The hard stop is Play's
/// immediate flow. Where Play cannot run the flow — a build not installed from
/// Play, or a Play without the update yet — both fall back to the store page.
///
/// iOS stays out until the app has an App Store listing to send people to.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _playUrl =
      'https://play.google.com/store/apps/details?id=com.sherdor.wallpapers';

  /// A declined offer is not repeated for this long, however many launches
  /// come in between.
  static const _snooze = Duration(days: 3);

  static const _fileName = 'update.json';

  int? _build;

  /// Reads this build's number. Called before `runApp`, after Remote Config,
  /// so [need] is answerable by the first frame.
  Future<void> init() async {
    try {
      _build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } catch (_) {
      // Unknown build: [need] stays at none rather than guessing.
    }
  }

  UpdateNeed get need {
    final build = _build;
    if (build == null || !Platform.isAndroid) return UpdateNeed.none;
    final rc = RemoteConfigService.instance;
    if (build < rc.updateMinBuild) return UpdateNeed.required;
    if (build < rc.updateLatestBuild) return UpdateNeed.suggested;
    return UpdateNeed.none;
  }

  /// Offers the newer build, if there is one and the user has not just turned
  /// it down. Returns what the caller should show next:
  ///
  /// * [OfferResult.downloaded] — the update is on the device; ask to restart
  ///   ([installDownloaded]).
  /// * [OfferResult.storeOnly] — Play cannot run its own flow here; offer the
  ///   store page ([openStore]).
  /// * [OfferResult.nothing] — nothing to show.
  Future<OfferResult> offer() async {
    if (need != UpdateNeed.suggested) return OfferResult.nothing;
    final AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (_) {
      // Not installed from Play: no flow to run, but the user may still want
      // the newer build.
      if (!await _askedRecently()) {
        await _noteAsked();
        return OfferResult.storeOnly;
      }
      return OfferResult.nothing;
    }
    // Downloaded on an earlier launch and never installed: no need to ask
    // twice, only to finish.
    if (info.installStatus == InstallStatus.downloaded) {
      return OfferResult.downloaded;
    }
    // Play says no update for this device yet (staged rollout, or the release
    // is still in review): Play knows better than the remote number.
    if (info.updateAvailability != UpdateAvailability.updateAvailable ||
        !info.flexibleUpdateAllowed) {
      return OfferResult.nothing;
    }
    if (await _askedRecently()) return OfferResult.nothing;
    await _noteAsked();
    try {
      // Completes once the download has finished, not when the user agrees.
      final result = await InAppUpdate.startFlexibleUpdate();
      return result == AppUpdateResult.success
          ? OfferResult.downloaded
          : OfferResult.nothing;
    } catch (_) {
      return OfferResult.nothing;
    }
  }

  /// Installs a flexible update and restarts the app.
  Future<void> installDownloaded() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      await openStore();
    }
  }

  /// The required-update path: Play's full-screen flow where it can run, the
  /// store page otherwise.
  Future<void> updateNow() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        // Declining Play's screen leaves the user on the page, free to tap
        // again; only a flow that failed is sent on to the store.
        final result = await InAppUpdate.performImmediateUpdate();
        if (result != AppUpdateResult.inAppUpdateFailed) return;
      }
    } catch (_) {
      // Fall through to the store.
    }
    await openStore();
  }

  Future<void> openStore() async {
    try {
      await launchUrl(Uri.parse(_playUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser or store app; nothing more the app can do.
    }
  }

  Future<File?> _store() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _askedRecently() async {
    try {
      final file = await _store();
      if (file == null || !await file.exists()) return false;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['askedAt'] is! int) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(data['askedAt'] as int);
      return DateTime.now().difference(at) < _snooze;
    } catch (_) {
      return false;
    }
  }

  Future<void> _noteAsked() async {
    try {
      await (await _store())?.writeAsString(
        jsonEncode({'askedAt': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {
      // Losing this only means the offer may come back sooner.
    }
  }
}

/// What [UpdateService.offer] leaves for the caller to show.
enum OfferResult { nothing, downloaded, storeOnly }
