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
      case "setWallpaper":
        // iOS does not allow apps to set the wallpaper programmatically.
        result(FlutterError(code: "NOT_SUPPORTED",
                            message: "Setting wallpaper is not supported on iOS",
                            details: nil))
      case "setLiveWallpaper":
        result(FlutterError(code: "NOT_IMPLEMENTED",
                            message: "Live wallpaper coming soon",
                            details: nil))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
