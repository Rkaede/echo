import AVFoundation
import XCTest

@testable import Echo

private actor Counter {
  private(set) var value = 0
  func increment() { value += 1 }
}

final class LongDictationXCTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LongDictationXCTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Splitting recordings

  func testShortRecordingsAreNotCut() {
    let cuts = LongRecordingSplitter.cutFrames(totalFrames: 600 * 16_000, sampleRate: 16_000) {
      _ in XCTFail("no search expected"); return 0
    }
    XCTAssertEqual(cuts, [])
  }

  func testAnHourIsCutIntoPartsUnderTheLimitAtTheQuietestPoint() {
    let sampleRate = 16_000.0
    let total = Int(3_600 * sampleRate)
    var searched: [Range<Int>] = []
    let cuts = LongRecordingSplitter.cutFrames(totalFrames: total, sampleRate: sampleRate) {
      range in
      searched.append(range)
      return range.lowerBound + 1_000  // pretend the pause is just inside the window
    }

    XCTAssertEqual(cuts.count, 6)
    let bounds = zip([0] + cuts, cuts + [total]).map { $1 - $0 }
    XCTAssertTrue(bounds.allSatisfy { Double($0) / sampleRate <= LongRecordingSplitter.maxPartSeconds })
    // Each search covers the 30 s before the part would hit the limit.
    XCTAssertEqual(searched.first, Int(570 * sampleRate)..<Int(600 * sampleRate))
  }

  func testCutsStayInsideTheSearchWindow() {
    // Parts of at most 200 frames, searched over their last 50. A nonsense answer is clamped
    // to the window, so every part still makes progress.
    let cuts = LongRecordingSplitter.cutFrames(
      totalFrames: 1_000, sampleRate: 100, maxPartSeconds: 2, searchSeconds: 0.5
    ) { _ in -50 }
    XCTAssertEqual(cuts, [150, 300, 450, 600, 750, 900])
  }

  func testSplitWritesPartsThatCutInSilence() throws {
    // 5 s at 16 kHz: speech-like tone with silent gaps at 1.6–1.9 s and 3.4–3.7 s.
    let url = directory.appendingPathComponent("long.wav")
    try writeTone(to: url, seconds: 5, silences: [1.6..<1.9, 3.4..<3.7])

    let parts = try LongRecordingSplitter.split(url, maxPartSeconds: 2, searchSeconds: 0.5)

    XCTAssertEqual(parts.count, 3)
    XCTAssertEqual(parts.map(\.duration).reduce(0, +), 5, accuracy: 0.01)
    XCTAssertTrue(parts.allSatisfy { $0.duration <= 2.0001 })
    // The first cut falls in the first silent gap, the second in the next.
    XCTAssertTrue((1.6..<1.9).contains(parts[0].duration))
    XCTAssertTrue((3.4..<3.7).contains(parts[0].duration + parts[1].duration))
    for part in parts {
      let file = try AVAudioFile(forReading: part.url)
      XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
      XCTAssertEqual(file.fileFormat.channelCount, 1)
    }
  }

  func testSplitWritesItsPartsIntoTheGivenFolder() throws {
    // A retried failed recording is split into the temp folder, not beside itself, where the
    // parts would be listed as failed recordings.
    let kept = directory.appendingPathComponent("failed", isDirectory: true)
    let temp = directory.appendingPathComponent("temp", isDirectory: true)
    try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
    let url = kept.appendingPathComponent("recording-20261123-101500.wav")
    try writeTone(to: url, seconds: 5, silences: [1.6..<1.9, 3.4..<3.7])

    let parts = try LongRecordingSplitter.split(url, into: temp, maxPartSeconds: 2, searchSeconds: 0.5)

    XCTAssertEqual(parts.count, 3)
    XCTAssertTrue(parts.allSatisfy { $0.url.deletingLastPathComponent().path == temp.path })
    XCTAssertTrue(parts.allSatisfy { TempFileManager.isRecordingFile($0.url) }, "left-over parts must be cleaned up")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: kept.path), [url.lastPathComponent])
  }

  func testSplitReturnsTheOriginalWhenShortEnough() throws {
    let url = directory.appendingPathComponent("short.wav")
    try writeTone(to: url, seconds: 1, silences: [])
    let parts = try LongRecordingSplitter.split(url, maxPartSeconds: 2)
    XCTAssertEqual(parts.map(\.url), [url])
  }

  // MARK: - Joining transcribed parts

  func testCombineJoinsTextOffsetsSegmentsAndDropsSilentParts() {
    let speech = segment(start: 0, end: 4, noSpeech: 0.01, logProb: -0.2)
    let silence = segment(start: 0, end: 5, noSpeech: 0.9, logProb: -1.5)
    let parts = [
      part("First part.", segments: [speech]),
      part("Thank you.", segments: [silence]),  // Whisper's invention over silence
      part(" Third part. ", segments: [speech]),
    ]

    let (combined, model) = TranscriptionService.combine(
      parts, models: ["whisper-large-v3-turbo", "whisper-large-v3-turbo", "microsoft/mai-transcribe-2"],
      partDurations: [600, 600, 300])

    XCTAssertEqual(combined.result.text, "First part. Third part.")
    XCTAssertEqual(combined.result.segments?.map(\.start), [0, 600, 1_200])
    XCTAssertEqual(combined.result.duration, 1_500)
    XCTAssertEqual(model, "whisper-large-v3-turbo + microsoft/mai-transcribe-2")
    XCTAssertEqual(combined.uploadTime, 3)
  }

  func testCombineKeepsSilentSegmentsSoAnAllSilentRecordingIsRejected() {
    let silence = segment(start: 0, end: 5, noSpeech: 0.9, logProb: -1.5)
    let (combined, _) = TranscriptionService.combine(
      [part("Thank you.", segments: [silence]), part("Bye.", segments: [silence])],
      models: ["m", "m"], partDurations: [600, 600])

    XCTAssertEqual(combined.result.text, "")
    guard case .reject = SpeechGate.transcriptDecision(segments: combined.result.segments) else {
      return XCTFail("an all-silent recording should still be rejected")
    }
  }

  func testCombineKeepsTextFromPartsWithoutSegmentsWhenAFallbackPartIsSilent() {
    // MAI-Transcribe-2 on OpenRouter returns no segments. The last part fell back to Whisper
    // on Groq, which flagged its quiet tail as non-speech.
    let silence = segment(start: 0, end: 5, noSpeech: 0.9, logProb: -1.5)
    let (combined, _) = TranscriptionService.combine(
      [
        part("First part.", segments: nil),
        part("Second part.", segments: nil),
        part("Thank you.", segments: [silence]),
      ],
      models: ["microsoft/mai-transcribe-2", "microsoft/mai-transcribe-2", "whisper-large-v3-turbo"],
      partDurations: [600, 600, 300])

    XCTAssertEqual(combined.result.text, "First part. Second part.")
    XCTAssertEqual(SpeechGate.transcriptDecision(segments: combined.result.segments), .transcribe)
  }

  // MARK: - Temporary file clean-up

  func testARecordingStillBeingWrittenIsNotOldHoweverLongAgoItStarted() {
    let now = Date()
    let started = now.addingTimeInterval(-75 * 60)

    // 75 minutes into a dictation: created long ago, written a second ago.
    XCTAssertEqual(
      TempFileManager.age(
        creationDate: started, modificationDate: now.addingTimeInterval(-1), now: now),
      1)
    // An orphan from an earlier session was last written long ago too.
    XCTAssertEqual(
      TempFileManager.age(creationDate: started, modificationDate: started, now: now), 75 * 60)
    XCTAssertEqual(TempFileManager.age(creationDate: started, modificationDate: nil, now: now), 75 * 60)
    XCTAssertNil(TempFileManager.age(creationDate: nil, modificationDate: nil, now: now))
  }

  // MARK: - Cleaning long transcripts in sections

  func testShortTranscriptsAndPlaceholderPromptsAreSentWhole() {
    let short = words(100)
    XCTAssertEqual(PostProcessingPrompt.sections(of: short, template: "Clean up."), [short])

    let long = sentences(200, wordsEach: 10)
    XCTAssertEqual(
      PostProcessingPrompt.sections(of: long, template: "Write an email: {{TRANSCRIPTION}}"),
      [long])
  }

  func testLongTranscriptsSplitEvenlyAtSentenceEnds() {
    let text = sentences(70, wordsEach: 10)  // 700 words
    let sections = PostProcessingPrompt.sections(of: text, template: "Clean up.")

    XCTAssertEqual(sections.count, 2)
    XCTAssertTrue(sections.allSatisfy { $0.hasSuffix(".") })
    XCTAssertEqual(sections.map(wordCount), [350, 350])
    XCTAssertEqual(sections.joined(separator: " "), text)
  }

  func testUnpunctuatedSpeechIsCutByWordCount() {
    let text = words(1_500)
    let sections = PostProcessingPrompt.sections(of: text, template: "Clean up.")

    XCTAssertTrue(sections.allSatisfy { wordCount($0) <= PostProcessingPrompt.maxSectionWords })
    XCTAssertEqual(sections.joined(separator: " "), text)
  }

  func testMaxTokensGrowsWithTheText() {
    XCTAssertEqual(PostProcessingPrompt.maxTokens(for: words(100)), 2_048)
    XCTAssertEqual(PostProcessingPrompt.maxTokens(for: words(600)), 2_224)
    XCTAssertEqual(PostProcessingPrompt.maxTokens(for: words(50_000)), 32_768)
  }

  func testSectionsAreCleanedInOrderAndFailuresKeepTheirRawText() async throws {
    let sections = ["one", "two", "three", "four", "five"]
    let result = try await PostProcessingPrompt.cleanUpSections(sections, maxConcurrent: 2) {
      section in
      if section == "three" { throw PostProcessingError.truncated }
      try await Task.sleep(for: .milliseconds(section == "one" ? 30 : 1))
      return section.uppercased()
    }
    XCTAssertEqual(result, "ONE TWO three FOUR FIVE")
  }

  func testCleanUpThrowsWhenEverySectionFails() async {
    do {
      _ = try await PostProcessingPrompt.cleanUpSections(["a", "b"]) { _ in
        throw PostProcessingError.emptyResponse
      }
      XCTFail("expected an error")
    } catch {
      XCTAssertTrue(error is PostProcessingError)
    }
  }

  func testACancelledCleanUpStartsNoMoreSectionsAndThrows() async {
    let started = Counter()
    let task = Task {
      try await PostProcessingPrompt.cleanUpSections(
        ["one", "two", "three", "four", "five", "six"], maxConcurrent: 2
      ) { section in
        await started.increment()
        try await Task.sleep(for: .seconds(30))
        return section
      }
    }
    while await started.value < 2 {
      try? await Task.sleep(for: .milliseconds(5))
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("a cancelled clean-up should throw")
    } catch {
      XCTAssertTrue(error is CancellationError, "\(error)")
    }
    let count = await started.value
    XCTAssertEqual(count, 2, "no section should start after the cancel")
  }

  func testCutOffCleanUpIsReportedNotPasted() throws {
    let cutOff = Data(
      #"{"choices":[{"message":{"role":"assistant","content":"The first half of"},"finish_reason":"length"}]}"#
        .utf8)
    XCTAssertThrowsError(try APIClient.chatContent(from: cutOff)) { error in
      guard case PostProcessingError.truncated = error else {
        return XCTFail("expected .truncated, got \(error)")
      }
    }

    let complete = Data(
      #"{"choices":[{"message":{"role":"assistant","content":" Done. "},"finish_reason":"stop"}]}"#
        .utf8)
    XCTAssertEqual(try APIClient.chatContent(from: complete), "Done.")
  }

  // MARK: - Keeping failed recordings

  @MainActor
  func testFailedRecordingsAreKeptNewestFirstAndPruned() throws {
    let store = FailedRecordingStore(directory: directory.appendingPathComponent("failed"))
    XCTAssertNil(store.latest)

    let recording = directory.appendingPathComponent("rec.wav")
    try Data("audio".utf8).write(to: recording)
    var saved: [URL] = []
    for minute in 0..<5 {
      let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60)
      saved.append(try XCTUnwrap(store.save(recording, at: date)))
    }

    XCTAssertEqual(store.latest, saved.last)
    let kept = try FileManager.default.contentsOfDirectory(atPath: saved[0].deletingLastPathComponent().path)
    XCTAssertEqual(kept.count, FailedRecordingStore.keepCount)
    XCTAssertFalse(FileManager.default.fileExists(atPath: saved[0].path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path), "the original is copied, not moved")

    store.remove(saved[4])
    XCTAssertEqual(store.latest, saved[3])
  }

  // MARK: - Helpers

  private func writeTone(to url: URL, seconds: Double, silences: [Range<Double>]) throws {
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16_000.0,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(
      forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let frames = AVAudioFrameCount(seconds * 16_000)
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
    buffer.frameLength = frames
    let samples = try XCTUnwrap(buffer.floatChannelData?[0])
    for index in 0..<Int(frames) {
      let time = Double(index) / 16_000
      let silent = silences.contains { $0.contains(time) }
      samples[index] = silent ? 0 : Float(0.3 * sin(2 * .pi * 220 * time))
    }
    try file.write(from: buffer)
  }

  private func part(_ text: String, segments: [TranscriptionResult.Segment]?)
    -> TranscriptionResultWithTiming
  {
    TranscriptionResultWithTiming(
      result: TranscriptionResult(text: text, language: "en", duration: nil, segments: segments),
      uploadTime: 1, downloadTime: 0.5, totalNetworkTime: 1.5)
  }

  private func segment(start: Double, end: Double, noSpeech: Double, logProb: Double)
    -> TranscriptionResult.Segment
  {
    TranscriptionResult.Segment(
      id: 0, start: start, end: end, text: "", averageLogProbability: logProb,
      noSpeechProbability: noSpeech, compressionRatio: 1)
  }

  private func words(_ count: Int) -> String {
    (1...count).map { "word\($0)" }.joined(separator: " ")
  }

  private func sentences(_ count: Int, wordsEach: Int) -> String {
    (1...count).map { sentence in
      // Capitalised, as transcripts are: the sentence breaker needs it to see a new sentence.
      (1...wordsEach).map { "S\(sentence)w\($0)" }.joined(separator: " ") + "."
    }.joined(separator: " ")
  }

  private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
  }
}
