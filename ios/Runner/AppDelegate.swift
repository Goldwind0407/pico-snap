import AVFoundation
import CoreVideo
import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // iOS 27 起沒採用 UIScene 的 App 一打開就被系統終止,所以外掛和通道
  // 都要等 FlutterSceneDelegate 建好引擎、這裡被呼叫時才註冊。
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    SubjectSegmenter.register(messenger: engineBridge.applicationRegistrar.messenger())
    VideoEncoder.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

// 寫在這個檔案裡,不另開新檔:新的 .swift 要加進 Xcode 專案檔才會編譯。
/// 去背的第一步:用系統內建的 Vision 找出照片裡的前景(免費、離線、App 不會變大)。
///
/// - iOS 17 以上:主體去背(相簿裡長按把主體拎起來的那個),人、動物、物品都行。
/// - iOS 15、16:人像分割,只切得出人。
///
/// Dart 那邊(lib/cutout/subject_segmenter.dart)送來 RGBA 像素,這裡回傳每個
/// 像素是前景的信心(0~255,寬×高);沒有前景或出錯回 nil,Dart 那邊就退回原本的
/// GrabCut。模擬器上 Vision 的主體去背不能用,要用實機測。
enum SubjectSegmenter {
  /// 通道要留著(放在 static),不然離開這個函式就被釋放,Dart 那邊叫不到。
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "picosnap/subject", binaryMessenger: messenger)
    Self.channel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "foreground" || call.method == "subjects",
        let args = call.arguments as? [String: Any],
        let rgba = args["rgba"] as? FlutterStandardTypedData,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        if call.method == "subjects" {
          // 每個主體一張和照片一樣大的遮罩(Dart 那邊當作 x=0,y=0 的整張框)
          let masks = subjects(rgba: data(rgba), width: width, height: height)
          DispatchQueue.main.async {
            result(masks.map { list in
              list.map { m -> [String: Any] in
                ["x": 0, "y": 0, "w": width, "h": height, "mask": FlutterStandardTypedData(bytes: m)]
              }
            })
          }
          return
        }
        let mask = foreground(rgba: rgba.data, width: width, height: height)
        DispatchQueue.main.async {
          result(mask.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
  }

  static func data(_ d: FlutterStandardTypedData) -> Data { d.data }

  static func cgImage(rgba: Data, width: Int, height: Int) -> CGImage? {
    guard rgba.count == width * height * 4,
      let provider = CGDataProvider(data: rgba as CFData)
    else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false,
      intent: .defaultIntent)
  }

  /// 每個主體分開的遮罩。iOS 17 以上用主體去背的每個實例;iOS 15、16 只有
  /// 人像分割,整個前景當成一個主體。拿不到回 nil。
  static func subjects(rgba: Data, width: Int, height: Int) -> [Data]? {
    guard let image = cgImage(rgba: rgba, width: width, height: height) else { return nil }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      if #available(iOS 17.0, *) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { return [] }
        var out: [Data] = []
        for instance in observation.allInstances {
          let buffer = try observation.generateScaledMaskForImage(
            forInstances: IndexSet(integer: instance), from: handler)
          if let m = resample(buffer, width: width, height: height) { out.append(m) }
        }
        return out
      } else {
        guard let m = foreground(rgba: rgba, width: width, height: height) else { return [] }
        return [m]
      }
    } catch {
      return nil
    }
  }

  static func foreground(rgba: Data, width: Int, height: Int) -> Data? {
    guard rgba.count == width * height * 4,
      let provider = CGDataProvider(data: rgba as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent)
    else { return nil }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      if #available(iOS 17.0, *) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first,
          !observation.allInstances.isEmpty
        else { return nil }
        let buffer = try observation.generateScaledMaskForImage(
          forInstances: observation.allInstances, from: handler)
        return resample(buffer, width: width, height: height)
      } else {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        return resample(buffer, width: width, height: height)
      }
    } catch {
      return nil
    }
  }

  /// 遮罩(8 位元或 32 位元浮點,大小可能跟照片不一樣)雙線性取樣成照片大小的 0~255。
  static func resample(_ buffer: CVPixelBuffer, width: Int, height: Int) -> Data? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let bw = CVPixelBufferGetWidth(buffer)
    let bh = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let format = CVPixelBufferGetPixelFormatType(buffer)
    let isFloat = format == kCVPixelFormatType_OneComponent32Float
    guard isFloat || format == kCVPixelFormatType_OneComponent8 else { return nil }

    func at(_ x: Int, _ y: Int) -> Float {
      let p = base.advanced(by: y * row)
      return isFloat
        ? p.assumingMemoryBound(to: Float.self)[x]
        : Float(p.assumingMemoryBound(to: UInt8.self)[x]) / 255
    }

    var out = Data(count: width * height)
    out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
      let o = dst.bindMemory(to: UInt8.self)
      for y in 0..<height {
        let fy = max(0, min(Float(bh - 1), (Float(y) + 0.5) * Float(bh) / Float(height) - 0.5))
        let y0 = Int(fy), y1 = min(bh - 1, y0 + 1), ty = fy - Float(y0)
        for x in 0..<width {
          let fx = max(0, min(Float(bw - 1), (Float(x) + 0.5) * Float(bw) / Float(width) - 0.5))
          let x0 = Int(fx), x1 = min(bw - 1, x0 + 1), tx = fx - Float(x0)
          let top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx
          let bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx
          let v = top * (1 - ty) + bottom * ty
          o[y * width + x] = UInt8(max(0, min(255, (v * 255).rounded())))
        }
      }
    }
    return out
  }
}

