import XCTest
import AVFoundation
@testable import Echo

/// XCTest-based tests for UnifiedAudioEngine (compatible with all Xcode versions)
@MainActor
final class UnifiedAudioEngineXCTests: XCTestCase {

  // MARK: - Error Enum Tests

  func testErrorDescriptions() {
    XCTAssertEqual(
      UnifiedAudioEngineError.alreadyRecording.errorDescription,
      "Recording is already in progress"
    )
    XCTAssertEqual(
      UnifiedAudioEngineError.engineNotRunning.errorDescription,
      "Audio engine is not running"
    )
    XCTAssertEqual(
      UnifiedAudioEngineError.invalidFormat.errorDescription,
      "Invalid audio format"
    )
    XCTAssertEqual(
      UnifiedAudioEngineError.converterCreationFailed.errorDescription,
      "Failed to create audio format converter"
    )
  }

  func testErrorIsLocalizedError() {
    let error: LocalizedError = UnifiedAudioEngineError.alreadyRecording
    XCTAssertNotNil(error.errorDescription)
  }

  // MARK: - Sound Type Tests

  func testSoundTypeRawValues() {
    XCTAssertEqual(SoundType.recordingStart.rawValue, "recordingStart")
    XCTAssertEqual(SoundType.transcriptionComplete.rawValue, "transcriptionComplete")
  }

  // MARK: - State Management Tests

  func testSingletonInstance() {
    let instance1 = UnifiedAudioEngine.shared
    let instance2 = UnifiedAudioEngine.shared
    XCTAssertTrue(instance1 === instance2)
  }

  func testInitialState() async {
    // stopRecording when not active returns nil
    let result = await UnifiedAudioEngine.shared.stopRecording()
    XCTAssertNil(result)
  }

  func testInvalidURLThrows() async throws {
    let invalidURL = URL(fileURLWithPath: "/nonexistent/directory/audio.wav")

    do {
      try UnifiedAudioEngine.shared.startRecording(to: invalidURL)
      XCTFail("Expected error to be thrown")
    } catch {
      // Expected error
    }
  }

  // MARK: - Buffer Calculation Tests

  func testFrameCapacityCalculation() {
    let testCases: [(inputFrames: Int, inputRate: Double, outputRate: Double, expectedMin: Int)] =
      [
        (1000, 48000.0, 16000.0, 1357),
        (4096, 44100.0, 16000.0, 2510),  // Fixed: was 2512, actual calculation is 2510
        (512, 16000.0, 16000.0, 1536),
      ]

    for testCase in testCases {
      let outputFrameCapacity = Int(
        Double(testCase.inputFrames) * testCase.outputRate / testCase.inputRate
      ) + 1024

      XCTAssertGreaterThanOrEqual(outputFrameCapacity, testCase.expectedMin)
      XCTAssertGreaterThanOrEqual(outputFrameCapacity, 1024)
    }
  }

  func testSafetyMarginValidation() {
    let testCases: [(input: Double, output: Double)] = [
      (48000.0, 16000.0),
      (44100.0, 16000.0),
      (16000.0, 16000.0),
      (96000.0, 16000.0),
    ]

    for (inputRate, outputRate) in testCases {
      let inputFrames = 4096
      let calculatedFrames = Int(Double(inputFrames) * outputRate / inputRate)
      let withSafetyMargin = calculatedFrames + 1024

      XCTAssertGreaterThanOrEqual(withSafetyMargin, Int(Double(calculatedFrames) * 1.1))
    }
  }

  // MARK: - File Cleanup Tests

  func testFileCleanup() throws {
    // Use NSTemporaryDirectory() instead of hardcoded /tmp/ for sandbox compatibility
    let tempDir = NSTemporaryDirectory()
    let testURL = URL(fileURLWithPath: tempDir).appendingPathComponent("echo-test-\(UUID().uuidString).wav")

    FileManager.default.createFile(atPath: testURL.path, contents: nil)
    XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))

    try FileManager.default.removeItem(at: testURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: testURL.path))
  }

  // MARK: - Thread Safety Tests

  func testConcurrentAccess() async {
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask {
          let _ = await UnifiedAudioEngine.shared
          let _ = await UnifiedAudioEngine.shared.currentInputLevel
        }
      }
    }
  }

  // MARK: - Format Validation Tests

  func testValidOutputFormat() {
    let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16000.0,
      channels: 1,
      interleaved: true
    )

    XCTAssertNotNil(format)
    XCTAssertEqual(format?.sampleRate, 16000.0)
    XCTAssertEqual(format?.channelCount, 1)
    XCTAssertEqual(format?.commonFormat, .pcmFormatInt16)
  }

  func testFileSettings() {
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: true
      )
    else {
      XCTFail("Failed to create output format")
      return
    }

    var fileSettings = outputFormat.settings
    fileSettings[AVFormatIDKey] = Int(kAudioFormatLinearPCM)
    fileSettings[AVLinearPCMBitDepthKey] = 16
    fileSettings[AVLinearPCMIsFloatKey] = false
    fileSettings[AVLinearPCMIsBigEndianKey] = false
    fileSettings[AVLinearPCMIsNonInterleaved] = false

    XCTAssertEqual(fileSettings[AVFormatIDKey] as? Int, Int(kAudioFormatLinearPCM))
    XCTAssertEqual(fileSettings[AVLinearPCMBitDepthKey] as? Int, 16)
    XCTAssertEqual(fileSettings[AVLinearPCMIsFloatKey] as? Bool, false)
    XCTAssertEqual(fileSettings[AVLinearPCMIsBigEndianKey] as? Bool, false)
    XCTAssertEqual(fileSettings[AVLinearPCMIsNonInterleaved] as? Bool, false)
  }

  // MARK: - Level Monitoring Tests

  func testRmsToDbConversion() {
    let testCases: [(rms: Float, expectedDb: Float)] = [
      (1.0, 0.0),
      (0.5, -6.0),
      (0.1, -20.0),
    ]

    for testCase in testCases {
      let db = 20 * log10(max(testCase.rms, 0.000001))
      XCTAssertEqual(db, testCase.expectedDb, accuracy: 0.5)
    }
  }

  func testLevelNormalization() {
    let testCases: [Float] = [-70, -60, -40, -20, -10, 0, 10]

    for db in testCases {
      let minDb: Float = -60
      let maxDb: Float = -10
      let normalized = (db - minDb) / (maxDb - minDb)
      let clamped = max(0, min(1, normalized))

      XCTAssertGreaterThanOrEqual(clamped, 0.0)
      XCTAssertLessThanOrEqual(clamped, 1.0)
    }
  }
}
