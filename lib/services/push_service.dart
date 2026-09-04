import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
/// someone has actually applied a wallpaper (see [maybeAskPermission]), when the
/// app has earned the question.
class PushService extends ChangeNotifier {
  PushService._();
  static final PushService instance = PushService._();

  /// Everyone who allows notifications joins this topic, so a campaign can be
  /// addressed to it from the Firebase console or the FCM API without needing
  /// a list of tokens.
  static const _topic = 'all';

  /// Applied wallpapers required before the prompt is worth asking for. Two is
  /// enough to show intent without waiting so long that the user is gone.
  static const _promptAfterApplies = 2;

  static const _fileName = 'push.json';

  bool _enabled = false;
  bool _asked = false;
  File? _file;

  /// Whether notifications are on. Drives the Settings switch.
  bool get enabled => _enabled;

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
  }

  /// Asks for notification permission, but only once the app has proved useful.
  ///
  /// Safe to call after every apply — it returns immediately unless this is the
  /// moment worth spending the one prompt Android gives us.
  Future<void> maybeAskPermission() async {
    if (_asked || _enabled) return;
    if (HistoryService.instance.ids.length < _promptAfterApplies) return;
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
      // A failed subscribe is recoverable: the next launch tries again.
    }
  }

  /// Opens whatever the notification points at.
  ///
  /// Campaigns carry a `link` data field holding an ordinary share URL, so the
  /// same path that handles a friend's shared link handles this — one way in,
  /// already tested. A notification without one just opens the app.
  void _handleTap(RemoteMessage message) {
    final link = message.data['link'];
    if (link is! String || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri != null) DeepLinkService.instance.handleUri(uri);
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
