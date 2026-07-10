import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wallpaper.dart';

/// Which screen the wallpaper is applied to.
enum WallpaperTarget {
  home('home'),
  lock('lock'),
  both('both');

  const WallpaperTarget(this.value);
  final String value;
}

/// Handles downloading the image and applying the wallpaper on the native side.
///
/// Optimization: the native side (MainActivity.kt) downsamples the bitmap to the
/// screen size and applies it on a background thread — so even a 4K image won't
/// cause an OOM and the UI won't freeze.
class WallpaperService {
  WallpaperService._();
  static final WallpaperService instance = WallpaperService._();

  static const MethodChannel _channel = MethodChannel('wallpaper.channel/setter');
  final Dio _dio = Dio();

  /// Downloads [url] to a temporary file. [onProgress] reports a 0.0..1.0 value.
  Future<String> _download(String url, {void Function(double)? onProgress}) async {
    final dir = await getTemporaryDirectory();
    // Keep the real extension (catalog images are `.webp`). Native decoders sniff
    // the bytes regardless, but an honest extension avoids format-mismatch bugs.
    final ext = _extFromUrl(url);
    final filePath =
        '${dir.path}/wall_${DateTime.now().millisecondsSinceEpoch}$ext';
    await _dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    return filePath;
  }

  /// Extracts a lowercase file extension (incl. the dot) from [url]'s path,
  /// falling back to `.jpg`. Query strings and odd paths are handled safely.
  static String _extFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    return ext.length <= 5 ? ext : '.jpg';
  }

  /// Downloads a regular (image) wallpaper and applies it to the chosen screen.
  Future<void> setImageWallpaper(
    Wallpaper wallpaper, {
    required WallpaperTarget target,
    void Function(double)? onProgress,
  }) async {
    final path = await _download(wallpaper.fullUrl, onProgress: onProgress);
    try {
      await _channel.invokeMethod<bool>('setWallpaper', {
        'path': path,
        'screen': target.value,
      });
    } finally {
      _deleteQuietly(path); // don't let temp downloads pile up
    }
  }

  /// Downloads the full-size image and saves it to the device gallery
  /// (Pictures/Wallpapers) via the native MediaStore handler.
  Future<void> downloadToGallery(
    Wallpaper wallpaper, {
    void Function(double)? onProgress,
  }) async {
    final path = await _download(wallpaper.fullUrl, onProgress: onProgress);
    try {
      await _channel.invokeMethod<bool>('saveImageToGallery', {'path': path});
    } finally {
      _deleteQuietly(path);
    }
  }

  /// Applies a live (video) wallpaper (Android).
  ///
  /// Downloads the video to permanent app storage (the live wallpaper service
  /// keeps reading it), then opens the system live-wallpaper preview where the
  /// user confirms. On iOS the native side returns NOT_IMPLEMENTED.
  Future<void> setLiveWallpaper(
    Wallpaper wallpaper, {
    void Function(double)? onProgress,
  }) async {
    final videoUrl = wallpaper.videoUrl;
    if (videoUrl == null) {
      throw PlatformException(code: 'ARG_ERROR', message: 'no video url');
    }
    // Permanent location — temp files could be purged while the wallpaper is set.
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/live_${wallpaper.id.replaceAll('/', '_')}.mp4';
    await _dio.download(
      videoUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    await _channel.invokeMethod<bool>('setLiveWallpaper', {'path': path});
  }

  /// Deletes a temp download file, ignoring errors.
  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Removes leftover temp download files (`wall_*`) from earlier runs, so the
  /// temp directory doesn't grow unbounded. Fire-and-forget at startup.
  Future<void> cleanTemp() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('wall_')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
