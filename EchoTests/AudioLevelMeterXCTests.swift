import Combine
import XCTest

@testable import Echo

@MainActor
final class AudioLevelMeterXCTests: XCTestCase {
  func testWindowRightAlignsAndZeroPadsShortHistory() {
    XCTAssertEqual(
      AudioLevelMeter.window(of: [0.1, 0.4, 0.2], length: 5),
      [0, 0, 0.1, 0.4, 0.2]
    )
    XCTAssertEqual(AudioLevelMeter.window(of: [0.1, 0.2, 0.3], length: 2), [0.2, 0.3])
    XCTAssertEqual(AudioLevelMeter.window(of: [0.1], length: 0), [])
  }

  func testSamplesStartEmptyAndRightAlignTheNewestReading() {
    let meter = AudioLevelMeter()
    XCTAssertEqual(meter.samples, [])

    meter.append(0.1)
    meter.append(0.4)

    XCTAssertEqual(meter.samples.count, AudioLevelMeter.historyLength)
    XCTAssertEqual(Array(meter.samples.suffix(2)), [0.1, 0.4])
    XCTAssertTrue(meter.samples.dropLast(2).allSatisfy { $0 == 0 })
  }

  func testHistoryIsBoundedToTheMostRecentReadings() {
    let meter = AudioLevelMeter()
    let readings = (0..<(AudioLevelMeter.historyLength + 8)).map { Float($0) / 100 }

    readings.forEach(meter.append)

    XCTAssertEqual(meter.samples, Array(readings.suffix(AudioLevelMeter.historyLength)))
  }

  func testEachReadingPublishesExactlyOnce() {
    let meter = AudioLevelMeter()
    var changeCount = 0
    let subscription = meter.objectWillChange.sink { changeCount += 1 }
    defer { subscription.cancel() }

    meter.append(0.2)
    meter.append(0.5)
    meter.append(0.3)

    XCTAssertEqual(changeCount, 3)
  }

  func testResetClearsSamplesAndOnlyPublishesWhenThereWasSomethingToClear() {
    let meter = AudioLevelMeter()
    var changeCount = 0
    let subscription = meter.objectWillChange.sink { changeCount += 1 }
    defer { subscription.cancel() }

    meter.reset()
    XCTAssertEqual(changeCount, 0)

    meter.append(0.6)
    meter.reset()

    XCTAssertEqual(meter.samples, [])
    XCTAssertEqual(changeCount, 2)

    // History starts over after a reset rather than resuming the old window
    meter.append(0.7)
    XCTAssertEqual(Array(meter.samples.suffix(2)), [0, 0.7])
  }
}
