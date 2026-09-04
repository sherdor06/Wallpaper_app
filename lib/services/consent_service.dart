import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:path_provider/path_provider.dart';

import 'remote_config_service.dart';

/// Decides whether personalised ads are allowed, and remembers the answer.
///
/// The Yandex SDK ships no consent management platform — `setUserConsent` is a
/// single boolean it expects the app to have earned. This is where that boolean
/// comes from.
///
/// Outside the EEA/UK there is no GDPR to satisfy, so consent is granted without
/// asking; the alternative is serving non-personalised ads (and taking the lower
/// price) to the CIS audience this app actually lives on. Inside it, nothing is
/// assumed until the user answers the dialog.
///
/// **This is not an IAB TCF certified CMP.** It sets the one flag the Yandex SDK
/// reads and stores the user's choice; it does not build a TC string or signal
/// other vendors. That is enough for this app's single-network setup, and would
/// have to be revisited if mediation is added or EEA traffic stops being a tail.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  static const _fileName = 'consent.json';

  /// EEA member states plus the three EFTA countries inside the EEA, plus the
  /// UK — which left the EU with UK GDPR still in force, so it asks the same
  /// question.
  static const _gdprCountries = <String>{
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', //
    'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK',
    'SI', 'ES', 'SE', // EU 27
    'IS', 'LI', 'NO', // EEA/EFTA
    'GB', // UK GDPR
  };

  File? _file;
  bool? _granted;
  final Completer<bool> _decided = Completer<bool>();

  /// Resolves to the consent flag once it is known: immediately where consent
  /// is not required or an answer is already stored, and otherwise when the
  /// user answers the dialog.
  ///
  /// [AdService.init] awaits this before starting the SDK, so no ad request can
  /// go out carrying a consent value the user has not given.
  Future<bool> get decision => _decided.future;

  /// Whether the dialog still has to be shown — consent applies here and the
  /// user has not answered yet.
  bool get isRequired => _appliesHere && _granted == null;

  /// Whether consent applies to this user at all. Drives the Settings row:
  /// consent that cannot be withdrawn as easily as it was given is not consent,
  /// but showing that row to a user who was never asked is just confusing.
  bool get appliesHere => _appliesHere;

  /// The stored answer, or null while unanswered.
  bool? get granted => _granted;

  /// Two independent signals, either of which is enough to ask.
  ///
  /// Remote Config is the accurate one: Firebase resolves the country
  /// server-side from the request, so a `consent_required` condition targeting
  /// EEA countries answers this properly. Device locale is the fallback for
  /// when Remote Config never fetched — a first launch offline, or a blocked
  /// network — because defaulting that case to "no consent needed" would be
  /// wrong in exactly the region where being wrong matters.
  ///
  /// Erring towards asking is deliberate: a Tashkent user with an en-GB phone
  /// sees one extra dialog, which costs far less than an EEA user who was never
  /// asked at all.
  bool get _appliesHere =>
      RemoteConfigService.instance.consentRequired || _localeSuggestsGdpr;

  static bool get _localeSuggestsGdpr => PlatformDispatcher.instance.locales
      .any((l) => _gdprCountries.contains(l.countryCode?.toUpperCase()));

  /// Loads any stored answer. Called before `runApp`, after Remote Config so
  /// [_appliesHere] can see the fetched flag.
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      _file = file;
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map && data['granted'] is bool) {
          _granted = data['granted'] as bool;
        }
      }
    } catch (_) {
      // Unreadable store — treat as unanswered and ask again.
    }

    // Nothing to wait for when consent does not apply, or it is already given.
    if (!_appliesHere) {
      _settle(true);
    } else if (_granted != null) {
      _settle(_granted!);
    }
  }

  /// Records the user's answer, releases [decision], and persists.
  ///
  /// Safe to call again when the user changes their mind from Settings: the
  /// stored value and the SDK flag both update, and the already-completed
  /// [decision] is simply left alone.
  Future<void> record(bool granted) async {
    _granted = granted;
    _settle(granted);
    try {
      await _file?.writeAsString(jsonEncode({
        'granted': granted,
        'at': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (_) {
      // Not persisting means asking again next launch — annoying, not harmful.
    }
  }

  void _settle(bool value) {
    if (!_decided.isCompleted) _decided.complete(value);
  }
}
