import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_app_first/models/wallpaper.dart';

void main() {
  group('Wallpaper.fromJson', () {
    test('key + convention: URLs are built from base and key', () {
      final w = Wallpaper.fromJson(
        {
          'key': 'nature/001',
          'title': 'Misty',
          'category': 'nature',
          'type': 'image',
          'resolution': '4K',
        },
        base: 'https://cdn.test',
      );

      expect(w.id, 'nature/001');
      expect(w.thumbUrl, 'https://cdn.test/nature/001_thumb.webp');
      expect(w.fullUrl, 'https://cdn.test/nature/001_full.webp');
      expect(w.videoUrl, isNull); // image type has no video
      expect(w.type, WallpaperType.image);
    });

    test('live type: video URL is built with .mp4', () {
      final w = Wallpaper.fromJson(
        {'key': 'live/001', 'type': 'live', 'category': 'live'},
        base: 'https://cdn.test',
      );

      expect(w.isLive, isTrue);
      expect(w.videoUrl, 'https://cdn.test/live/001.mp4');
    });

    test('explicit URLs override the key convention', () {
      final w = Wallpaper.fromJson(
        {
          'key': 'x',
          'thumb': 'https://picsum.photos/id/1/360/640',
          'full': 'https://picsum.photos/id/1/1080/1920',
          'type': 'image',
        },
        base: 'https://cdn.test',
      );

      expect(w.thumbUrl, 'https://picsum.photos/id/1/360/640');
      expect(w.fullUrl, 'https://picsum.photos/id/1/1080/1920');
    });
  });
}
