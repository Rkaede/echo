import CoreAudio
import XCTest

@testable import Echo

final class AudioInputDeviceManagerXCTests: XCTestCase {
  func testWiredTransportsAreNotWireless() {
    let wiredTransports: [UInt32] = [
      kAudioDeviceTransportTypeBuiltIn,
      kAudioDeviceTransportTypeUSB,
      kAudioDeviceTransportTypeThunderbolt,
      kAudioDeviceTransportTypeDisplayPort,
      kAudioDeviceTransportTypeHDMI,
      kAudioDeviceTransportTypeFireWire,
      kAudioDeviceTransportTypePCI,
      kAudioDeviceTransportTypeContinuityCaptureWired,
    ]

    for transport in wiredTransports {
      XCTAssertFalse(
        AudioInputDeviceManager.isWirelessTransport(transport),
        "Transport \(transport) should be treated as wired"
      )
    }
  }

  func testWirelessTransportsRequireSettleBehavior() {
    let wirelessTransports: [UInt32] = [
      kAudioDeviceTransportTypeBluetooth,
      kAudioDeviceTransportTypeBluetoothLE,
      kAudioDeviceTransportTypeAirPlay,
      kAudioDeviceTransportTypeContinuityCaptureWireless,
    ]

    for transport in wirelessTransports {
      XCTAssertTrue(
        AudioInputDeviceManager.isWirelessTransport(transport),
        "Transport \(transport) should be treated as wireless"
      )
    }
  }

  func testUnknownOrUnreadableTransportIsConservativelyWireless() {
    XCTAssertTrue(AudioInputDeviceManager.isWirelessTransport(nil))
    XCTAssertTrue(
      AudioInputDeviceManager.isWirelessTransport(kAudioDeviceTransportTypeUnknown)
    )
  }
}
