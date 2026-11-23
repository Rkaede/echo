// A Swift port of Cuelume's renderer — https://github.com/danielwh2/cuelume
// Copyright (c) 2026 Daniel Belyi. MIT License; see Cuelume-LICENSE.txt beside this file.
//
// Cuelume renders live with Web Audio nodes. Echo renders one play offline into a buffer instead,
// following Cuelume's own offline renderer (scripts/sound.mjs): the same envelopes and glides, Web
// Audio's RBJ biquads, the shared room, output gain, subsonic cut and soft clip.

import AVFoundation
import Accelerate
import Foundation

/// One rendered play: stereo samples at `CuelumeSynth.sampleRate`.
struct CuelumeRendering: Sendable {
  let left: [Float]
  let right: [Float]

  var frameCount: Int { left.count }
  var duration: TimeInterval { Double(frameCount) / CuelumeSynth.sampleRate }

  /// A deinterleaved float buffer for AVAudioEngine.
  func makeBuffer() -> AVAudioPCMBuffer? {
    guard
      let format = AVAudioFormat(standardFormatWithSampleRate: CuelumeSynth.sampleRate, channels: 2),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
      let channels = buffer.floatChannelData
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(frameCount)
    left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: frameCount) }
    right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: frameCount) }
    return buffer
  }
}

enum CuelumeSynth {
  static let sampleRate: Double = 48_000

  // Output stage (Cuelume's output.ts).
  static let outputGain = 5.8
  static let clipKnee = 0.7
  static let subsonicHz = 40.0
  /// A lowpass or highpass Q in dB that gives a flat, unresonant corner.
  static let flatQ = -3.0

  // Layers (render.ts).
  static let sourceStopPadding = 0.05
  static let decayDB = 60.0
  /// A play with no real let-go plays its release this long after the press.
  static let releaseGap = 0.09
  /// Within one strike, each layer's ring length moves by up to this.
  static let decayJitter = 0.1
  /// And each tone's pitch by up to this, about 9 cents.
  static let modeJitter = 0.005
  /// CuelumeBiquad coefficients follow a gliding filter every this many samples, as sound.mjs does.
  static let filterUpdateInterval = 32

  // Shared room (output.ts).
  static let roomSeconds = 0.25
  static let roomPredelay = 0.008
  static let roomLowpass = 3500.0
  /// How much of every cue reaches the room: about 22 dB down.
  static let roomSend = 0.08
  static let roomSeeds: [UInt32] = [3110, 5639]
  static let roomReflectionsPerSecond = 48_000.0

  /// Seconds of shared noise. Noise layers read it from a random point.
  static let noiseSeconds = 2.0
  static let noiseSeed: UInt32 = 1

  /// Layers centred at or above this count as bright, which emphasis leans on.
  static let brightHz = 2500.0

  static func fallTime(_ decay: Double) -> Double {
    decay / ((decayDB / 20) * M_LN10)
  }

  // MARK: - Rendering

  /// Renders one play of `cue`: the press and, for themes that have one, its release.
  static func render<R: RandomNumberGenerator>(
    _ cue: CuelumeCue, theme: CuelumeTheme, emphasis: CuelumeEmphasis = .normal, using rng: inout R
  ) -> CuelumeRendering {
    render(theme.recipe(for: cue), emphasis: emphasis, using: &rng)
  }

  static func render(
    _ cue: CuelumeCue, theme: CuelumeTheme, emphasis: CuelumeEmphasis = .normal
  ) -> CuelumeRendering {
    var rng = SystemRandomNumberGenerator()
    return render(cue, theme: theme, emphasis: emphasis, using: &rng)
  }

