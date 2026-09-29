import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_app_first/models/world_composition.dart';
import 'package:wallpaper_app_first/ui/worlds/world_scene.dart';
import 'package:wallpaper_app_first/ui/worlds/world_weather.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image image;
  const size = ui.Size(320, 640);

  setUpAll(() async {
    await WorldWeatherRenderer.prepare();
    final asset = await rootBundle.load(WorldComposition.midnight.imagePath);
    final codec = await ui.instantiateImageCodec(asset.buffer.asUint8List());
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  });
  tearDownAll(() => image.dispose());

  test('old recipes and every weather mode survive save/load', () {
    for (final weather in WorldWeather.values) {
      final settings = WorldSettings(weather: weather, intensity: .8);
      expect(WorldSettings.fromJson(settings.toJson()), settings);
    }
    expect(
      WorldSettings.fromJson({'weather': 'fog'}).weather,
      WorldWeather.fog,
    );
    expect(
      WorldSettings.fromJson({'weather': 'future'}).weather,
      WorldWeather.rain,
    );
  });

  test(
    'zero intensity leaves the original scene intact for every weather',
    () async {
      final clear = await renderWorld(
        image,
        const WorldSettings(weather: WorldWeather.clear, drift: 0),
        size,
      );
      for (final weather in WorldWeather.values) {
        final frame = await renderWorld(
          image,
          WorldSettings(weather: weather, intensity: 0, drift: 0),
          size,
        );
        expect(frame, orderedEquals(clear), reason: weather.name);
      }
    },
  );

  test(
    'weather animates deterministically and motion-off exports are still',
    () async {
      for (final weather in WorldWeather.values.where(
        (w) => w != WorldWeather.clear,
      )) {
        final settings = WorldSettings(
          weather: weather,
          intensity: .85,
          drift: 0,
        );
        final first = await renderWorld(image, settings, size);
        final later = await renderWorld(image, settings, size, time: 3);
        final repeat = await renderWorld(image, settings, size, time: 3);
        expect(later, isNot(orderedEquals(first)), reason: weather.name);
        expect(later, orderedEquals(repeat), reason: weather.name);
        final frozen = await renderWorld(
          image,
          settings.copyWith(motion: false),
          size,
          time: 3,
        );
        expect(frozen, orderedEquals(first), reason: weather.name);
      }
    },
  );

  test('weather renders at export size, thumbnails and high density', () async {
    for (final weather in WorldWeather.values) {
      final frame = await renderWorld(
        image,
        WorldSettings(weather: weather, intensity: 1),
        const ui.Size(120, 240),
      );
      expect(frame, isNotEmpty);
    }
    final frame = await renderWorld(
      image,
      const WorldSettings(weather: WorldWeather.clouds),
      exportSize(size),
    );
    final codec = await ui.instantiateImageCodec(frame);
    final result = (await codec.getNextFrame()).image;
    expect(result.height, 2304);
    expect(result.width, 1152);
    result.dispose();
    codec.dispose();
  });

  // Optional review artifacts, excluded from normal test runs and source control.
  final previewDirectory = Platform.environment['WEATHER_PREVIEW_DIR'];
  if (previewDirectory != null) {
    test('render review frames', () async {
      await Directory(previewDirectory).create(recursive: true);
      for (final weather in [
        WorldWeather.rain,
        WorldWeather.clouds,
        WorldWeather.snow,
      ]) {
        for (var frame = 0; frame < 24; frame++) {
          final bytes = await renderWorld(
            image,
            WorldSettings(weather: weather, intensity: .85),
            size,
            time: frame / 12,
          );
          await File(
            '$previewDirectory/${weather.name}_$frame.png',
          ).writeAsBytes(bytes);
        }
      }
    });
  }
}
