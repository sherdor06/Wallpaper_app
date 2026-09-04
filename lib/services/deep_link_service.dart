import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../data/wallpaper_repository.dart';
import '../models/wallpaper.dart';
import '../ui/detail_page.dart';

/// Turns a shared wallpaper link into an open detail page.
///
/// The link is a plain https URL on the CDN's own domain
/// (`https://<host>/w/<id>`), which is what makes the two halves of sharing
/// work from a single string:
///
///  * With the app installed, Android App Links hands the URL straight to us —
///    the friend lands on the wallpaper, no browser, no chooser. That requires
///    the domain to vouch for the app in `.well-known/assetlinks.json`; without
///    it Android falls back to asking, which still works but is uglier.
///  * Without the app, it is an ordinary web page, and the page sends them to
///    the Play Store.
///
/// A custom scheme (`wavely://`) would have been less work and strictly worse:
/// it does nothing at all for someone who has not installed the app, which is
/// exactly the person a share is trying to reach.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  /// Host and path the share links live on. Must match the intent filter in
  /// AndroidManifest.xml and the `_redirects` rule on the site.
  static const _host = 'wallpapers-cdn.pages.dev';
  static const _pathPrefix = '/w/';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigator;

  /// The URL to share for [wallpaperId].
  ///
  /// Ids carry a slash (`nature/tg_18493`) and become path segments, so the
  /// result reads as a normal nested URL rather than something escaped.
  static Uri shareUrlFor(String wallpaperId) =>
      Uri.parse('https://$_host$_pathPrefix$wallpaperId');

  /// Extracts a wallpaper id from an incoming link, or null if it is not one of
  /// ours. Deliberately strict about host and prefix: anything else reaching
  /// this app is not a link we published.
  static String? wallpaperIdFrom(Uri uri) {
    if (uri.host != _host) return null;
    if (!uri.path.startsWith(_pathPrefix)) return null;
    final id = uri.path.substring(_pathPrefix.length);
    return id.isEmpty ? null : Uri.decodeComponent(id);
  }

  /// Starts listening. [navigator] is the app's navigator key, since links
  /// arrive from outside the widget tree and there is no context to push with.
  ///
  /// Called after `runApp` — a link that launched the app is delivered by
  /// [AppLinks.getInitialLink] and would otherwise be missed.
  Future<void> init(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    _sub ??= _appLinks.uriLinkStream.listen(
      _open,
      // A malformed link is the sender's problem, not a crash.
      onError: (_) {},
    );
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _open(initial);
    } catch (_) {
      // Nothing launched us; normal cold start.
    }
  }

  Future<void> _open(Uri uri) async {
    final id = wallpaperIdFrom(uri);
    if (id == null) return;

    // The catalog may still be loading on a cold start; this awaits it rather
    // than dropping the link.
    final Catalog catalog;
    try {
      catalog = await WallpaperRepository.instance.fetchCatalog();
    } catch (_) {
      return;
    }

    Wallpaper? match;
    for (final w in catalog.wallpapers) {
      if (w.id == id) {
        match = w;
        break;
      }
    }
    // Deleted since it was shared, or a hand-typed URL. Silently staying on the
    // gallery beats an error the user can do nothing about.
    if (match == null) return;

    final nav = _navigator?.currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute(builder: (_) => DetailPage(wallpaper: match!)));
  }
}
