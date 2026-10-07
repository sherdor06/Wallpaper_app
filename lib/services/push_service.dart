import 'dart:async' show unawaited;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'analytics_service.dart';
import 'deep_link_service.dart';
import 'history_service.dart';

/// Push notifications, used to tell people when there is new content.
///
/// A wallpaper is a one-off act: the user picks one, sets it, and has no reason
/// to open the app again for weeks. Push is the only thing that reverses that,
/// which is why it matters more here than the feature list suggests.
///
/// **The permission prompt is deliberately not shown at startup.** Android 13+
/// requires runtime consent, and a prompt on first launch — before the app has
/// done anything for the user — is mostly denied, permanently. This waits until
/// someone has actually applied or saved wallpapers (see [maybeAskPermission]),
/// when the app has earned the question. Where the system asks nothing (Android
/// 12 and older) the device joins at launch instead.
class PushService extends ChangeNotifier {
  PushService._();
  static final PushService instance = PushService._();

  /// Everyone who allows notifications joins this topic, so a campaign can be
  /// addressed to it from the Firebase console or the FCM API without needing
  /// a list of tokens.
  static const _topic = 'all';

  /// Wallpapers applied or saved before the prompt is worth asking for. Two is
  /// enough to show intent without waiting so long that the user is gone.
  static const _promptAfterApplies = 2;

  static const _fileName = 'push.json';

  bool _enabled = false;
  bool _asked = false;
  bool _promptedThisRun = false;
  File? _file;

  /// Whether notifications are on. Drives the Settings switch.
  bool get enabled => _enabled;

  /// Whether [maybeAskPermission] put the system prompt up in this run, so the
  /// review sheet can stay out of its way.
  bool get promptedThisRun => _promptedThisRun;

  /// Loads the stored state. Called before `runApp`.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          _enabled = data['enabled'] == true;
          _asked = data['asked'] == true;
        }
      }
    } catch (_) {
      // Unreadable store — treat as never asked.
    }

    // Taps are handled whether or not the app was running, so both paths are
    // wired up before anything else.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (_) {
      // No launching notification; ordinary start.
    }

    // Off the startup path: both reach the network.
    unawaited(_enabled ? _subscribe() : _enableIfAlreadyAllowed());

    // The console's "Send test message" addresses one device by its token.
    // Printed in debug only, so a test never has to go to the whole topic.
    if (kDebugMode) unawaited(_printToken());
  }

  /// Joins the topic without a prompt where the system needs none.
  ///
  /// Android 12 and older show notifications unless the user turns them off,
  /// so there is no question to ask. Waiting for the apply-count prompt there
  /// only left everyone who never applied two wallpapers off every campaign.
  /// Android 13+ and iOS report "not determined" until asked, and are left to
  /// [maybeAskPermission]. Never asked again once the user has had a say: a
  /// switch turned off in Settings stays off.
  Future<void> _enableIfAlreadyAllowed() async {
    if (_asked) return;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return;
      }
    } catch (_) {
      return;
    }
    _asked = true;
    _enabled = true;
    notifyListeners();
    await _subscribe();
    await _save();
  }

  Future<void> _printToken() async {
    try {
      debugPrint('FCM token: ${await FirebaseMessaging.instance.getToken()}');
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
    }
  }

  /// Asks for notification permission, but only once the app has proved useful.
  ///
  /// Safe to call after every apply or save — it returns immediately unless
  /// this is the moment worth spending the one prompt Android gives us.
  Future<void> maybeAskPermission() async {
    if (_asked || _enabled) return;
    if (HistoryService.instance.ids.length < _promptAfterApplies) return;
    _promptedThisRun = true;
    await requestPermission();
  }

  /// Shows the system prompt and, if allowed, subscribes to [_topic].
  ///
  /// Also the path the Settings switch takes, which is why it is public and
  /// ignores the "already asked" guard: a user turning this on by hand has
  /// answered the question themselves.
  Future<bool> requestPermission() async {
    _asked = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) await _subscribe();
      _enabled = granted;
    } catch (_) {
      _enabled = false;
    }
    notifyListeners();
    await _save();
    return _enabled;
  }

  /// Turns notifications off from Settings.
  ///
  /// Unsubscribes rather than only flipping a flag — the OS-level permission
  /// stays granted, so without this the device would keep receiving campaigns.
  Future<void> disable() async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(_topic);
    } catch (_) {
      // Offline; the flag below still stops us re-subscribing.
    }
    _enabled = false;
    notifyListeners();
    await _save();
  }

  Future<void> _subscribe() async {
    try {
      // iOS refuses topic subscription until APNs has handed over a token.
      if (Platform.isIOS) await FirebaseMessaging.instance.getAPNSToken();
      await FirebaseMessaging.instance.subscribeToTopic(_topic);
    } catch (_) {
      // A failed subscribe is recoverable: [init] subscribes again on every
      // launch while notifications are on.
    }
  }

  /// Counts the tap, then opens whatever the notification points at.
  ///
  /// Campaigns carry a `link` data field holding an ordinary share URL, so the
  /// same path that handles a friend's shared link handles this — one way in,
  /// already tested. A notification without one just opens the app.
  void _handleTap(RemoteMessage message) {
    final link = message.data['link'];
    final hasLink = link is String && link.isNotEmpty;
    AnalyticsService.logPushOpen(
      campaign: _campaignOf(message),
      target: hasLink ? 'link' : 'app',
    );
    if (!hasLink) return;
    final uri = Uri.tryParse(link);
    if (uri != null) unawaited(DeepLinkService.instance.handleUri(uri));
  }

  /// The name a tap is counted under: the message's `campaign` data field,
  /// else its title.
  ///
  /// The console's own campaign name never reaches the app on Android — FCM
  /// strips its `google.*` keys from the data — so a campaign that should be
  /// told apart from the next one with the same title sets `campaign` under
  /// "Custom data". Cut to Analytics' 100-character limit for a value.
  static String _campaignOf(RemoteMessage message) {
    final named = message.data['campaign'];
    final name = named is String && named.isNotEmpty
        ? named
        : message.notification?.title ?? 'untitled';
    return name.length > 100 ? name.substring(0, 100) : name;
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(
        jsonEncode({'enabled': _enabled, 'asked': _asked}),
      );
    } catch (_) {
      // Losing this only means asking again later.
    }
  }
}
