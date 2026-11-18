import AVFoundation
import Flutter
import UIKit

/// Plays a finished «فيديو الآية» inside the share sheet on iPhone; the twin
/// of Android's AyahVideoPlayerView.kt with the same channel calls.
///
/// Creation params: {"path": "/abs/file.mp4"}. It starts playing at once, plays
/// one time and stops on the last frame. Flutter draws the controls and talks
/// to it on "<viewType>_<viewId>": play, pause, state.
final class AyahVideoPlayerFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "com.mahfodqr.qalon_mushaf/ayah_video_player"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    let path = (args as? [String: Any])?["path"] as? String ?? ""
    return AyahVideoPlayerView(frame: frame, viewId: viewId, path: path, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class PlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private final class AyahVideoPlayerView: NSObject, FlutterPlatformView {
  private let container: PlayerLayerView
  private let player: AVPlayer
  private let channel: FlutterMethodChannel
  private var ended = false
  private var endObserver: NSObjectProtocol?

  init(frame: CGRect, viewId: Int64, path: String, messenger: FlutterBinaryMessenger) {
    player = AVPlayer(url: URL(fileURLWithPath: path))
    player.actionAtItemEnd = .pause
    container = PlayerLayerView(frame: frame)
    container.backgroundColor = .black
    container.playerLayer.videoGravity = .resizeAspect
    container.playerLayer.player = player
    channel = FlutterMethodChannel(
      name: "\(AyahVideoPlayerFactory.viewType)_\(viewId)", binaryMessenger: messenger)
    super.init()

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
    ) { [weak self] _ in self?.ended = true }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handle(call, result: result)
    }

    // The app's own session is normally «playback» already (the recitation
    // player sets it). Only a silent-switch-bound category is lifted, so the
    // preview is heard even with the ringer off, like any video.
    let session = AVAudioSession.sharedInstance()
    if session.category == .ambient || session.category == .soloAmbient {
      try? session.setCategory(.playback, mode: .moviePlayback)
    }
    player.play()
  }

  deinit {
    channel.setMethodCallHandler(nil)
    if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    player.pause()
    container.playerLayer.player = nil
  }

  func view() -> UIView { container }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      if ended {
        ended = false
        player.seek(to: .zero)
      }
      player.play()
      result(nil)
    case "pause":
      player.pause()
      result(nil)
    case "state":
      let item = player.currentItem
      let position = CMTimeGetSeconds(player.currentTime())
      let duration = item.map { CMTimeGetSeconds($0.duration) } ?? 0
      result([
        "position": position.isFinite ? Int(position * 1000) : 0,
        "duration": duration.isFinite ? Int(duration * 1000) : 0,
        // "Meant to play", so the play button does not flash while loading.
        "playing": player.timeControlStatus != .paused && !ended,
        "ended": ended,
        "error": item?.status == .failed,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
