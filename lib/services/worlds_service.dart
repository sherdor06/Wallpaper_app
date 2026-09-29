import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/world_composition.dart';
import '../ui/worlds/world_weather.dart';
import '../ui/worlds/world_scene.dart' show exportSize, renderWorld, worldClock;

/// Private, offline scene library. Imports are copied out of picker caches;
/// native wallpapers own another copy so deleting a draft cannot break one.
class WorldsService extends ChangeNotifier {
  WorldsService._();
  static final instance = WorldsService._();
  static const _channel = MethodChannel('wallpaper.channel/setter');
  final _picker = ImagePicker();
  final _random = math.Random.secure();
  List<WorldComposition> _saved = const [];
  bool _exportingLivePhoto = false;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  late Directory _directory;
  String? loadError;

  // Publish one immutable snapshot per write, not one copy per grid cell.
  List<WorldComposition> get saved => _saved;

  /// Android: the world can *be* the wallpaper, drawn by the native service.
  bool get supportsLiveWallpaper => Platform.isAndroid;

  /// iOS: no app may set a wallpaper, so the world is saved to Photos as a
  /// Live Photo instead and the user picks it as the Lock Screen there —
  /// see [saveLivePhoto].
  bool get supportsLivePhoto => Platform.isIOS;
  bool contains(String id) => _saved.any((w) => w.id == id);