  static func render<R: RandomNumberGenerator>(
    _ recipe: CuelumeRecipe, emphasis: CuelumeEmphasis = .normal, using rng: inout R
  ) -> CuelumeRendering {
    let layers = layers(for: recipe, emphasis: emphasis, using: &rng)
    guard !layers.isEmpty else { return CuelumeRendering(left: [], right: []) }

    let end =
      layers.map { $0.offset + $0.attack + $0.decay + sourceStopPadding }.max()! + roomSeconds + 0.05
    var dry = [Double](repeating: 0, count: Int((end * sampleRate).rounded(.up)))
    for layer in layers {
      add(layer, to: &dry, noiseStart: Int(Double.random(in: 0..<1, using: &rng) * Double(noise.count)))
    }

    let gain = recipe.masterGain * outputGain
    let send = roomSend * recipe.room
    let dryFloat = dry.map { Float($0) }
    let subsonic = CuelumeBiquad(.highpass, frequency: subsonicHz, q: flatQ)
    let channels = rooms.map { room -> [Float] in
      let wet = convolve(dryFloat, room)
      var mixed = [Double](repeating: 0, count: dry.count)
      for i in 0..<dry.count { mixed[i] = (dry[i] + Double(wet[i]) * send) * gain }
      return subsonic.process(mixed).map { Float(softClip($0)) }
    }
    return CuelumeRendering(left: channels[0], right: channels[1])
  }

  // MARK: - Shaping

  /// One play's strike: every layer shares it, so a harder strike is louder and brighter at once.
  private struct Strike {
    var pitch = 1.0
    var force = 1.0
  }

  /// How emphasis bends a cue (context.ts): most of the difference is which layers play.
  private struct Shape {
    var pitch = 1.0
    var level = 1.0
    var length = 1.0
    var bright = 1.0

    init(_ emphasis: CuelumeEmphasis) {
      switch emphasis {
      case .subtle: (level, length, bright) = (0.8, 0.85, 0.75)
      case .normal: break
      case .strong: (pitch, level, length, bright) = (0.98, 1.08, 1.2, 1.1)
      }
    }
  }

  /// The layers one play sounds: arranged for its emphasis, bent by its shape and strike, the
  /// release starting `releaseGap` after the press. Echo plays each cue on its own, so Cuelume's
  /// cadence, walk and input context, which follow quick repeats and pointer input, do not apply.
  static func layers<R: RandomNumberGenerator>(
    for recipe: CuelumeRecipe, emphasis: CuelumeEmphasis, using rng: inout R
  ) -> [CuelumeLayer] {
    let shape = Shape(emphasis)
    let vary = recipe.vary
    let strike =
      vary.map { Strike(pitch: nudge($0.pitch, using: &rng), force: nudge($0.level, using: &rng)) }
      ?? Strike()

    let parts: [(layers: [CuelumeLayer], delay: Double)] = [
      (recipe.layers, 0), (recipe.release, releaseGap),
    ]
    return parts.flatMap { part in
      part.layers.filter { emphasis >= $0.from }.map { layer in
        var bent = layer
        let gain =
          shape.level * (layer.frequency >= brightHz ? shape.bright : 1)
        let pitchFactor = min(1.25, max(0.75, shape.pitch))
        let lengthFactor = min(1.6, max(0.6, shape.length))
        let tune: Double
        switch layer.source {
        case .tone: tune = vary == nil ? 1 : nudge(modeJitter, using: &rng)
        case .noise: tune = strike.force
        }
        let pitch = pitchFactor * strike.pitch * tune
        bent.frequency = layer.frequency * pitch
        bent.glideTo = layer.glideTo.map { $0 * pitch }
        bent.peak = layer.peak * min(1.5, max(0, gain)) * strike.force
        bent.decay = layer.decay * lengthFactor * (vary == nil ? 1 : nudge(decayJitter, using: &rng))
        bent.offset = layer.offset + part.delay
        return bent
      }
    }
  }

  private static func nudge<R: RandomNumberGenerator>(_ amount: Double, using rng: inout R) -> Double {
    1 + (Double.random(in: 0..<1, using: &rng) * 2 - 1) * amount
  }

  // MARK: - Layers

