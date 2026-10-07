import 'dart:convert';
import 'dart:io';

import 'package:in_app_review/in_app_review.dart';
import 'package:path_provider/path_provider.dart';

import 'analytics_service.dart';
import 'history_service.dart';
import 'push_service.dart';

/// Asks for a store rating, in the store's own sheet, at a moment the app has
/// clearly worked.
///
/// Ratings decide where the app ranks in Play search and whether a visitor to
/// the listing installs it, and the "Rate the app" row in Settings is almost
/// never visited. The in-app sheet is the only prompt most people will see.
///
/// **The store decides whether the sheet actually appears.** Play and iOS both
/// keep a hidden quota (iOS: three times a year) and say nothing when they
/// decline, so this cannot know whether anyone saw it. It only picks the moment
/// and keeps its own interval, so the quota is not spent on a bad one. Store
/// policy also forbids asking first ("Enjoying Wavely?") and only then sending
/// the happy users to the sheet, so it is called directly.
///
/// On Android the sheet only shows in builds installed from Play (internal
/// testing counts); a `flutter run` build gets a silent no-op. The iOS
/// simulator shows it every time.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  /// Wallpapers applied or saved before the first ask. One could be luck;
  /// three is someone who keeps coming back to the app for the thing it does.
  static const _afterSaves = 3;

  /// Gap between asks. The stores cap them anyway, and an ask the store
  /// swallows is still one this app cannot take back.
  static const _interval = Duration(days: 60);

  /// Lets the "Applied" confirmation land before the sheet covers it.
  static const _settle = Duration(milliseconds: 1200);

  static const _fileName = 'review.json';

  File? _file;
  bool _loaded = false;
  bool _askedThisRun = false;
  DateTime? _lastAsked;

  /// Called after every successful apply or save. Returns at once unless this
  /// is the moment worth spending a store prompt on.
  ///
  /// The caller decides not to call it when a full-screen ad has just played:
  /// a rating asked for straight after an ad is a rating of the ad.
  Future<void> maybeAsk() async {
    if (_askedThisRun) return;
    if (HistoryService.instance.ids.length < _afterSaves) return;
    // The notification prompt may be on screen from this same tap. Two system
    // dialogs in a row read as the app nagging, and the review loses.
    if (PushService.instance.promptedThisRun) return;
    await _load();
    final last = _lastAsked;
    if (last != null && DateTime.now().difference(last) < _interval) return;
    _askedThisRun = true;
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await Future<void>.delayed(_settle);
      await review.requestReview();
      _lastAsked = DateTime.now();
      AnalyticsService.logReviewPrompt();
      await _save();
    } catch (_) {
      // No store on this device, or the request failed. Nothing to show the
      // user, and the next run is free to try again.
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['lastAsked'] is int) {
          _lastAsked = DateTime.fromMillisecondsSinceEpoch(
            data['lastAsked'] as int,
          );
        }
      }
    } catch (_) {
      // Unreadable store: treat as never asked.
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(
        jsonEncode({'lastAsked': _lastAsked?.millisecondsSinceEpoch}),
      );
    } catch (_) {
      // Losing this only means the next ask may come sooner.
    }
  }
}
