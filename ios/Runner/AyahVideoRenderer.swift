import AVFoundation
import CoreImage
import Flutter
import UIKit

/// «فيديو الآية» on iPhone: builds the MP4 on the phone with AVFoundation,
/// so nothing is uploaded and our server does no work. It is the twin of
/// Android's AyahVideoRenderer.kt and takes the very same arguments: Dart
/// prepares everything that is drawn (one picture per ayah group with the
/// mushaf text, the surah title and the watermark, and the closing card) and
/// the audio clips; this class only puts them together:
///
///   video: the background clip, looping until the recitation ends, with the
///          right picture laid over every frame (Core Image), H.264;
///   audio: the recitation clips one after another, then the closing card's
///          silence, at 44.1 kHz stereo, with the echo or reverb
///          ([AyahAudioEffect]) over the whole of it, AAC.
///
/// Channel `com.mahfodqr.qalon_mushaf/ayah_video`:
///   isSupported -> Bool
///   render(args) -> {"path": String, "durationMs": Int}  (or an error)
///   progress -> Double in 0..1, or nil before it starts
///   cancel
final class AyahVideoRenderer: NSObject {
  static let channelName = "com.mahfodqr.qalon_mushaf/ayah_video"

  static func register(with registrar: FlutterPluginRegistrar) {
    let renderer = AyahVideoRenderer()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in renderer.handle(call, result: result) }
    registrar.register(
      AyahVideoPlayerFactory(messenger: registrar.messenger()),
      withId: AyahVideoPlayerFactory.viewType)
  }

  private var job: AyahVideoJob?

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "progress":
      result(job?.progress)
    case "cancel":
      job?.cancel()
      job = nil
      result(nil)
    case "render":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "no arguments", details: nil))
        return
      }
      job?.cancel()
      let j = AyahVideoJob(args: args)
      job = j
      j.start { outcome in
        DispatchQueue.main.async {
          if self.job === j { self.job = nil }
          switch outcome {
          case .done(let ms):
            result(["path": j.outputPath, "durationMs": ms])
          case .cancelled:
            result(FlutterError(code: "cancelled", message: "cancelled", details: nil))
          case .failed(let message):
            NSLog("AyahVideo: %@", message)
            result(FlutterError(code: "render_failed", message: message, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private enum JobOutcome {
  case done(Int)
  case cancelled
  case failed(String)
}

private struct JobError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

private struct TimedClip {
  let url: URL
  let startMs: Int64
  let lengthMs: Int64
}

private struct TimedPicture {
  let startMs: Int64
  let path: String
}

private final class AyahVideoJob {
  let outputPath: String
  private let args: [String: Any]
  private let lock = NSLock()
  private var isCancelled = false
  private var progressValue: Double?
  private var failure: String?
  private let work = DispatchQueue(label: "ayah_video.work", qos: .userInitiated)
  private let videoQueue = DispatchQueue(label: "ayah_video.video", qos: .userInitiated)
  private let audioQueue = DispatchQueue(label: "ayah_video.audio", qos: .userInitiated)

  init(args: [String: Any]) {
    self.args = args
    outputPath = args["output"] as? String ?? ""
  }

  var progress: Double? {
    lock.lock()
    defer { lock.unlock() }
    return progressValue
  }

  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isCancelled
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    lock.unlock()
  }

  private func setProgress(_ p: Double) {
    lock.lock()
    progressValue = p
    lock.unlock()
  }

  private func fail(_ message: String) {
    lock.lock()
    if failure == nil { failure = message }
    lock.unlock()
  }

  private var failed: String? {
    lock.lock()
    defer { lock.unlock() }
    return failure
  }

  func start(_ done: @escaping (JobOutcome) -> Void) {
    work.async {
      let outcome: JobOutcome
      do {
        outcome = try self.run()
      } catch let e as JobError {
        outcome = self.cancelled ? .cancelled : .failed(e.message)
      } catch {
        outcome = self.cancelled ? .cancelled : .failed("\(error)")
      }
      done(outcome)
    }
  }

  // MARK: the timeline

  private func run() throws -> JobOutcome {
    guard !outputPath.isEmpty else { throw JobError("no output") }
    let fps = Int32(max(1, min(60, (args["fps"] as? NSNumber)?.intValue ?? 30)))
    let bitrate = (args["bitrate"] as? NSNumber)?.intValue ?? 5_000_000
    guard let segments = args["segments"] as? [[String: Any]] else { throw JobError("no segments") }

    var clips: [TimedClip] = []
    var pictures: [TimedPicture] = []
    var atMs: Int64 = 0
    for seg in segments {
      let segStart = atMs
      for c in seg["clips"] as? [[String: Any]] ?? [] {
        if cancelled { return .cancelled }
        guard let uri = c["uri"] as? String else { continue }
        let url = try localURL(uri)
        let start = (c["startMs"] as? NSNumber)?.int64Value ?? 0
        let end = (c["endMs"] as? NSNumber)?.int64Value
        let length = try (end ?? durationMs(url)) - start
        if length <= 0 { continue }
        clips.append(TimedClip(url: url, startMs: start, lengthMs: length))
        atMs += length
      }
      if atMs > segStart, let path = seg["overlay"] as? String {
        pictures.append(TimedPicture(startMs: segStart, path: path))
      }
    }
    if clips.isEmpty { throw JobError("no audio") }
    var totalMs = atMs
    var closingMs: Int64 = 0
    if let closing = args["closing"] as? [String: Any], let path = closing["overlay"] as? String {
      closingMs = max(0, (closing["ms"] as? NSNumber)?.int64Value ?? 0)
      pictures.append(TimedPicture(startMs: atMs, path: path))
      totalMs += closingMs
    }
    guard let bg = args["background"] as? [String: Any],
      let bgUri = bg["uri"] as? String,
      let bgURL = URL(string: bgUri)
    else { throw JobError("no background") }
    let bgIsImage = (bg["image"] as? Bool) == true

    // The size of the pictures is the size of the video.
    var width = (args["width"] as? NSNumber)?.intValue ?? 0
    var height = (args["height"] as? NSNumber)?.intValue ?? 0
    if width <= 0 || height <= 0, let first = pictures.first,
      let img = UIImage(contentsOfFile: first.path)?.cgImage
    {
      width = img.width
      height = img.height
    }
    width -= width % 2
    height -= height % 2
    if width <= 0 || height <= 0 { throw JobError("no size") }

    // MARK: the writer

    try? FileManager.default.removeItem(atPath: outputPath)
    let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputPath), fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true

    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
          AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
          AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
          AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitrate,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2,
          AVVideoExpectedSourceFrameRateKey: Int(fps),
        ],
      ])
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ])

    var layout = AudioChannelLayout()
    layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
    let audioInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: AudioSource.rate,
        AVNumberOfChannelsKey: AudioSource.channels,
        AVEncoderBitRateKey: 128_000,
        AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
      ])
    audioInput.expectsMediaDataInRealTime = false

    guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
      throw JobError("writer refused the inputs")
    }
    writer.add(videoInput)
    writer.add(audioInput)

    let video = try VideoSource(
      url: bgURL, isImage: bgIsImage, width: width, height: height, pictures: pictures)
    let audio = AudioSource(
      clips: clips, closingMs: closingMs, effect: args["effect"] as? [String: Any])

    guard writer.startWriting() else {
      throw JobError("writer: \(writer.error?.localizedDescription ?? "cannot start")")
    }
    writer.startSession(atSourceTime: .zero)

    let totalFrames = Int64((Double(totalMs) * Double(fps) / 1000).rounded(.up))
    let group = DispatchGroup()

    // Both inputs are fed at once, each on its own queue: the writer
    // interleaves them and holds back whichever runs ahead.
    group.enter()
    var frame: Int64 = 0
    var videoDone = false
    videoInput.requestMediaDataWhenReady(on: videoQueue) {
      func finish() {
        if videoDone { return }
        videoDone = true
        videoInput.markAsFinished()
        group.leave()
      }
      while videoInput.isReadyForMoreMediaData && !videoDone {
        if self.cancelled || self.failed != nil || frame >= totalFrames {
          finish()
          return
        }
        do {
          let ms = frame * 1000 / Int64(fps)
          guard let pool = adaptor.pixelBufferPool else { throw JobError("no pixel buffer pool") }
          let pb = try video.frame(atMs: ms, pool: pool)
          if !adaptor.append(pb, withPresentationTime: CMTime(value: frame, timescale: fps)) {
            throw JobError("video: \(writer.error?.localizedDescription ?? "append failed")")
          }
          frame += 1
          self.setProgress(min(0.99, Double(frame) / Double(max(totalFrames, 1))))
        } catch let e as JobError {
          self.fail(e.message)
          finish()
          return
        } catch {
          self.fail("video: \(error)")
          finish()
          return
        }
      }
    }

    group.enter()
    var audioDone = false
    audioInput.requestMediaDataWhenReady(on: audioQueue) {
      func finish() {
        if audioDone { return }
        audioDone = true
        audioInput.markAsFinished()
        group.leave()
      }
      while audioInput.isReadyForMoreMediaData && !audioDone {
        if self.cancelled || self.failed != nil {
          finish()
          return
        }
        do {
          guard let sb = try audio.next() else {
            finish()
            return
          }
          if !audioInput.append(sb) {
            throw JobError("audio: \(writer.error?.localizedDescription ?? "append failed")")
          }
        } catch let e as JobError {
          self.fail(e.message)
          finish()
          return
        } catch {
          self.fail("audio: \(error)")
          finish()
          return
        }
      }
    }

    group.wait()
    if cancelled || failed != nil {
      writer.cancelWriting()
      try? FileManager.default.removeItem(atPath: outputPath)
      if let f = failed, !cancelled { return .failed(f) }
      return .cancelled
    }
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    if writer.status != .completed {
      return .failed("finish: \(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")")
    }
    setProgress(1)
    return .done(Int(totalMs))
  }

  /// A file the readers can open. AVAssetReader cannot read from the
  /// network, so a clip still on the mirror (Dart normally downloads it
  /// first) is fetched whole into the temporary folder.
  private func localURL(_ uri: String) throws -> URL {
    guard let url = URL(string: uri) else { throw JobError("bad uri \(uri)") }
    if url.isFileURL { return url }
    guard url.scheme == "http" || url.scheme == "https" else { throw JobError("bad uri \(uri)") }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "ayah_video_audio", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = String(uri.hashValue.magnitude) + "_" + url.lastPathComponent
    let dest = dir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: dest.path) { return dest }
    let done = DispatchSemaphore(value: 0)
    var problem: String?
    URLSession.shared.downloadTask(with: url) { tmp, response, err in
      defer { done.signal() }
      if let err = err {
        problem = err.localizedDescription
        return
      }
      guard let tmp = tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
        problem = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
        return
      }
      do {
        try FileManager.default.moveItem(at: tmp, to: dest)
      } catch {
        problem = "\(error)"
      }
    }.resume()
    done.wait()
    if let problem = problem { throw JobError("download: \(problem)") }
    return dest
  }

  private func durationMs(_ url: URL) throws -> Int64 {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let seconds = CMTimeGetSeconds(asset.duration)
    guard seconds.isFinite, seconds > 0 else { throw JobError("no duration for \(url.lastPathComponent)") }
    return Int64((seconds * 1000).rounded())
  }
}