  /// A straight swell to the peak, then an exponential fall of 60 dB over `decay`.
  static func envelope(_ layer: CuelumeLayer, at t: Double) -> Double {
    if t < 0 { return 0 }
    if t < layer.attack { return layer.peak * t / layer.attack }
    return layer.peak * exp((layer.attack - t) / fallTime(layer.decay))
  }

  /// Web Audio's exponential ramp from the layer's frequency to `glideTo`.
  static func pitch(_ layer: CuelumeLayer, at t: Double) -> Double {
    guard let target = layer.glideTo else { return layer.frequency }
    let time = layer.glideTime ?? (layer.attack + layer.decay)
    if t <= 0 { return layer.frequency }
    if t >= time { return target }
    return layer.frequency * pow(target / layer.frequency, t / time)
  }

  private static func add(_ layer: CuelumeLayer, to out: inout [Double], noiseStart: Int) {
    let start = Int((layer.offset * sampleRate).rounded())
    let length = Int(((layer.attack + layer.decay + sourceStopPadding) * sampleRate).rounded())
    let count = min(length, out.count - start)
    guard count > 0 else { return }

    switch layer.source {
    case .tone:
      var phase = 0.0
      for i in 0..<count {
        let t = Double(i) / sampleRate
        phase += 2 * Double.pi * pitch(layer, at: t) / sampleRate
        out[start + i] += envelope(layer, at: t) * sin(phase)
      }
    case .noise(let type, let q):
      var filter = CuelumeBiquad(type, frequency: layer.frequency, q: q)
      for i in 0..<count {
        let t = Double(i) / sampleRate
        if layer.glideTo != nil, i % filterUpdateInterval == 0 {
          filter.setCoefficients(type, frequency: pitch(layer, at: t), q: q)
        }
        let x = Double(noise[(noiseStart + i) % noise.count])
        out[start + i] += envelope(layer, at: t) * filter.next(x)
      }
    }
  }

  /// Rounds levels above the knee off towards a ceiling. Past full scale the level is held at
  /// the ceiling, as Web Audio's WaveShaperNode clamps its input; without that the curve bends
  /// back down and, from about 1.7, flips the sign.
  static func softClip(_ level: Double) -> Double {
    let shoulder = 1 - clipKnee
    let over = min(abs(level) - clipKnee, shoulder)
    guard over > 0 else { return level }
    return (level < 0 ? -1 : 1) * (clipKnee + over - (over * over) / (2 * shoulder))
  }

  // MARK: - Noise and room

