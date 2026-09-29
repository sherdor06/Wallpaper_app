import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_app_first/models/world_composition.dart';
import 'package:wallpaper_app_first/ui/worlds/world_scene.dart';
import 'package:wallpaper_app_first/ui/worlds/world_studio_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image image;
  const size = ui.Size(320, 640);

  setUpAll(() async {
    final data = await rootBundle.load(WorldComposition.midnight.imagePath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  });
  tearDownAll(() => image.dispose());

  test('old and unknown view recipes remain open air; glass persists', () {
    expect(
      WorldSettings.fromJson({'weather': 'rain'}).weatherView,
      WorldWeatherView.openAir,
    );
    expect(
      WorldSettings.fromJson({'weatherView': 'unknown'}).weatherView,
      WorldWeatherView.openAir,
    );
    const original = WorldSettings();
    final glass = original.copyWith(weatherView: WorldWeatherView.window);
    expect(glass, isNot(original));
    expect(glass.hasGlass, isTrue);
    expect(WorldSettings.fromJson(glass.toJson()), glass);
    expect(glass.copyWith(intensity: .3).weatherView, WorldWeatherView.window);
    expect(glass.copyWith(weatherView: WorldWeatherView.openAir), original);
  });

  test(
    'glass is optional, animates deterministically, and respects motion off',
    () async {
      for (final weather in [WorldWeather.rain, WorldWeather.snow]) {
        final air = WorldSettings(weather: weather, drift: 0);
        final glass = air.copyWith(weatherView: WorldWeatherView.window);
        final openFrame = await renderWorld(image, air, size);
        final first = await renderWorld(image, glass, size);
        final later = await renderWorld(image, glass, size, time: 8);
        final repeated = await renderWorld(image, glass, size, time: 8);
        final frozen = await renderWorld(
          image,
          glass.copyWith(motion: false),
          size,
          time: 8,
        );
        expect(first, isNot(orderedEquals(openFrame)), reason: weather.name);
        expect(later, isNot(orderedEquals(first)), reason: weather.name);
        expect(later, orderedEquals(repeated));
        // Lens clipping can differ by one channel level on first rasterization.
        await expectSameScene(frozen, first);
        final frozenLater = await renderWorld(
          image,
          glass.copyWith(motion: false),
          size,
          time: 30,
        );
        await expectSameScene(frozenLater, frozen);
        final backToAir = await renderWorld(
          image,
          glass.copyWith(weatherView: WorldWeatherView.openAir),
          size,
        );
        expect(backToAir, orderedEquals(openFrame));
      }
    },
  );

  test('no glass at zero intensity or in non-precipitation weather', () async {
    for (final weather in WorldWeather.values) {
      final settings = WorldSettings(
        weather: weather,
        intensity: weather == WorldWeather.rain || weather == WorldWeather.snow
            ? 0
            : .8,
      );
      final air = await renderWorld(image, settings, size);
      final glass = await renderWorld(
        image,
        settings.copyWith(weatherView: WorldWeatherView.window),
        size,
      );
      expect(glass, orderedEquals(air), reason: weather.name);
    }
  });

  test(
    'glass supports strong crop, both focal extremes and full export size',
    () async {
      for (final focal in [0.0, 1.0]) {
        final bytes = await renderWorld(
          image,
          WorldSettings(
            weatherView: WorldWeatherView.window,
            intensity: 1,
            zoom: 1.6,
            focalX: focal,
            focalY: focal,
          ),
          exportSize(size),
          time: 18,
        );
        expect(bytes, isNotEmpty);
      }
    },
  );

  testWidgets(
    'small phone can switch between air and glass, then change weather',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const WorldStudioPage(world: WorldComposition.midnight),
        ),
      );
      for (
        var i = 0;
        i < 25 && find.byType(WorldScene).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(WorldScene), findsOneWidget);
      await tester.ensureVisible(find.text('Through glass'));
      await tester.tap(find.text('Through glass'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorldScene>(find.byType(WorldScene)).settings.hasGlass,
        isTrue,
      );
      await tester.ensureVisible(find.text('Snow'));
      await tester.tap(find.text('Snow'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorldScene>(find.byType(WorldScene)).settings.weather,
        WorldWeather.snow,
      );
      expect(
        tester.widget<WorldScene>(find.byType(WorldScene)).settings.hasGlass,
        isTrue,
      );
      await tester.ensureVisible(find.text('Open air'));
      await tester.tap(find.text('Open air'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorldScene>(find.byType(WorldScene)).settings.hasGlass,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  final output = Platform.environment['GLASS_PREVIEW_DIR'];
  if (output != null) {
    test('render glass review frames', () async {
      await Directory(output).create(recursive: true);
      for (final weather in [WorldWeather.rain, WorldWeather.snow]) {
        for (final view in WorldWeatherView.values) {
          for (var i = 0; i < 72; i++) {
            final bytes = await renderWorld(
              image,
              WorldSettings(
                weather: weather,
                weatherView: view,
                intensity: .85,
              ),
              size,
              time: i / 12,
            );
            await File(
              '$output/${weather.name}_${view.name}_$i.png',
            ).writeAsBytes(bytes);
          }
        }
      }
    });
  }
}

Future<void> expectSameScene(Uint8List actual, Uint8List expected) async {
  Future<Uint8List> pixels(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = (await codec.getNextFrame()).image;
    try {
      return (await frame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      frame.dispose();
      codec.dispose();
    }
  }

  final a = await pixels(actual), b = await pixels(expected);
  expect(a.length, b.length);
  var changedChannels = 0;
  var maxDifference = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > 0) changedChannels++;
    if (difference > maxDifference) maxDifference = difference;
  }
  expect(maxDifference, lessThanOrEqualTo(1));
  expect(changedChannels, lessThanOrEqualTo(16));
}