// MARK: - pictures

/// The background clip (looping) or still picture, with the picture of the
/// moment laid over it, one frame at a time.
private final class VideoSource {
  private let width: Int
  private let height: Int
  private let pictures: [TimedPicture]
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  private let context: CIContext

  private var pictureIndex = -1
  private var picture: CIImage?

  private let asset: AVURLAsset?
  private let track: AVAssetTrack?
  private let loopMs: Int64
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var current: (ms: Int64, sample: CMSampleBuffer)?
  private var upcoming: (ms: Int64, sample: CMSampleBuffer)?
  private var lastLocalMs: Int64 = -1

  init(url: URL, isImage: Bool, width: Int, height: Int, pictures: [TimedPicture]) throws {
    self.width = width
    self.height = height
    self.pictures = pictures
    context = CIContext(options: [.workingColorSpace: colorSpace, .cacheIntermediates: false])
    if isImage {
      guard let img = CIImage(contentsOf: url) else { throw JobError("cannot read the background") }
      asset = nil
      track = nil
      loopMs = 0
      stillImage = VideoSource.fill(img, width: width, height: height)
      return
    }
    stillImage = nil
    let a = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let t = a.tracks(withMediaType: .video).first else { throw JobError("the background has no video") }
    asset = a
    track = t
    let seconds = CMTimeGetSeconds(t.timeRange.duration)
    loopMs = seconds.isFinite && seconds > 0 ? Int64(seconds * 1000) : 0
    try openReader()
  }

