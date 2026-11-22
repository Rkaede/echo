// A Swift port of Cuelume's sound model — https://github.com/danielwh2/cuelume
// Copyright (c) 2026 Daniel Belyi. MIT License; see Cuelume-LICENSE.txt beside this file.
//
// Every cue is a list of layers: one sine tone or one burst of filtered noise, shaped by a straight
// attack and an exponential decay. The recipes themselves are generated into CuelumeRecipes.swift.

import Foundation

/// A finished material for the same cues. A theme changes how a cue sounds, never what it means.
enum CuelumeTheme: String, CaseIterable, Identifiable, Sendable {
  case standard = "default"
  case mech
  case bubble
  case press

  var id: String { rawValue }

  var label: String {
    switch self {
    case .standard: return "Default"
    case .mech: return "Mechanical"
    case .bubble: return "Bubble"
    case .press: return "Press"
    }
  }
}

/// One interface job. Cuelume names cues by what they mean, not how they sound.
enum CuelumeCue: String, CaseIterable, Identifiable, Sendable {
  case tap, type, select, toggle, open, close, success, error, navigate, warning, loading, ready,
    attention, count

  var id: String { rawValue }

  var label: String { rawValue.capitalized }
}

/// How much the action matters. Layers marked `from: .normal` drop out of subtle; `.strong` layers
/// play only when strong.
enum CuelumeEmphasis: Int, Comparable, Sendable {
  case subtle, normal, strong

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CuelumeFilter: Sendable {
  case lowpass, highpass, bandpass
}

struct CuelumeLayer: Equatable, Sendable {
  enum Source: Equatable, Sendable {
    case tone
    /// Web Audio reads a bandpass Q as a plain ratio and a lowpass or highpass Q in dB.
    case noise(CuelumeFilter, q: Double)
  }

  var source: Source
  /// A tone's pitch, or a noise layer's filter frequency, in Hz.
  var frequency: Double
  /// Fade-in time, in seconds.
  var attack: Double
  /// Ring time: the seconds the layer takes to fall 60 dB once the attack ends.
  var decay: Double
  /// Peak level reached at the end of the attack.
  var peak: Double
  /// Seconds after the trigger that this layer starts.
  var offset: Double = 0
  /// If set, the pitch (or filter) glides exponentially to this value.
  var glideTo: Double?
  /// How long the glide takes. Defaults to attack + decay.
  var glideTime: Double?
  /// The lowest emphasis this layer plays at.
  var from: CuelumeEmphasis = .subtle

  static func tone(
    _ frequency: Double, attack: Double, decay: Double, peak: Double, offset: Double = 0,
    glideTo: Double? = nil, glideTime: Double? = nil, from: CuelumeEmphasis = .subtle
  ) -> CuelumeLayer {
    CuelumeLayer(
      source: .tone, frequency: frequency, attack: attack, decay: decay, peak: peak, offset: offset,
      glideTo: glideTo, glideTime: glideTime, from: from)
  }

  /// Web Audio's BiquadFilterNode defaults Q to 1.
  static func noise(
    _ filter: CuelumeFilter, _ frequency: Double, q: Double = 1, attack: Double, decay: Double,
    peak: Double, offset: Double = 0, glideTo: Double? = nil, glideTime: Double? = nil,
    from: CuelumeEmphasis = .subtle
  ) -> CuelumeLayer {
    CuelumeLayer(
      source: .noise(filter, q: q), frequency: frequency, attack: attack, decay: decay, peak: peak,
      offset: offset, glideTo: glideTo, glideTime: glideTime, from: from)
  }
}

/// Per-play randomness, as fractions: each play's pitch and level move by up to ± these.
struct CuelumeVariation: Equatable, Sendable {
  var pitch: Double
  var level: Double
}

struct CuelumeRecipe: Equatable, Sendable {
  var masterGain: Double
  var layers: [CuelumeLayer]
  /// What the gesture sounds like as it lets go, played `CuelumeSynth.releaseGap` after the press.
  var release: [CuelumeLayer] = []
  /// How strongly this cue rings into the shared room, as a multiple of every cue's faint send.
  var room: Double = 1
  var vary: CuelumeVariation?
}
