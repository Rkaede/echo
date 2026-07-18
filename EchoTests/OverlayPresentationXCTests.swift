import XCTest
@testable import Echo

@MainActor
final class OverlayPresentationXCTests: XCTestCase {
  func testInitiatingRecordingCommunicatesMicPreparation() {
    XCTAssertEqual(
      OverlayPresentation.displayText(
        status: .initiatingRecording,
        currentInputDevice: "Corey's AirPods"
      ),
      "Preparing mic..."
    )
    XCTAssertFalse(OverlayPresentation.shouldShowWaveform(for: .initiatingRecording))
    XCTAssertEqual(
      OverlayPresentation.statusIconName(
        for: .initiatingRecording,
        recordingIconName: "waveform.circle.fill"
      ),
      "clock.circle.fill"
    )
    XCTAssertEqual(OverlayPresentation.statusTone(for: .initiatingRecording), .preparing)
  }

  func testRecordingCommunicatesWhenUserCanSpeak() {
    XCTAssertEqual(
      OverlayPresentation.displayText(
        status: .recording,
        currentInputDevice: "Corey's AirPods"
      ),
      "Speak now"
    )
    XCTAssertTrue(OverlayPresentation.shouldShowWaveform(for: .recording))
    XCTAssertEqual(
      OverlayPresentation.statusIconName(for: .recording, recordingIconName: "waveform.circle.fill"),
      "waveform.circle.fill"
    )
    XCTAssertEqual(OverlayPresentation.statusTone(for: .recording), .recording)
  }

  func testProfileNameOverridesRecordingReadyCue() {
    XCTAssertEqual(
      OverlayPresentation.displayText(
        status: .recording,
        showingProfileName: "Meeting Notes",
        currentInputDevice: "Corey's AirPods"
      ),
      "Meeting Notes"
    )
  }
}