  private let stillImage: CIImage?

  private func openReader() throws {
    guard let asset = asset, let track = track else { return }
    reader?.cancelReading()
    let r = try AVAssetReader(asset: asset)
    let o = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    o.alwaysCopiesSampleData = false
    guard r.canAdd(o) else { throw JobError("cannot read the background") }
    r.add(o)
    guard r.startReading() else {
      throw JobError("background: \(r.error?.localizedDescription ?? "cannot read")")
    }
    reader = r
    output = o
    current = nil
    upcoming = nil
  }

  private func read() -> (ms: Int64, sample: CMSampleBuffer)? {
    guard let sb = output?.copyNextSampleBuffer() else { return nil }
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
    let start = CMTimeGetSeconds(track?.timeRange.start ?? .zero)
    return (Int64(((pts - start) * 1000).rounded()), sb)
  }

  /// The background at [ms] of the video: the clip's frame at that point of
  /// its loop, held when the clip has no newer frame.
  private func background(atMs ms: Int64) throws -> CIImage {
    if let s = stillImage { return s }
    let local = loopMs > 0 ? ms % loopMs : ms
    if local < lastLocalMs { try openReader() }  // the loop came round
    lastLocalMs = local
    if current == nil { current = read() }
    while true {
      if upcoming == nil { upcoming = read() }
      guard let next = upcoming, next.ms <= local else { break }
      current = next
      upcoming = nil
    }
    guard let frame = current ?? upcoming, let pb = CMSampleBufferGetImageBuffer(frame.sample) else {
      throw JobError("the background has no frames")
    }
    var img = CIImage(cvPixelBuffer: pb)
    if let t = track?.preferredTransform, !t.isIdentity {
      img = img.transformed(by: t)
      img = img.transformed(
        by: CGAffineTransform(translationX: -img.extent.origin.x, y: -img.extent.origin.y))
    }
    return VideoSource.fill(img, width: width, height: height)
  }