  /// Cuelume's seeded generator (output.ts), bit for bit, so the noise and room match its own.
  struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
      state = state &+ 0x6d2b_79f5
      var mixed = (state ^ (state >> 15)) &* (1 | state)
      mixed = (mixed &+ ((mixed ^ (mixed >> 7)) &* (61 | mixed))) ^ mixed
      return Double(mixed ^ (mixed >> 14)) / 4_294_967_296
    }
  }

  static let noise: [Float] = {
    var random = SeededRandom(seed: noiseSeed)
    return (0..<Int(noiseSeconds * sampleRate)).map { _ in Float(2 * random.next() - 1) }
  }()

  /// One channel of the shared room: a short, dense burst of reflections dying away over
  /// `roomSeconds`, low-passed the way walls swallow the highs. Each channel is independent noise,
  /// so the room is wide while the sound itself stays centred.
  static func room(seed: UInt32) -> [Float] {
    var random = SeededRandom(seed: seed)
    var data = [Double](repeating: 0, count: Int(roomSeconds * sampleRate))
    let fall = (decayDB / 20) * M_LN10
    var reflections = [Double](repeating: 0, count: Int(roomSeconds * roomReflectionsPerSecond))
    var energy = 0.0
    for i in reflections.indices {
      let t = Double(i) / roomReflectionsPerSecond
      reflections[i] = t < roomPredelay ? 0 : (2 * random.next() - 1) * exp(-fall * t / roomSeconds)
      energy += reflections[i] * reflections[i]
    }
    let scale = 1 / energy.squareRoot()
    for i in reflections.indices {
      let at = Double(i) / roomReflectionsPerSecond * sampleRate
      let sample = Int(at)
      let late = at - Double(sample)
      if sample < data.count { data[sample] += reflections[i] * scale * (1 - late) }
      if sample + 1 < data.count { data[sample + 1] += reflections[i] * scale * late }
    }
    return CuelumeBiquad(.lowpass, frequency: roomLowpass, q: flatQ).process(data).map { Float($0) }
  }

  static let rooms: [[Float]] = roomSeeds.map { room(seed: $0) }

  /// Linear convolution by FFT, trimmed to `signal`'s length.
  static func convolve(_ signal: [Float], _ kernel: [Float]) -> [Float] {
    guard !signal.isEmpty, !kernel.isEmpty else { return [Float](repeating: 0, count: signal.count) }
    var log2n = 0
    while (1 << log2n) < signal.count + kernel.count { log2n += 1 }
    let n = 1 << log2n
    guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
      return [Float](repeating: 0, count: signal.count)
    }
    defer { vDSP_destroy_fftsetup(setup) }

    var signalReal = signal + [Float](repeating: 0, count: n - signal.count)
    var signalImag = [Float](repeating: 0, count: n)
    var kernelReal = kernel + [Float](repeating: 0, count: n - kernel.count)
    var kernelImag = [Float](repeating: 0, count: n)

    signalReal.withUnsafeMutableBufferPointer { sr in
      signalImag.withUnsafeMutableBufferPointer { si in
        kernelReal.withUnsafeMutableBufferPointer { kr in
          kernelImag.withUnsafeMutableBufferPointer { ki in
            var a = DSPSplitComplex(realp: sr.baseAddress!, imagp: si.baseAddress!)
            var b = DSPSplitComplex(realp: kr.baseAddress!, imagp: ki.baseAddress!)
            vDSP_fft_zip(setup, &a, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
            vDSP_fft_zip(setup, &b, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
            vDSP_zvmul(&a, 1, &b, 1, &a, 1, vDSP_Length(n), 1)
            vDSP_fft_zip(setup, &a, 1, vDSP_Length(log2n), FFTDirection(FFT_INVERSE))
          }
        }
      }
    }
    var scale = 1 / Float(n)
    var result = [Float](repeating: 0, count: signal.count)
    vDSP_vsmul(signalReal, 1, &scale, &result, 1, vDSP_Length(signal.count))
    return result
  }
}

/// A biquad with Web Audio's coefficients (the RBJ cookbook), in direct form I.
struct CuelumeBiquad {
  private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
  private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

  init(_ type: CuelumeFilter, frequency: Double, q: Double) {
    setCoefficients(type, frequency: frequency, q: q)
  }

  mutating func setCoefficients(_ type: CuelumeFilter, frequency: Double, q: Double) {
    let rate = CuelumeSynth.sampleRate
    let w = 2 * Double.pi * min(frequency, rate / 2 - 1) / rate
    let c = cos(w)
    let s = sin(w)
    let b: (Double, Double, Double)
    let alpha: Double
    switch type {
    case .bandpass:
      alpha = s / (2 * q)
      b = (alpha, 0, -alpha)
    case .lowpass:
      alpha = s / (2 * pow(10, q / 20))
      b = ((1 - c) / 2, 1 - c, (1 - c) / 2)
    case .highpass:
      alpha = s / (2 * pow(10, q / 20))
      b = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
    }
    let a0 = 1 + alpha
    (b0, b1, b2) = (b.0 / a0, b.1 / a0, b.2 / a0)
    (a1, a2) = (-2 * c / a0, (1 - alpha) / a0)
  }

  mutating func next(_ x: Double) -> Double {
    let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    (x2, x1, y2, y1) = (x1, x, y1, y)
    return y
  }

  func process(_ input: [Double]) -> [Double] {
    var filter = self
    return input.map { filter.next($0) }
  }
}
