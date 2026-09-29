import AVFoundation
import Accelerate
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Assembles a Live Photo from frames the Dart side pushes one at a time,
/// then saves it to Photos.
///
/// iOS has no way for an app to set a wallpaper, live or still. What it does
/// have is Live Photos: a JPEG and a short MOV that share an asset
/// identifier — the JPEG carries it in its Apple maker note, the MOV in a
/// `content.identifier` metadata item plus a timed `still-image-time` track
/// that says where in the clip the still sits. Photos pairs the two on
/// import, and from there the user can pick it as a Lock Screen wallpaper;
/// iOS 17+ plays the motion on wake. This is the same recipe the Live Photo
/// converter apps use.
///
/// Frames arrive as raw RGBA; the still arrives last, as PNG, and is
/// re-encoded to JPEG here with the identifier attached. Both are the same
/// size, and the still is marked at [stillFrame] — the middle of the clip,
/// where the Camera puts it. iOS 17+ decides by unpublished rules whether a
/// Live Photo may move on the Lock Screen; staying close to what the Camera
/// produces is the only lever there is.
final class LivePhotoWriter {
  enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? {
      if case .message(let text) = self { return text }
      return nil
    }
  }

  private let identifier = UUID().uuidString
  private let width: Int
  private let height: Int
  private let fps: Int32
  private let movURL: URL
  private let jpegURL: URL
  private let writer: AVAssetWriter
  private let video: AVAssetWriterInput
  private let pixels: AVAssetWriterInputPixelBufferAdaptor
  private let metadata: AVAssetWriterInput
  private let timed: AVAssetWriterInputMetadataAdaptor
  private let queue = DispatchQueue(label: "wavely.livephoto")
  private let stillFrame: Int64
  private var frames: Int64 = 0
  private let cancellationLock = NSLock()
  private var cancelled = false
  private var finishingEncoding = false

  private var isCancelled: Bool {
    cancellationLock.lock()
    defer { cancellationLock.unlock() }
    return cancelled
  }

  init(width: Int, height: Int, fps: Int, stillFrame: Int) throws {
    // H.264 wants even dimensions; the Dart side sends them even, but a
    // silent failure deep in the encoder is worse than a check here.
    guard (2...2304).contains(width), (2...2304).contains(height),
          width % 2 == 0, height % 2 == 0, (1...60).contains(fps) else {
      throw Failure.message("Invalid video size")
    }
    self.width = width
    self.height = height
    self.fps = Int32(fps)
    self.stillFrame = Int64(max(0, stillFrame))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("livephoto-\(identifier)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var started = false
    defer {
      if !started { try? FileManager.default.removeItem(at: directory) }
    }
    movURL = directory.appendingPathComponent("world.mov")
    jpegURL = directory.appendingPathComponent("world.jpg")

    writer = try AVAssetWriter(outputURL: movURL, fileType: .mov)
    let content = AVMutableMetadataItem()
    content.key = "com.apple.quicktime.content.identifier" as NSString
    content.keySpace = .quickTimeMetadata
    content.value = identifier as NSString
    content.dataType = "com.apple.metadata.datatype.UTF-8"
    writer.metadata = [content]

    video = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        // Generous: two seconds of rain over a photo is cheap to store,
        // and banding in the fog is exactly what a low rate would show.
        AVVideoAverageBitRateKey: width * height * 6,
        AVVideoExpectedSourceFrameRateKey: fps,
      ],
    ])
    video.expectsMediaDataInRealTime = false
    pixels = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: video,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])

    // The timed track that marks the still's position in the clip.
    let spec: [String: Any] = [
      kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
        "mdta/com.apple.quicktime.still-image-time",
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
        "com.apple.metadata.datatype.int8",
    ]
    var description: CMFormatDescription?
    let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
      allocator: kCFAllocatorDefault,
      metadataType: kCMMetadataFormatType_Boxed,
      metadataSpecifications: [spec] as CFArray,
      formatDescriptionOut: &description)
    guard status == noErr, let description else {
      throw Failure.message("Could not describe the Live Photo metadata track")
    }
    metadata = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil,
                                  sourceFormatHint: description)
    timed = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)

    guard writer.canAdd(video), writer.canAdd(metadata) else {
      throw Failure.message("This video format is unavailable")
    }
    writer.add(video)
    writer.add(metadata)
    guard writer.startWriting() else {
      throw writer.error ?? Failure.message("Could not start the video")
    }
    writer.startSession(atSourceTime: .zero)
    started = true
  }

  /// Appends one frame of raw RGBA, `width * height * 4` bytes.
  func append(rgba: Data, completion: @escaping (Error?) -> Void) {
    queue.async {
      do {
        try autoreleasepool { try self.appendNow(rgba: rgba) }
        completion(nil)
      } catch {
        self.stopAndCleanUp()
        completion(error)
      }
    }
  }

  private func appendNow(rgba: Data) throws {
    try waitUntilReady(video)
    guard rgba.count == width * height * 4 else {
      throw Failure.message("Frame is \(rgba.count) bytes, expected \(width * height * 4)")
    }
    guard let pool = pixels.pixelBufferPool else {
      throw writer.error ?? Failure.message("Video writer is not ready")
    }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let buffer
    else { throw Failure.message("Could not allocate a frame") }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw Failure.message("Frame has no storage")
    }
    // Flutter hands over RGBA; the encoder takes BGRA. One channel permute
    // per frame, in Accelerate, is far cheaper than doing it in Dart.
    try rgba.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let source = raw.baseAddress else { throw Failure.message("Empty frame") }
      var input = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: source),
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: width * 4)
      var output = vImage_Buffer(
        data: base,
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: CVPixelBufferGetBytesPerRow(buffer))
      let map: [UInt8] = [2, 1, 0, 3]
      let result = vImagePermuteChannels_ARGB8888(&input, &output, map, vImage_Flags(kvImageNoFlags))
      guard result == kvImageNoError else {
        throw Failure.message("Could not convert a frame (\(result))")
      }
    }

    guard pixels.append(buffer, withPresentationTime: CMTime(value: frames, timescale: fps)) else {
      throw writer.error ?? Failure.message("Could not append a frame")
    }
    frames += 1
  }

  /// Bound encoder back-pressure and let cancellation interrupt a stalled
  /// frame. Waiting happens before allocating/converting its pixel buffer.
  private func waitUntilReady(_ input: AVAssetWriterInput) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 15
    while true {
      guard !isCancelled, writer.status == .writing else {
        throw writer.error ?? Failure.message("Video writer stopped")
      }
      if input.isReadyForMoreMediaData { return }
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw Failure.message("Video encoder timed out. Please try again.")
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
  }

  /// Closes the clip, writes the still with the shared identifier, and
  /// saves the pair to Photos. [still] is PNG at wallpaper resolution.
  func finish(still: Data, completion: @escaping (Error?) -> Void) {
    queue.async {
      guard self.frames > 0 else {
        self.stopAndCleanUp()
        completion(Failure.message("No frames were rendered"))
        return
      }
      let stillTime = CMTime(value: min(self.stillFrame, self.frames - 1), timescale: self.fps)
      let item = AVMutableMetadataItem()
      item.key = "com.apple.quicktime.still-image-time" as NSString
      item.keySpace = .quickTimeMetadata
      item.value = 0 as NSNumber
      item.dataType = "com.apple.metadata.datatype.int8"
      let group = AVTimedMetadataGroup(
        items: [item],
        timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: self.fps)))
      self.video.markAsFinished()
      do {
        try self.waitUntilReady(self.metadata)
      } catch {
        self.stopAndCleanUp()
        completion(error)
        return
      }
      guard self.timed.append(group) else {
        self.stopAndCleanUp()
        completion(self.writer.error ?? Failure.message("Could not mark the still"))
        return
      }
      self.metadata.markAsFinished()
      self.finishingEncoding = true
      self.queue.asyncAfter(deadline: .now() + 30) { [weak self] in
        guard let self, self.finishingEncoding else { return }
        self.finishingEncoding = false
        self.stopAndCleanUp()
        completion(Failure.message("Video encoder timed out. Please try again."))
      }
      self.writer.finishWriting {
        self.queue.async {
          guard self.finishingEncoding else { return }
          self.finishingEncoding = false
          guard !self.isCancelled, self.writer.status == .completed else {
            self.stopAndCleanUp()
            completion(self.writer.error ?? Failure.message("Could not finish the video"))
            return
          }
          do {
            try autoreleasepool { try self.writeStill(png: still) }
          } catch {
            self.cleanUp()
            completion(error)
            return
          }
          self.save(completion: completion)
        }
      }
    }
  }

  private func writeStill(png: Data) throws {
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let destination = CGImageDestinationCreateWithURL(
            jpegURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw Failure.message("Could not decode the still") }
    // Maker note tag 17 is where Photos looks for the identifier that pairs
    // a still with its clip.
    let properties: [CFString: Any] = [
      kCGImagePropertyMakerAppleDictionary: ["17": identifier],
      kCGImageDestinationLossyCompressionQuality: 0.95,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw Failure.message("Could not write the still")
    }
  }

  private func save(completion: @escaping (Error?) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        self.cleanUp()
        completion(Failure.message("PERMISSION_DENIED"))
        return
      }
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, fileURL: self.jpegURL, options: nil)
        request.addResource(with: .pairedVideo, fileURL: self.movURL, options: nil)
      }) { success, error in
        self.cleanUp()
        completion(success ? nil : (error ?? Failure.message("Photos did not save the Live Photo")))
      }
    }
  }

  /// Abandons the clip; the temp files go with it.
  func cancel() {
    cancellationLock.lock()
    cancelled = true
    cancellationLock.unlock()
    queue.async {
      self.stopAndCleanUp()
    }
  }

  private func stopAndCleanUp() {
    if writer.status == .writing { writer.cancelWriting() }
    cleanUp()
  }

  private func cleanUp() {
    try? FileManager.default.removeItem(at: movURL.deletingLastPathComponent())
  }
}