  Future<void> init() => _initializing ??= _load();
  Future<void> _load() async {
    unawaited(_cleanExports());
    try {
      final support = await getApplicationSupportDirectory();
      _directory = await Directory(
        '${support.path}/worlds',
      ).create(recursive: true);
      final file = File('${_directory.path}/library.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is! Map || data['version'] != 1 || data['worlds'] is! List) {
          throw const FormatException('Unsupported world library');
        }
        _saved = List.unmodifiable(
          (data['worlds'] as List).map((j) {
            final world = WorldComposition.fromJson(
              Map<String, dynamic>.from(j),
            );
            // Resolve relative paths after an iOS app-container migration.
            if (world.isAsset) {
              if (world.imagePath != WorldComposition.midnight.imagePath) {
                throw const FormatException('Unknown scene asset');
              }
              return world;
            }
            final name = world.imagePath;
            if (!RegExp(r'^photo_[a-zA-Z0-9_]+\.png$').hasMatch(name)) {
              throw const FormatException('Invalid photo path');
            }
            return world.copyWith(imagePath: '${_directory.path}/$name');
          }),
        );
      }
      // The system may kill the activity while its photo picker is open.
      if (Platform.isAndroid) {
        final lost = await _picker.retrieveLostData();
        if (lost.files?.isNotEmpty ?? false) {
          final recovered = await _import(lost.files!.first);
          await _store([
            ..._saved,
            recovered.copyWith(title: 'Recovered world'),
          ]);
        }
      }
    } catch (_) {
      loadError =
          'Your worlds could not be loaded. Your saved files are still safe.';
    }
    notifyListeners();
  }

  Future<void> _cleanExports() async {
    try {
      final temporary = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      await for (final file in temporary.list()) {
        if (file is File &&
            RegExp(
              r'^world_\d+_\d+\.png$',
            ).hasMatch(file.uri.pathSegments.last) &&
            (await file.lastModified()).isBefore(cutoff)) {
          await file.delete();
        }
      }
    } catch (_) {
      // A stale share file must not block access to the user's library.
    }
  }

  Future<void> retryLoad() async {
    await _writes;
    loadError = null;
    _initializing = _load();
    await _initializing;
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 30)}';

  Future<WorldComposition?> pickPhoto() async {
    await init();
    if (loadError != null) throw StateError(loadError!);
    final selected = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2304,
      maxHeight: 2304,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    return selected == null ? null : _import(selected);
  }

  Future<WorldComposition> _import(XFile selected) async {
    if (await selected.length() > 40 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 40 MB.');
    }
    final image = await _decode(await selected.readAsBytes(), 2304);
    try {
      // Normalize orientation and format once, including HEIC picker results.
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const FormatException('This photo could not be opened.');
      }
      final id = _id();
      final file = File('${_directory.path}/photo_$id.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return WorldComposition(
        id: id,
        title: 'My world',
        imagePath: file.path,
        isAsset: false,
        settings: const WorldSettings(palette: WorldPalette.original),
      );
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image> loadImage(
    WorldComposition world, {
    int maxDimension = 2048,
  }) async {
    await WorldWeatherRenderer.prepare();
    final bytes = world.isAsset
        ? (await rootBundle.load(world.imagePath)).buffer.asUint8List()
        : await File(world.imagePath).readAsBytes();
    return _decode(bytes, maxDimension);
  }

  static Future<ui.Image> _decode(Uint8List bytes, int maxDimension) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        maxDimension / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<WorldComposition> save(
    WorldComposition world, {
    String? title,
    bool asCopy = false,
  }) async {
    await init();
    return _enqueue(() async {
      if (loadError != null) throw StateError(loadError!);
      final name = (title ?? world.title).trim();
      final value = world.copyWith(
        id: asCopy || world.isAsset && !contains(world.id) ? _id() : world.id,
        title: name.isEmpty
            ? 'My world'
            : name.substring(0, math.min(80, name.length)),
      );
      await _store([value, ..._saved.where((w) => w.id != value.id)]);
      return value;
    });
  }

  Future<void> _store(List<WorldComposition> next) async {
    final data = {
      'version': 1,
      'worlds': next
          .map(
            (w) =>
                (w.isAsset
                        ? w
                        : w.copyWith(imagePath: w.imagePath.split('/').last))
                    .toJson(),
          )
          .toList(),
    };
    final temp = File('${_directory.path}/library.json.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename('${_directory.path}/library.json');
    _saved = List.unmodifiable(next);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await init();
    await _enqueue(() async {
      if (loadError != null) throw StateError(loadError!);
      final world = _saved.where((w) => w.id == id).firstOrNull;
      await _store(_saved.where((w) => w.id != id).toList());
      if (world != null) await discardDraft(world);
    });
  }

  Future<void> discardDraft(WorldComposition world) async {
    if (world.isAsset || _saved.any((w) => w.imagePath == world.imagePath)) {
      return;
    }
    try {
      await File(world.imagePath).delete();
    } catch (_) {}
  }

  Future<File> imageFile(WorldComposition world) async {
    await init();
    if (!world.isAsset) return File(world.imagePath);
    final file = File('${_directory.path}/midnight_express.jpg');
    if (!await file.exists()) {
      final bytes = await rootBundle.load(world.imagePath);
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    return file;
  }

  Future<bool> applyLive(WorldComposition world) async {
    final file = await imageFile(world);
    return await _channel.invokeMethod<bool>('setWorldWallpaper', {
          'path': file.path,
          'settings': world.settings.toJson(),
        }) ??
        false;
  }

  /// A short clip with matching still/video dimensions. Photos accepting
  /// the pair does not guarantee Lock Screen motion on every iOS version.
  static const livePhotoFps = 30;
  static const livePhotoSeconds = 2.0;

  /// Renders the world and saves it to Photos as a Live Photo: a clip plus
  /// a still on its middle frame, paired natively. Frames stream to the
  /// native writer one at a time — raw RGBA, so nothing is encoded twice —
  /// and [onProgress] runs 0→1 as they go. Throws a [PlatformException]
  /// with code `PERMISSION_DENIED` when Photos access was refused.
  Future<void> saveLivePhoto(
    ui.Image image,
    WorldSettings settings,
    Size screen, {
    void Function(double)? onProgress,
  }) async {
    if (_exportingLivePhoto) {
      throw StateError('A Live Photo export is already in progress.');
    }
    _exportingLivePhoto = true;
    const fps = livePhotoFps;
    final frames = (livePhotoSeconds * fps).round();
    final size = exportSize(screen);
    try {
      await _channel.invokeMethod<bool>('livePhotoBegin', {
        'width': size.width.round(),
        'height': size.height.round(),
        'fps': fps,
        'stillFrame': frames ~/ 2,
      });
      for (var i = 0; i < frames; i++) {
        final frame = await renderWorld(
          image,
          settings,
          size,
          time: worldClock(i / fps, settings),
          format: ui.ImageByteFormat.rawRgba,
        );
        await _channel.invokeMethod<bool>('livePhotoFrame', frame);
        onProgress?.call((i + 1) / frames);
      }
      // The still is the middle frame, so the picture sits where the
      // Camera's own Live Photos keep it.
      final photo = await renderWorld(
        image,
        settings,
        size,
        time: worldClock((frames ~/ 2) / fps, settings),
      );
      await _channel.invokeMethod<bool>('livePhotoFinish', photo);
    } catch (_) {
      try {
        await _channel.invokeMethod<bool>('livePhotoCancel');
      } catch (_) {
        // Preserve the render/Photos error if native cleanup also failed.
      }
      rethrow;
    } finally {
      _exportingLivePhoto = false;
    }
  }

  Future<File> writeExport(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    return File(
      '${directory.path}/world_${_id()}.png',
    ).writeAsBytes(bytes, flush: true);
  }

  Future<void> saveStill(Uint8List bytes) async {
    if (Platform.isAndroid &&
        (await _channel.invokeMethod<bool>('needsGalleryPermission') ??
            false)) {
      if (!await Permission.storage.request().isGranted) {
        throw PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'Allow photo access in Settings to save this wallpaper.',
        );
      }
    }
    final file = await writeExport(bytes);
    try {
      final saved = await _channel.invokeMethod<bool>('saveImageToGallery', {
        'path': file.path,
      });
      if (saved != true) throw StateError('The image was not saved.');
    } finally {
      await file.delete();
    }
  }
}
