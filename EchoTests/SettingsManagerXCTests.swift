import XCTest

@testable import Echo

final class SettingsManagerXCTests: XCTestCase {
  func testIdleTimeoutPresetsSpanThirtySecondsToThirtyMinutes() {
    XCTAssertEqual(SettingsManager.audioEngineIdleTimeoutPresets.first, 30)
    XCTAssertEqual(SettingsManager.audioEngineIdleTimeoutPresets.last, 1800)
    XCTAssertEqual(
      SettingsManager.audioEngineIdleTimeoutPresets,
      SettingsManager.audioEngineIdleTimeoutPresets.sorted()
    )
  }

  func testClampedIdleTimeoutBoundsOutOfRangeValues() {
    XCTAssertEqual(SettingsManager.clampedIdleTimeoutSeconds(10), 30)
    XCTAssertEqual(SettingsManager.clampedIdleTimeoutSeconds(30), 30)
    XCTAssertEqual(SettingsManager.clampedIdleTimeoutSeconds(240), 240)
    XCTAssertEqual(SettingsManager.clampedIdleTimeoutSeconds(1800), 1800)
    XCTAssertEqual(SettingsManager.clampedIdleTimeoutSeconds(7200), 1800)
  }

  func testIdleTimeoutPresetIndexSnapsToClosestStop() {
    XCTAssertEqual(SettingsManager.idleTimeoutPresetIndex(closestTo: 10), 0)
    XCTAssertEqual(SettingsManager.idleTimeoutPresetIndex(closestTo: 60), 1)
    XCTAssertEqual(SettingsManager.idleTimeoutPresetIndex(closestTo: 100), 2)
    XCTAssertEqual(SettingsManager.idleTimeoutPresetIndex(closestTo: 400), 4)
    XCTAssertEqual(SettingsManager.idleTimeoutPresetIndex(closestTo: 10_000), 8)
  }

  func testFormattedIdleTimeoutUsesSecondsBelowOneMinute() {
    XCTAssertEqual(SettingsManager.formattedIdleTimeout(seconds: 30), "30 sec")
    XCTAssertEqual(SettingsManager.formattedIdleTimeout(seconds: 60), "1 min")
    XCTAssertEqual(SettingsManager.formattedIdleTimeout(seconds: 90), "1 min 30 sec")
    XCTAssertEqual(SettingsManager.formattedIdleTimeout(seconds: 300), "5 min")
    XCTAssertEqual(SettingsManager.formattedIdleTimeout(seconds: 1800), "30 min")
  }
}
