// Basic smoke test: the app builds and mounts without errors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wallpaper_app_first/main.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const WallpaperApp());

    // The app builds its MaterialApp shell (splash → home).
    expect(find.byType(MaterialApp), findsOneWidget);

    // Let async work (splash animation, catalog load) advance a little so we
    // don't get a "pending timer" error on dispose.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
