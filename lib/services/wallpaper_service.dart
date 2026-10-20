import 'dart:async' show unawaited;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/wallpaper.dart';

/// Which screen an image wallpaper is applied to.
enum WallpaperTarget { home, lock, both }

/// Downloads wallpapers and hands them to the native side, which decodes them
/// at screen size off the UI thread.
class WallpaperService {
  WallpaperService._();
  static final WallpaperService instance = WallpaperService._();

  static const _channel = MethodChannel('wallpaper.channel/setter');

  // receiveTimeout is the longest silence between chunks, not a cap on the
  // whole transfer, so a slow 4K download still finishes.
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<void> setImageWallpaper(
    Wallpaper wallpaper, {
    required WallpaperTarget target,
    void Function(double)? onProgress,
  }) async {
    final path = await _downloadToTemp(wallpaper.fullUrl, onProgress);
    try {
      await _channel.invokeMethod<bool>('setWallpaper', {
        'path': path,
        'screen': target.name,
      });
    } finally {
      unawaited(_deleteQuietly(path));
    }
  }

  /// Asks for gallery access before the download, so a refusal costs no data.
  Future<void> downloadToGallery(
    Wallpaper wallpaper, {
    void Function(double)? onProgress,
  }) async {
    await _ensureGalleryAccess();
    final path = await _downloadToTemp(wallpaper.fullUrl, onProgress);
    try {
      await _saveToGallery(path);
    } finally {
      unawaited(_deleteQuietly(path));
    }
  }

  /// Saves an image file to the gallery (Android) or Photos (iOS).
  Future<void> saveFileToGallery(String path) async {
    await _ensureGalleryAccess();
    await _saveToGallery(path);
  }

  /// Android only. The video goes to permanent storage, because the live
  /// wallpaper service keeps reading it after the preview closes.
  Future<void> setLiveWallpaper(
    Wallpaper wallpaper, {
    void Function(double)? onProgress,
  }) async {
    final videoUrl = wallpaper.videoUrl;
    if (videoUrl == null) {
      throw PlatformException(code: 'ARG_ERROR', message: 'no video url');
    }
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/live_${wallpaper.id.replaceAll('/', '_')}.mp4';
    await _download(videoUrl, path, onProgress);
    await _channel.invokeMethod<bool>('setLiveWallpaper', {'path': path});
  }

  /// Byte size of [url] from a HEAD request, or null when it is unknown.
  Future<int?> fileSize(String url) async {
    try {
      final response = await _dio.head<void>(url);
      final length = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      return length != null && length > 0 ? length : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes `wall_*` downloads left behind by earlier runs.
  Future<void> cleanTemp() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('wall_')) {
          await _deleteQuietly(e.path);
        }
      }
    } catch (_) {}
  }

  // Android 9 and older can write to shared storage only with the storage
  // permission. iOS asks for Photos access natively.
  Future<void> _ensureGalleryAccess() async {
    if (!Platform.isAndroid) return;
    final needed =
        await _channel.invokeMethod<bool>('needsGalleryPermission') ?? false;
    if (needed && !await Permission.storage.request().isGranted) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Storage permission denied',
      );
    }
  }

  Future<void> _saveToGallery(String path) async {
    final saved = await _channel.invokeMethod<bool>('saveImageToGallery', {
      'path': path,
    });
    if (saved != true) throw StateError('The image was not saved.');
  }

  Future<String> _downloadToTemp(
    String url,
    void Function(double)? onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/wall_$stamp${_extension(url)}';
    await _download(url, path, onProgress);
    return path;
  }

  Future<void> _download(
    String url,
    String path,
    void Function(double)? onProgress,
  ) async {
    await _dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
  }

  // The real extension (catalog images are `.webp`): Android picks the
  // gallery MIME type from it.
  static String _extension(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    return ext.length <= 5 ? ext : '.jpg';
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