  private func picture(atMs ms: Int64) -> CIImage? {
    guard !pictures.isEmpty else { return nil }
    let i = pictures.lastIndex(where: { ms >= $0.startMs }) ?? 0
    if i != pictureIndex {
      pictureIndex = i
      picture = CIImage(contentsOf: URL(fileURLWithPath: pictures[i].path)).map {
        VideoSource.fill($0, width: width, height: height)
      }
    }
    return picture
  }

  func frame(atMs ms: Int64, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
    var image = try background(atMs: ms)
    if let p = picture(atMs: ms) { image = p.composited(over: image) }
    var out: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
    guard let pb = out else { throw JobError("no pixel buffer") }
    context.render(
      image, to: pb, bounds: CGRect(x: 0, y: 0, width: width, height: height),
      colorSpace: colorSpace)
    return pb
  }

  /// Scales [img] to cover width x height and crops the middle.
  private static func fill(_ img: CIImage, width: Int, height: Int) -> CIImage {
    let e = img.extent
    if e.width == CGFloat(width) && e.height == CGFloat(height) && e.origin == .zero { return img }
    let scale = max(CGFloat(width) / e.width, CGFloat(height) / e.height)
    let scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let s = scaled.extent
    let dx = s.origin.x + (s.width - CGFloat(width)) / 2
    let dy = s.origin.y + (s.height - CGFloat(height)) / 2
    return scaled
      .transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
      .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
  }
}

// MARK: - sound

/// The recitation as one stream: every clip cut to exactly its planned
/// length (so the pictures stay in step), then the closing silence, with the
/// effect over all of it.
private final class AudioSource {
  static let rate = 44100
  static let channels = 2
  private static let chunk = 4096

  private let clips: [TimedClip]
  private var clipIndex = -1
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var owed = 0  // frames the current clip still has to give
  private var pending: [Float] = []
  private var pendingAt = 0
  private var closingLeft: Int
  private var written: Int64 = 0
  private let effect: AyahAudioEffect?
  private var format: CMAudioFormatDescription?

  init(clips: [TimedClip], closingMs: Int64, effect: [String: Any]?) {
    self.clips = clips
    closingLeft = AudioSource.frames(closingMs)
    if let e = effect, AyahAudioEffect.isActive(e) {
      self.effect = AyahAudioEffect(params: e, sampleRate: AudioSource.rate, channels: AudioSource.channels)
    } else {
      self.effect = nil
    }
  }

