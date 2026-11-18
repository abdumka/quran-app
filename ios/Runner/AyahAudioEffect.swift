import Foundation

/// The «صدى / غرفة / قاعة» of an ayah video on iPhone: the same echo and
/// Freeverb as Android's AyahAudioEffect.kt, number for number, so a video
/// sounds the same whichever phone made it. Pitch and speed are never touched.
///
/// Runs once over the whole recitation (interleaved Float32, any channel
/// count), so a reverb tail carries across ayah boundaries and rings out into
/// the closing card's silence.
///
///   echo:   {"type": "echo", "taps": [[delayMs, gain], ...], "dry": 1.0}
///   reverb: {"type": "reverb", "room": 0..1, "damping": 0..1,
///            "wet": 0..1, "dry": 0..1, "width": 0..1}
final class AyahAudioEffect {
  private static let knee: Float = 0.9
  private static let fixedGain: Float = 0.015
  private static let wetScale: Float = 3
  private static let stereoSpread = 23
  private static let combTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
  private static let allpassTuning = [556, 441, 341, 225]

  /// Whether [params] asks for any processing at all.
  static func isActive(_ params: [String: Any]?) -> Bool {
    let t = params?["type"] as? String
    return t == "echo" || t == "reverb"
  }

  private static func num(_ v: Any?, _ fallback: Double) -> Double {
    if let n = v as? NSNumber {
      let d = n.doubleValue
      return d.isFinite ? d : fallback
    }
    return fallback
  }

  private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, lo), hi)
  }

  private let type: String
  private let dry: Float
  private let channels: Int

  // echo
  private var echoLines: [[Float]] = []
  private var echoDelays: [Int] = []
  private var echoGains: [Float] = []
  private var echoPos = 0

  // reverb
  private var verbs: [Freeverb] = []
  private let wet: Float
  private let width: Float

  init(params: [String: Any], sampleRate: Int, channels: Int) {
    type = params["type"] as? String ?? "none"
    dry = Float(Self.clamp(Self.num(params["dry"], 1.0), 0, 1.5))
    self.channels = max(1, channels)
    wet = Float(Self.clamp(Self.num(params["wet"], 0.1), 0, 1))
    width = Float(Self.clamp(Self.num(params["width"], 1.0), 0, 1))

    if type == "echo" {
      for t in params["taps"] as? [Any] ?? [] {
        guard let l = t as? [Any], l.count >= 2 else { continue }
        let ms = Self.clamp(Self.num(l[0], 0), 10, 2000)
        echoDelays.append(Int((ms * Double(sampleRate) / 1000).rounded()))
        echoGains.append(Float(Self.clamp(Self.num(l[1], 0), 0, 0.9)))
      }
      let len = (echoDelays.max() ?? 0) + 1
      echoLines = Array(repeating: [Float](repeating: 0, count: len), count: self.channels)
    } else if type == "reverb" {
      let room = Self.clamp(Self.num(params["room"], 0.5), 0, 0.98)
      let damping = Self.clamp(Self.num(params["damping"], 0.5), 0, 1)
      verbs = (0..<self.channels).map { c in
        Freeverb(rate: sampleRate, spread: c % 2 == 1 ? Self.stereoSpread : 0, room: room, damping: damping)
      }
    }
  }

  /// Processes [frames] interleaved frames of [samples] in place.
  func process(_ samples: UnsafeMutablePointer<Float>, frames: Int) {
    if type != "echo" && type != "reverb" { return }
    var x = [Float](repeating: 0, count: channels)
    var y = [Float](repeating: 0, count: channels)
    for f in 0..<frames {
      let base = f * channels
      for c in 0..<channels { x[c] = samples[base + c] }
      if type == "echo" {
        echo(x, &y)
      } else {
        reverb(x, &y)
      }
      for c in 0..<channels { samples[base + c] = Self.limit(y[c]) }
    }
  }

  private func echo(_ x: [Float], _ y: inout [Float]) {
    let len = echoLines.first?.count ?? 1
    for c in 0..<channels {
      var v = x[c] * dry
      for i in 0..<echoDelays.count {
        var p = echoPos - echoDelays[i]
        if p < 0 { p += len }
        v += echoLines[c][p] * echoGains[i]
      }
      echoLines[c][echoPos] = x[c]
      y[c] = v
    }
    echoPos = (echoPos + 1) % len
  }

  private func reverb(_ x: [Float], _ y: inout [Float]) {
    // Freeverb feeds both channels the same mono sum and spreads the two
    // tanks slightly apart; the wet signal is then crossed by [width].
    var mono: Float = 0
    for c in 0..<channels { mono += x[c] }
    mono = mono / Float(channels) * Self.fixedGain
    if channels == 1 {
      y[0] = x[0] * dry + verbs[0].process(mono) * wet * Self.wetScale
      return
    }
    let l = verbs[0].process(mono)
    let r = verbs[1].process(mono)
    let wet1 = wet * Self.wetScale * (width / 2 + 0.5)
    let wet2 = wet * Self.wetScale * ((1 - width) / 2)
    y[0] = x[0] * dry + l * wet1 + r * wet2
    y[1] = x[1] * dry + r * wet1 + l * wet2
    if channels > 2 {
      for c in 2..<channels { y[c] = x[c] * dry }
    }
  }

  /// A soft knee above 0.9 instead of hard clipping when echo adds up.
  private static func limit(_ v: Float) -> Float {
    let a = abs(v)
    if a <= knee { return v }
    let s = knee + (1 - knee) * tanh((a - knee) / (1 - knee))
    return v < 0 ? -s : s
  }

  private final class Freeverb {
    private var combs: [Comb]
    private var allpasses: [Allpass]

    init(rate: Int, spread: Int, room: Double, damping: Double) {
      let scale = Double(rate) / 44100.0
      combs = AyahAudioEffect.combTuning.map { Comb(size: max(1, Int((Double($0 + spread) * scale).rounded()))) }
      allpasses = AyahAudioEffect.allpassTuning.map { Allpass(size: max(1, Int((Double($0 + spread) * scale).rounded()))) }
      let feedback = Float(room * 0.28 + 0.7)
      let damp1 = Float(damping * 0.4)
      for c in combs {
        c.feedback = feedback
        c.damp1 = damp1
        c.damp2 = 1 - damp1
      }
    }

    func process(_ input: Float) -> Float {
      var out: Float = 0
      for c in combs { out += c.process(input) }
      for a in allpasses { out = a.process(out) }
      return out
    }
  }

  private final class Comb {
    private var buf: [Float]
    private var idx = 0
    private var store: Float = 0
    var feedback: Float = 0.84
    var damp1: Float = 0.2
    var damp2: Float = 0.8

    init(size: Int) { buf = [Float](repeating: 0, count: size) }

    func process(_ x: Float) -> Float {
      let out = buf[idx]
      store = out * damp2 + store * damp1
      buf[idx] = x + store * feedback
      idx += 1
      if idx >= buf.count { idx = 0 }
      return out
    }
  }

  private final class Allpass {
    private var buf: [Float]
    private var idx = 0

    init(size: Int) { buf = [Float](repeating: 0, count: size) }

    func process(_ x: Float) -> Float {
      let b = buf[idx]
      let out = -x + b
      buf[idx] = x + b * 0.5
      idx += 1
      if idx >= buf.count { idx = 0 }
      return out
    }
  }
}
