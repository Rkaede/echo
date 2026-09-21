import XCTest

@testable import Echo

final class SpeechGateXCTests: XCTestCase {

  // MARK: - Helpers

  private func signal(
    peak: Float = -12,
    voicedFrames: Int = 20,
    duration: TimeInterval = 3
  ) -> RecordingSignal {
    RecordingSignal(
      peakPowerDecibels: peak,
      voicedFrameCount: voicedFrames,
      duration: duration
    )
  }

  private func segment(
    id: Int = 0,
    text: String = "Thank you.",
    noSpeechProbability: Double?,
    averageLogProbability: Double?
  ) -> TranscriptionResult.Segment {
    TranscriptionResult.Segment(
      id: id,
      start: 0,
      end: 1,
      text: text,
      averageLogProbability: averageLogProbability,
      noSpeechProbability: noSpeechProbability,
      compressionRatio: nil
    )
  }

  // MARK: - Gate B: duration

  func testRecordingShorterThanMinimumIsRejectedAsTooShort() {
    let decision = SpeechGate.preflightDecision(for: signal(duration: 0.2))
    XCTAssertEqual(decision, .reject(.tooShort))
  }

  func testDurationGateTakesPrecedenceOverLoudness() {
    // A very short but loud blip is still a mis-tapped shortcut, not an utterance.
    let decision = SpeechGate.preflightDecision(for: signal(peak: -5, duration: 0.1))
    XCTAssertEqual(decision, .reject(.tooShort))
  }

  func testRecordingAtTheDurationBoundaryIsAccepted() {
    let decision = SpeechGate.preflightDecision(
      for: signal(duration: SpeechGate.minimumDuration)
    )
    XCTAssertEqual(decision, .transcribe)
  }

  // MARK: - Gate A: loudness

  func testTotallySilentRecordingIsRejected() {
    let decision = SpeechGate.preflightDecision(
      for: signal(peak: RecordingSignal.silenceFloorDecibels, voicedFrames: 0)
    )
    XCTAssertEqual(decision, .reject(.silent))
  }

  func testRecordingBelowTheSpeechFloorIsRejected() {
    let decision = SpeechGate.preflightDecision(for: signal(peak: -55, voicedFrames: 0))
    XCTAssertEqual(decision, .reject(.silent))
  }

  func testSingleLoudFrameIsRejectedAsStrayNoise() {
    // One frame above the floor is a click or a key press, not speech.
    let decision = SpeechGate.preflightDecision(for: signal(peak: -20, voicedFrames: 1))
    XCTAssertEqual(decision, .reject(.silent))
  }

  func testNormalSpeechIsAccepted() {
    let decision = SpeechGate.preflightDecision(for: signal(peak: -18, voicedFrames: 40))
    XCTAssertEqual(decision, .transcribe)
  }

  func testQuietButAudibleSpeechIsAccepted() {
    // Low-gain mics should still get through; content judgement is left to the model.
    let decision = SpeechGate.preflightDecision(for: signal(peak: -40, voicedFrames: 12))
    XCTAssertEqual(decision, .transcribe)
  }

  func testPeakExactlyAtTheFloorIsRejected() {
    let decision = SpeechGate.preflightDecision(
      for: signal(peak: SpeechGate.speechFloorDecibels, voicedFrames: 10)
    )
    XCTAssertEqual(decision, .reject(.silent))
  }

  func testVoicedFrameDetectionMatchesTheFloor() {
    XCTAssertTrue(SpeechGate.isVoicedFrame(peakPowerDecibels: -30))
    XCTAssertFalse(SpeechGate.isVoicedFrame(peakPowerDecibels: -50))
    XCTAssertFalse(
      SpeechGate.isVoicedFrame(peakPowerDecibels: SpeechGate.speechFloorDecibels)
    )
  }

  // MARK: - Gate C: model confidence

  func testSegmentsAllFlaggedAsNonSpeechAreRejected() {
    let segments = [
      segment(id: 0, noSpeechProbability: 0.92, averageLogProbability: -1.4),
      segment(id: 1, noSpeechProbability: 0.81, averageLogProbability: -1.1),
    ]
    XCTAssertEqual(
      SpeechGate.transcriptDecision(segments: segments),
      .reject(.noSpeechInTranscript)
    )
  }

  func testOneConfidentSegmentKeepsTheWholeResult() {
    let segments = [
      segment(id: 0, noSpeechProbability: 0.92, averageLogProbability: -1.4),
      segment(id: 1, text: "real speech", noSpeechProbability: 0.02, averageLogProbability: -0.3),
    ]
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: segments), .transcribe)
  }

  func testBothConfidenceSignalsMustAgreeToReject() {
    // High no-speech probability alone is common on short utterances.
    let highNoSpeechOnly = [segment(noSpeechProbability: 0.95, averageLogProbability: -0.2)]
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: highNoSpeechOnly), .transcribe)

    // Low log probability alone is common on unusual but genuine speech.
    let lowLogProbOnly = [segment(noSpeechProbability: 0.1, averageLogProbability: -2.5)]
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: lowLogProbOnly), .transcribe)
  }

  func testMissingConfidenceFieldsAreTreatedAsUnjudgeable() {
    let segments = [segment(noSpeechProbability: nil, averageLogProbability: nil)]
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: segments), .transcribe)
  }

  func testAbsentOrEmptySegmentsFallThroughToExistingHandling() {
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: nil), .transcribe)
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: []), .transcribe)
  }

  // MARK: - Decoding

  func testSegmentDecodesWhisperConfidenceFieldsFromSnakeCase() throws {
    let json = """
      {
        "text": " Thank you.",
        "language": "english",
        "duration": 1.2,
        "segments": [
          {
            "id": 0,
            "seek": 0,
            "start": 0.0,
            "end": 1.2,
            "text": " Thank you.",
            "tokens": [50364, 1912, 291, 13],
            "temperature": 0.0,
            "avg_logprob": -1.23,
            "compression_ratio": 0.75,
            "no_speech_prob": 0.87
          }
        ]
      }
      """

    let result = try JSONDecoder().decode(
      TranscriptionResult.self,
      from: Data(json.utf8)
    )

    let decoded = try XCTUnwrap(result.segments?.first)
    XCTAssertEqual(decoded.averageLogProbability, -1.23)
    XCTAssertEqual(decoded.noSpeechProbability, 0.87)
    XCTAssertEqual(decoded.compressionRatio, 0.75)

    // The realistic silence hallucination this whole feature exists to stop.
    XCTAssertEqual(
      SpeechGate.transcriptDecision(segments: result.segments),
      .reject(.noSpeechInTranscript)
    )
  }

  func testSegmentDecodesWhenConfidenceFieldsAreAbsent() throws {
    let json = """
      {
        "text": "hello",
        "segments": [
          { "id": 0, "start": 0.0, "end": 0.5, "text": "hello" }
        ]
      }
      """

    let result = try JSONDecoder().decode(
      TranscriptionResult.self,
      from: Data(json.utf8)
    )

    let decoded = try XCTUnwrap(result.segments?.first)
    XCTAssertEqual(decoded.text, "hello")
    XCTAssertNil(decoded.averageLogProbability)
    XCTAssertNil(decoded.noSpeechProbability)
  }
}
