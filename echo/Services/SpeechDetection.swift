import Foundation

/// What the microphone actually picked up during a recording.
///
/// Gathered from `AVAudioRecorder` metering while recording, and read back once the
/// recording stops so the transcription pipeline can decide whether the audio is worth
/// uploading.
struct RecordingSignal: Equatable {
  /// The level `AVAudioRecorder` reports when it has heard nothing at all.
  static let silenceFloorDecibels: Float = -160

  /// Loudest peak observed across the whole recording, in dBFS.
  let peakPowerDecibels: Float

  /// Metering frames whose peak cleared `SpeechGate.speechFloorDecibels`.
  let voicedFrameCount: Int

  /// Wall-clock length of the recording.
  let duration: TimeInterval
}

enum SpeechRejectionReason: String, Equatable {
  case tooShort
  case silent
  case noSpeechInTranscript

  var logDescription: String {
    switch self {
    case .tooShort:
      return "recording was too short to contain speech"
    case .silent:
      return "recording never rose above the speech floor"
    case .noSpeechInTranscript:
      return "every transcript segment was flagged as non-speech"
    }
  }
}

enum SpeechGateDecision: Equatable {
  case transcribe
  case reject(SpeechRejectionReason)
}

/// Guards against Whisper's habit of inventing text when it is handed silence.
///
/// Whisper was trained on captioned video, so near-silent audio reliably produces stock
/// phrases — "Thank you.", "Thanks for watching!", "you" — which then get pasted into
/// whatever app happens to be focused. Three cheap checks catch it:
///
///   1. Duration — an accidental double-tap of the record shortcut is too short to speak into.
///   2. Loudness — if nothing ever cleared the speech floor there is nothing to transcribe,
///      and the upload can be skipped entirely.
///   3. The model's own confidence, once the response comes back. This is the only one of
///      the three that catches a noisy room, where a fan or typing clears the loudness gate
///      but nobody actually spoke.
enum SpeechGate {
  /// Recordings shorter than this cannot hold a usable utterance and are almost always a
  /// mis-tapped shortcut.
  nonisolated static let minimumDuration: TimeInterval = 0.35

  /// Peak level, in dBFS, that a metering frame must exceed to count as speech.
  ///
  /// Deliberately well below conversational level — speech peaks around -20 dBFS even on a
  /// quiet mic — because input gain varies enormously between built-in mics, AirPods and USB
  /// interfaces. The aim is to reject only unambiguous silence and leave anything borderline
  /// for `transcriptDecision`, which judges content rather than volume.
  nonisolated static let speechFloorDecibels: Float = -45

  /// Metering runs every 50ms, so this is 100ms of sound above the floor. A single stray
  /// frame is usually a click, a key press, or the recording-start chime bleeding in.
  nonisolated static let minimumVoicedFrames = 2

  /// Whisper's own thresholds for "this segment is not speech", matching the defaults used
  /// inside openai-whisper's decoding loop.
  nonisolated static let noSpeechProbabilityThreshold = 0.6
  nonisolated static let averageLogProbabilityThreshold = -1.0

  /// Runs before the upload, on metering data gathered during the recording.
  nonisolated static func preflightDecision(for signal: RecordingSignal) -> SpeechGateDecision {
    if signal.duration < minimumDuration {
      return .reject(.tooShort)
    }

    if signal.peakPowerDecibels <= speechFloorDecibels
      || signal.voicedFrameCount < minimumVoicedFrames
    {
      return .reject(.silent)
    }

    return .transcribe
  }

  nonisolated static func isVoicedFrame(peakPowerDecibels: Float) -> Bool {
    peakPowerDecibels > speechFloorDecibels
  }

  /// Runs on the API response.
  ///
  /// Rejects only when every segment the model returned is flagged as non-speech, so one
  /// confident segment is enough to keep the whole result.
  nonisolated static func transcriptDecision(
    segments: [TranscriptionResult.Segment]?
  ) -> SpeechGateDecision {
    guard let segments, !segments.isEmpty else {
      // Not every model or response format returns segment metadata. With nothing to judge,
      // defer to the existing empty-text handling rather than guessing.
      return .transcribe
    }

    return segments.allSatisfy(isNonSpeech) ? .reject(.noSpeechInTranscript) : .transcribe
  }

  nonisolated static func isNonSpeech(_ segment: TranscriptionResult.Segment) -> Bool {
    // Both signals have to agree. `no_speech_prob` alone runs high on short utterances, and
    // `avg_logprob` alone runs low on unusual but genuine speech.
    guard let noSpeechProbability = segment.noSpeechProbability,
      let averageLogProbability = segment.averageLogProbability
    else {
      return false
    }

    return noSpeechProbability > noSpeechProbabilityThreshold
      && averageLogProbability < averageLogProbabilityThreshold
  }
}