  private static func frames(_ ms: Int64) -> Int {
    Int((Double(ms) * Double(rate) / 1000).rounded())
  }

  private func openClip(_ clip: TimedClip) throws {
    let asset = AVURLAsset(url: clip.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw JobError("no audio in \(clip.url.lastPathComponent)")
    }
    let r = try AVAssetReader(asset: asset)
    r.timeRange = CMTimeRange(
      start: CMTime(value: clip.startMs, timescale: 1000),
      duration: CMTime(value: clip.lengthMs, timescale: 1000))
    let o = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: AudioSource.rate,
        AVNumberOfChannelsKey: AudioSource.channels,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    guard r.canAdd(o) else { throw JobError("cannot read \(clip.url.lastPathComponent)") }
    r.add(o)
    guard r.startReading() else {
      throw JobError("audio: \(r.error?.localizedDescription ?? "cannot read")")
    }
    reader = r
    output = o
    owed = AudioSource.frames(clip.lengthMs)
    pending = []
    pendingAt = 0
  }

  /// Decoded samples of the current clip; nil at its end.
  private func refill() throws -> Bool {
    while let sb = output?.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
      let length = CMBlockBufferGetDataLength(block)
      if length == 0 { continue }
      var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
      let status = data.withUnsafeMutableBytes { raw in
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
      }
      if status != kCMBlockBufferNoErr { continue }
      pending = data
      pendingAt = 0
      return true
    }
    if reader?.status == .failed {
      throw JobError("audio: \(reader?.error?.localizedDescription ?? "read failed")")
    }
    return false
  }

  func next() throws -> CMSampleBuffer? {
    let ch = AudioSource.channels
    var buf = [Float]()
    buf.reserveCapacity(AudioSource.chunk * ch)
    while buf.count < AudioSource.chunk * ch {
      let room = AudioSource.chunk - buf.count / ch
      if output != nil {
        if owed <= 0 {
          reader?.cancelReading()
          reader = nil
          output = nil
          continue
        }
        if pendingAt >= pending.count {
          if try !refill() {
            // The file ended early: silence keeps the timeline exact.
            let n = min(owed, room)
            buf.append(contentsOf: [Float](repeating: 0, count: n * ch))
            owed -= n
            continue
          }
        }
        let available = (pending.count - pendingAt) / ch
        let n = min(available, owed, room)
        buf.append(contentsOf: pending[pendingAt..<(pendingAt + n * ch)])
        pendingAt += n * ch
        owed -= n
      } else if clipIndex + 1 < clips.count {
        clipIndex += 1
        try openClip(clips[clipIndex])
      } else if closingLeft > 0 {
        let n = min(closingLeft, room)
        buf.append(contentsOf: [Float](repeating: 0, count: n * ch))
        closingLeft -= n
      } else {
        break
      }
    }
    if buf.isEmpty { return nil }
    let frames = buf.count / ch
    if let e = effect {
      buf.withUnsafeMutableBufferPointer { p in e.process(p.baseAddress!, frames: frames) }
    }
    let sb = try sampleBuffer(buf, frames: frames)
    written += Int64(frames)
    return sb
  }

  private func sampleBuffer(_ samples: [Float], frames: Int) throws -> CMSampleBuffer {
    if format == nil {
      var asbd = AudioStreamBasicDescription(
        mSampleRate: Float64(AudioSource.rate),
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(4 * AudioSource.channels),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(4 * AudioSource.channels),
        mChannelsPerFrame: UInt32(AudioSource.channels),
        mBitsPerChannel: 32,
        mReserved: 0)
      var f: CMAudioFormatDescription?
      CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &f)
      guard let made = f else { throw JobError("audio format") }
      format = made
    }
    let bytes = samples.count * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
      blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
      dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    guard let b = block else { throw JobError("audio block") }
    let copied = samples.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(
        with: raw.baseAddress!, blockBuffer: b, offsetIntoDestination: 0, dataLength: bytes)
    }
    guard copied == kCMBlockBufferNoErr else { throw JobError("audio copy") }
    var sb: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: kCFAllocatorDefault, dataBuffer: b, formatDescription: format!,
      sampleCount: frames,
      presentationTimeStamp: CMTime(value: written, timescale: CMTimeScale(AudioSource.rate)),
      packetDescriptions: nil, sampleBufferOut: &sb)
    guard let out = sb else { throw JobError("audio sample buffer") }
    return out
  }
}