/// 縮時影片：把一張張 PNG 畫格用 AVAssetWriter 做成 H.264 的 MP4。
///
/// Dart 那邊(lib/services/timelapse_recorder.dart)送來畫格路徑(同一張重複送
/// 就是停在那一格)、fps、寬高、輸出路徑;做好回傳輸出路徑,失敗回錯誤。
enum VideoEncoder {
  /// 通道要留著(放在 static),不然離開這個函式就被釋放,Dart 那邊叫不到。
  private static var channel: FlutterMethodChannel?

  enum EncodeError: Error { case setup, decode, append, finish }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "picosnap/video", binaryMessenger: messenger)
    Self.channel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "encode",
        let args = call.arguments as? [String: Any],
        let frames = args["frames"] as? [String], !frames.isEmpty,
        let out = args["out"] as? String,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let fps = args["fps"] as? Int ?? 12
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try encode(frames: frames, out: out, fps: fps, width: width, height: height)
          DispatchQueue.main.async { result(out) }
        } catch {
          try? FileManager.default.removeItem(atPath: out)
          DispatchQueue.main.async {
            result(FlutterError(code: "encode", message: "\(error)", details: nil))
          }
        }
      }
    }
  }

  static func encode(frames: [String], out: String, fps: Int, width: Int, height: Int) throws {
    let url = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
      ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    guard writer.canAdd(input) else { throw EncodeError.setup }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? EncodeError.setup }
    writer.startSession(atSourceTime: .zero)

    var loaded: String?
    var buffer: CVPixelBuffer?
    do {
      for (i, path) in frames.enumerated() {
        // 同一張重複出現(最後停住的成品)就不用重新讀
        if path != loaded {
          buffer = try pixelBuffer(path: path, width: width, height: height)
          loaded = path
        }
        // 寫入失敗(例如空間不足)之後永遠不會 ready:不要一直等
        while !input.isReadyForMoreMediaData {
          if writer.status == .failed { throw writer.error ?? EncodeError.append }
          Thread.sleep(forTimeInterval: 0.005)
        }
        let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
        guard let frame = buffer, adaptor.append(frame, withPresentationTime: time) else {
          throw writer.error ?? EncodeError.append
        }
      }
    } catch {
      // 收掉寫到一半的影片,呼叫的地方會刪檔
      writer.cancelWriting()
      throw error
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? EncodeError.finish }
  }

  /// 讀一張 PNG,畫進編碼器要的像素緩衝(大小不同就縮放)。
  static func pixelBuffer(path: String, width: Int, height: Int) throws -> CVPixelBuffer {
    guard let image = UIImage(contentsOfFile: path)?.cgImage else { throw EncodeError.decode }
    var created: CVPixelBuffer?
    let attrs = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ] as CFDictionary
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs, &created)
        == kCVReturnSuccess,
      let buffer = created
    else { throw EncodeError.decode }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    else { throw EncodeError.decode }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}
