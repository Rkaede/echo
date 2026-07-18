import XCTest

@testable import Echo

final class TranscriptionServiceXCTests: XCTestCase {
  func testRecordingStartSoundSettleDelayOnlyAppliesToWirelessInputs() {
    XCTAssertEqual(
      TranscriptionService.recordingStartSoundSettleDelayNanoseconds(inputIsWireless: true),
      250_000_000
    )
    XCTAssertNil(
      TranscriptionService.recordingStartSoundSettleDelayNanoseconds(inputIsWireless: false)
    )
  }
}
