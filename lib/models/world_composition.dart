import 'package:flutter/foundation.dart';

enum WorldWeather { clear, rain, fog, clouds, snow }

enum WorldWeatherView { openAir, window }

enum WorldPalette { original, blue, lavender, amber }

/// A portable scene recipe. The native wallpaper consumes the same schema.
@immutable
class WorldSettings {
  const WorldSettings({
    this.weather = WorldWeather.rain,
    this.weatherView = WorldWeatherView.openAir,
    this.palette = WorldPalette.lavender,
    this.intensity = .62,
    this.glow = .55,
    this.speed = .35,
    this.drift = .4,
    this.zoom = 1.055,
    this.focalX = .5,
    this.focalY = .5,
    this.motion = true,
  });

  final WorldWeather weather;
  final WorldWeatherView weatherView;
  bool get hasGlass =>
      weatherView == WorldWeatherView.window &&
      (weather == WorldWeather.rain || weather == WorldWeather.snow);
  final WorldPalette palette;
  final double intensity, glow, speed, drift, zoom, focalX, focalY;
  final bool motion;

  WorldSettings copyWith({
    WorldWeather? weather,
    WorldWeatherView? weatherView,
    WorldPalette? palette,
    double? intensity,
    double? glow,
    double? speed,
    double? drift,
    double? zoom,
    double? focalX,
    double? focalY,
    bool? motion,
  }) => WorldSettings(
    weather: weather ?? this.weather,
    weatherView: weatherView ?? this.weatherView,
    palette: palette ?? this.palette,
    intensity: intensity ?? this.intensity,
    glow: glow ?? this.glow,
    speed: speed ?? this.speed,
    drift: drift ?? this.drift,
    zoom: zoom ?? this.zoom,
    focalX: focalX ?? this.focalX,
    focalY: focalY ?? this.focalY,
    motion: motion ?? this.motion,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'weather': weather.name,
    'weatherView': weatherView.name,
    'palette': palette.name,
    'intensity': intensity,
    'glow': glow,
    'speed': speed,
    'drift': drift,
    'zoom': zoom,
    'focalX': focalX,
    'focalY': focalY,
    'motion': motion,
  };

  factory WorldSettings.fromJson(Map<String, dynamic> json) {
    double number(
      String key,
      double fallback, [
      double min = 0,
      double max = 1,
    ]) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return WorldSettings(
      weather:
          WorldWeather.values
              .where((v) => v.name == json['weather'])
              .firstOrNull ??
          WorldWeather.rain,
      weatherView:
          WorldWeatherView.values
              .where((v) => v.name == json['weatherView'])
              .firstOrNull ??
          WorldWeatherView.openAir,
      palette:
          WorldPalette.values
              .where((v) => v.name == json['palette'])
              .firstOrNull ??
          WorldPalette.lavender,
      intensity: number('intensity', .62),
      glow: number('glow', .55),
      speed: number('speed', .35),
      drift: number('drift', .4),
      zoom: number('zoom', 1.055, 1.04, 1.6),
      focalX: number('focalX', .5),
      focalY: number('focalY', .5),
      motion: json['motion'] is bool ? json['motion'] as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorldSettings &&
      weather == other.weather &&
      weatherView == other.weatherView &&
      palette == other.palette &&
      intensity == other.intensity &&
      glow == other.glow &&
      speed == other.speed &&
      drift == other.drift &&
      zoom == other.zoom &&
      focalX == other.focalX &&
      focalY == other.focalY &&
      motion == other.motion;
  @override
  int get hashCode => Object.hash(
    weather,
    weatherView,
    palette,
    intensity,
    glow,
    speed,
    drift,
    zoom,
    focalX,
    focalY,
    motion,
  );
}

@immutable
class WorldComposition {
  const WorldComposition({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.isAsset,
    this.settings = const WorldSettings(),
  });

  static const midnight = WorldComposition(
    id: 'midnight-express',
    title: 'Midnight Express',
    imagePath: 'assets/worlds/midnight_express.jpg',
    isAsset: true,
  );
  final String id, title, imagePath;
  final bool isAsset;
  final WorldSettings settings;

  WorldComposition copyWith({
    String? id,
    String? title,
    String? imagePath,
    bool? isAsset,
    WorldSettings? settings,
  }) => WorldComposition(
    id: id ?? this.id,
    title: title ?? this.title,
    imagePath: imagePath ?? this.imagePath,
    isAsset: isAsset ?? this.isAsset,
    settings: settings ?? this.settings,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'imagePath': imagePath,
    'isAsset': isAsset,
    'settings': settings.toJson(),
  };

  factory WorldComposition.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['title'] is! String ||
        json['imagePath'] is! String ||
        json['isAsset'] is! bool ||
        json['settings'] is! Map) {
      throw const FormatException('Invalid world');
    }
    return WorldComposition(
      id: json['id'],
      title: json['title'],
      imagePath: json['imagePath'],
      isAsset: json['isAsset'],
      settings: WorldSettings.fromJson(
        Map<String, dynamic>.from(json['settings']),
      ),
    );
  }
}
