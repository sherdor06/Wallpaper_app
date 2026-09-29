import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Native side of the app's wallpaper channel (matches MainActivity.kt on Android).
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WallpaperChannel")
    else { return }
    let channel = FlutterMethodChannel(
      name: "wallpaper.channel/setter",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveImageToGallery":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              FileManager.default.fileExists(atPath: path)
        else {
          result(FlutterError(code: "ARG_ERROR", message: "invalid path", details: nil))
          return
        }
        Self.saveToPhotos(filePath: path, result: result)
      case "isEmulator":
        // Debug-only convenience for the Dart side: the banner is hidden on
        // the simulator so screens can be looked at without an ad strip.
        // Compile-time, so a device build answers false without a lookup.
        #if targetEnvironment(simulator)
        result(true)
        #else
        result(false)
        #endif
      case "setWallpaper":
        // iOS does not allow apps to set the wallpaper programmatically.
        result(FlutterError(code: "NOT_SUPPORTED",
                            message: "Setting wallpaper is not supported on iOS",
                            details: nil))
      case "setLiveWallpaper":
        result(FlutterError(code: "NOT_IMPLEMENTED",
                            message: "Live wallpaper coming soon",
                            details: nil))
      // Live Photo export for Wavely Worlds — see LivePhotoWriter. The Dart
      // side renders the frames and streams them here one call at a time.
      case "livePhotoBegin":
        guard let args = call.arguments as? [String: Any],
              let width = args["width"] as? Int,
              let height = args["height"] as? Int,
              let fps = args["fps"] as? Int,
              let stillFrame = args["stillFrame"] as? Int
        else {
          result(FlutterError(code: "ARG_ERROR", message: "invalid video size", details: nil))
          return
        }
        // Ask before rendering dozens of full-size frames. A denied Photos
        // request should return immediately without starting the encoder.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          DispatchQueue.main.async {
            guard status == .authorized || status == .limited else {
              result(FlutterError(code: "PERMISSION_DENIED", message: "Photos permission denied", details: nil))
              return
            }
            self.livePhoto?.cancel()
            self.livePhoto = nil
            do {
              self.livePhoto = try LivePhotoWriter(width: width, height: height, fps: fps,
                                                   stillFrame: stillFrame)
              result(true)
            } catch {
              result(FlutterError(code: "LIVE_PHOTO_FAIL", message: error.localizedDescription, details: nil))
            }
          }
        }
      case "livePhotoFrame":
        guard let writer = self.livePhoto, let frame = call.arguments as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "ARG_ERROR", message: "no live photo in progress", details: nil))
          return
        }
        writer.append(rgba: frame.data) { error in
          DispatchQueue.main.async { Self.reply(result, error: error) }
        }
      case "livePhotoFinish":
        guard let writer = self.livePhoto, let still = call.arguments as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "ARG_ERROR", message: "no live photo in progress", details: nil))
          return
        }
        self.livePhoto = nil
        writer.finish(still: still.data) { error in
          DispatchQueue.main.async { Self.reply(result, error: error) }
        }
      case "livePhotoCancel":
        self.livePhoto?.cancel()
        self.livePhoto = nil
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The Live Photo being assembled, if any. One at a time: a second export
  /// cancels the first.
  private var livePhoto: LivePhotoWriter?

  /// Turns a writer callback into a channel reply. The writer signals a
  /// Photos permission refusal by message so the Dart side can tell it apart
  /// from a render failure and point at Settings.
  private static func reply(_ result: @escaping FlutterResult, error: Error?) {
    guard let error else {
      result(true)
      return
    }
    let message = error.localizedDescription
    result(FlutterError(code: message == "PERMISSION_DENIED" ? "PERMISSION_DENIED" : "LIVE_PHOTO_FAIL",
                        message: message, details: nil))
  }

  /// Saves the image file to the user's photo library (asks for add-only permission).
  ///
  /// The catalog serves WebP, which PhotoKit rejects with PHPhotosError 3302 — even
  /// via `creationRequestForAsset(from:)`. So we decode the file into a UIImage
  /// (`UIImage(contentsOfFile:)` uses ImageIO, which sniffs the real format from the
  /// bytes and decodes WebP on iOS 14+), then re-encode it to explicit JPEG data and
  /// add that resource. That guarantees Photos always receives a supported format.
  private static func saveToPhotos(filePath: String, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "PERMISSION_DENIED",
                              message: "Photos permission denied",
                              details: nil))
        }
        return
      }
      guard let image = UIImage(contentsOfFile: filePath) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "DECODE_FAIL",
                              message: "Could not decode image file",
                              details: nil))
        }
        return
      }
      // Re-encode to JPEG so Photos always receives a format it supports. The
      // catalog serves WebP, which PhotoKit rejects with PHPhotosError 3302 — even
      // via creationRequestForAsset(from:). Explicit JPEG data avoids that entirely.
      guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "ENCODE_FAIL",
                              message: "Could not encode image",
                              details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: jpeg, options: nil)
      }) { success, error in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(FlutterError(code: "SAVE_FAIL",
                                message: error?.localizedDescription ?? "unknown error",
                                details: nil))
          }
        }
      }
    }
  }
}
