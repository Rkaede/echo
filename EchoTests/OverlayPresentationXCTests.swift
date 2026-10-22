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

  func testNotesModeDetailCountsEntriesAndFlagsMissingScreenshots() {
    XCTAssertEqual(
      OverlayPresentation.notesModeDetail(entryCount: 0, screenshotsAvailable: true),
      "Press Fn to add an entry"
    )
    XCTAssertEqual(
      OverlayPresentation.notesModeDetail(entryCount: 1, screenshotsAvailable: true),
      "1 entry"
    )
    XCTAssertEqual(
      OverlayPresentation.notesModeDetail(entryCount: 3, screenshotsAvailable: true),
      "3 entries"
    )
    XCTAssertEqual(
      OverlayPresentation.notesModeDetail(entryCount: 0, screenshotsAvailable: false),
      "Screenshots off"
    )
    XCTAssertEqual(
      OverlayPresentation.notesModeDetail(entryCount: 2, screenshotsAvailable: false),
      "2 entries, no screenshots"
    )
  }
}
