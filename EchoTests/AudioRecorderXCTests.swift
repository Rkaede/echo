import AVFoundation
import XCTest
@testable import Echo

@MainActor
final class AudioRecorderXCTests: XCTestCase {
  func testPreferredInputDeviceBecomesAudioRecorderCaptureRoute() {
    let external = AudioInputDevice(
      uid: "BuiltInHeadphoneInputDevice",
      name: "External Microphone",
      deviceID: AudioDeviceID(123)
    )
    let elgato = AudioInputDevice(
      uid: "AppleUSBAudioEngine:Elgato Systems:Elgato Wave:3:A017A52210MU90:2,1",
      name: "Elgato Wave:3",
      deviceID: AudioDeviceID(113)
    )

    let route = AudioRecorder.audioRecorderCaptureRoute(
      resolvedSelection: AudioInputDeviceSelection(device: elgato, source: .preferred),
      defaultInputDevice: external
    )

    XCTAssertEqual(route.captureDevice, elgato)
    XCTAssertEqual(route.deviceToMakeDefault, elgato)
    XCTAssertEqual(route.deviceToRestore, external)
  }

  func testUnavailablePreferredInputFallsBackToSystemDefaultCaptureRoute() {
    let external = AudioInputDevice(
      uid: "BuiltInHeadphoneInputDevice",
      name: "External Microphone",
      deviceID: AudioDeviceID(123)
    )

    let route = AudioRecorder.audioRecorderCaptureRoute(
      resolvedSelection: AudioInputDeviceSelection(device: external, source: .systemDefault),
      defaultInputDevice: external
    )

    XCTAssertEqual(route.captureDevice, external)
    XCTAssertNil(route.deviceToMakeDefault)
    XCTAssertNil(route.deviceToRestore)
  }

  func testFallbackInputDeviceBecomesAudioRecorderCaptureRoute() {
    let builtIn = AudioInputDevice(
      uid: "BuiltInMicrophoneDevice",
      name: "MacBook Microphone",
      deviceID: AudioDeviceID(456)
    )
    let fallback = AudioInputDevice(
      uid: "fallback-mic",
      name: "Fallback Microphone",
      deviceID: AudioDeviceID(789)
    )

    let route = AudioRecorder.audioRecorderCaptureRoute(
      resolvedSelection: AudioInputDeviceSelection(device: fallback, source: .fallback),
      defaultInputDevice: builtIn
    )

    XCTAssertEqual(route.captureDevice, fallback)
    XCTAssertEqual(route.deviceToMakeDefault, fallback)
    XCTAssertEqual(route.deviceToRestore, builtIn)
  }

  func testDefaultInputDevicesUseAudioRecorderCapture() {
    let devices = [
      AudioInputDevice(
        uid: "BuiltInHeadphoneInputDevice",
        name: "External Microphone",
        deviceID: AudioDeviceID(123)
      ),
      AudioInputDevice(
        uid: "BuiltInMicrophoneDevice",
        name: "MacBook Microphone",
        deviceID: AudioDeviceID(456)
      ),
      AudioInputDevice(
        uid: "AppleUSBAudioEngine:Elgato Systems:Elgato Wave:3:A017A52210MU90:2,1",
        name: "Elgato Wave:3",
        deviceID: AudioDeviceID(113)
      ),
    ]

    for device in devices {
      XCTAssertTrue(AudioRecorder.shouldUseAudioRecorderCapture(defaultInputDevice: device))
    }
  }

  func testLegacyMeterLevelNormalization() {
    XCTAssertEqual(AudioRecorder.normalizedLegacyMeterLevel(averagePower: -80), 0)
    XCTAssertEqual(AudioRecorder.normalizedLegacyMeterLevel(averagePower: 0), 1)
    XCTAssertEqual(
      AudioRecorder.normalizedLegacyMeterLevel(averagePower: -20),
      0.395,
      accuracy: 0.001
    )
    XCTAssertLessThan(AudioRecorder.normalizedLegacyMeterLevel(averagePower: -10), 0.8)
  }

  func testMeteringCadenceReportsMeanAndMaxTickInterval() {
    var cadence = MeteringCadence()
    XCTAssertNil(cadence.meanInterval)

    cadence.recordTick(at: 10.000)
    XCTAssertNil(cadence.meanInterval, "a single tick has no interval yet")

    cadence.recordTick(at: 10.030)
    cadence.recordTick(at: 10.060)
    cadence.recordTick(at: 10.135)

    XCTAssertEqual(cadence.tickCount, 4)
    XCTAssertEqual(cadence.meanInterval ?? 0, 0.045, accuracy: 0.0001)
    XCTAssertEqual(cadence.maxInterval, 0.075, accuracy: 0.0001)
  }

  func testLegacyRecorderRestartDelayOnlyAppliesWhenCleaningUpExistingRecorder() {
    XCTAssertNil(
      AudioRecorder.legacyRecorderRestartSettleDelayNanoseconds(hasExistingRecorder: false)
    )
    XCTAssertEqual(
      AudioRecorder.legacyRecorderRestartSettleDelayNanoseconds(hasExistingRecorder: true),
      100_000_000
    )
  }

  func testWaitForDefaultInputDeviceSwitchReturnsImmediatelyWhenAlreadySwitched() async {
    var pollCount = 0

    let completed = await AudioRecorder.waitForDefaultInputDeviceSwitch {
      pollCount += 1
      return true
    }

    XCTAssertTrue(completed)
    XCTAssertEqual(pollCount, 1)
  }

  func testWaitForDefaultInputDeviceSwitchDetectsLateSwitch() async {
    var pollCount = 0

    let completed = await AudioRecorder.waitForDefaultInputDeviceSwitch(
      pollIntervalNanoseconds: 1_000_000
    ) {
      pollCount += 1
      return pollCount >= 3
    }

    XCTAssertTrue(completed)
    XCTAssertEqual(pollCount, 3)
  }

  func testWaitForDefaultInputDeviceSwitchTimesOutWhenSwitchNeverCompletes() async {
    let start = Date()

    let completed = await AudioRecorder.waitForDefaultInputDeviceSwitch(
      timeoutNanoseconds: 30_000_000,
      pollIntervalNanoseconds: 5_000_000
    ) {
      false
    }

    XCTAssertFalse(completed)
    XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
  }
}
