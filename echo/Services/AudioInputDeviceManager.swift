import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
  let uid: String
  let name: String
  let deviceID: AudioDeviceID

  var id: String { uid }
}

enum AudioInputDeviceSelectionSource: String, Equatable {
  case preferred
  case fallback
  case systemDefault
}

struct AudioInputDeviceSelection: Equatable {
  let device: AudioInputDevice?
  let source: AudioInputDeviceSelectionSource
}

@MainActor
final class AudioInputDeviceManager: ObservableObject {
  static let shared = AudioInputDeviceManager()

  @Published private(set) var devices: [AudioInputDevice] = []

  private init() {
    refreshDevices()
    setupDeviceChangeNotifications()
  }

  static func resolveDevice(
    preferredUID: String,
    fallbackUID: String,
    devices: [AudioInputDevice],
    defaultDevice: AudioInputDevice?
  ) -> AudioInputDeviceSelection {
    guard !preferredUID.isEmpty else {
      return AudioInputDeviceSelection(device: defaultDevice, source: .systemDefault)
    }

    if let preferredDevice = devices.first(where: { $0.uid == preferredUID }) {
      return AudioInputDeviceSelection(device: preferredDevice, source: .preferred)
    }

    if !fallbackUID.isEmpty,
      let fallbackDevice = devices.first(where: { $0.uid == fallbackUID })
    {
      return AudioInputDeviceSelection(device: fallbackDevice, source: .fallback)
    }

    return AudioInputDeviceSelection(device: defaultDevice, source: .systemDefault)
  }

  func refreshDevices() {
    devices = Self.fetchInputDevices()
  }

  func currentDefaultInputDevice() -> AudioInputDevice? {
    guard let defaultDeviceID = Self.defaultInputDeviceID() else { return nil }
    if let knownDevice = devices.first(where: { $0.deviceID == defaultDeviceID }) {
      return knownDevice
    }
    return Self.makeInputDevice(for: defaultDeviceID)
  }

  func resolvedSelection(
    preferredUID: String,
    fallbackUID: String
  ) -> AudioInputDeviceSelection {
    refreshDevices()
    return Self.resolveDevice(
      preferredUID: preferredUID,
      fallbackUID: fallbackUID,
      devices: devices,
      defaultDevice: currentDefaultInputDevice()
    )
  }

  func selectedDeviceDisplayName(
    preferredUID: String,
    preferredName: String
  ) -> String {
    let selection = resolvedSelection(preferredUID: preferredUID, fallbackUID: "")
    if selection.source == .systemDefault, !preferredUID.isEmpty, !preferredName.isEmpty {
      return "\(preferredName) (Unavailable)"
    }
    return selection.device?.name ?? "System Default"
  }

  private func setupDeviceChangeNotifications() {
    NotificationCenter.default.addObserver(
      forName: AVCaptureDevice.wasConnectedNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshDevices() }
    }

    NotificationCenter.default.addObserver(
      forName: AVCaptureDevice.wasDisconnectedNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshDevices() }
    }
  }

  static func applyInputDevice(_ deviceID: AudioDeviceID, to audioUnit: AudioUnit) throws {
    var mutableDeviceID = deviceID
    let status = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &mutableDeviceID,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )

    guard status == noErr else {
      throw AudioInputDeviceError.failedToApplyDevice(status)
    }
  }

  static func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var mutableDeviceID = deviceID
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableDeviceID
    )

    guard status == noErr else {
      throw AudioInputDeviceError.failedToApplyDevice(status)
    }
  }

  nonisolated static func describeOSStatus(_ status: OSStatus) -> String {
    let unsignedStatus = UInt32(bitPattern: status)
    let bytes = [
      UInt8((unsignedStatus >> 24) & 0xff),
      UInt8((unsignedStatus >> 16) & 0xff),
      UInt8((unsignedStatus >> 8) & 0xff),
      UInt8(unsignedStatus & 0xff),
    ]

    let isPrintableFourCharCode = bytes.allSatisfy { byte in
      byte >= 32 && byte <= 126
    }

    guard isPrintableFourCharCode,
      let fourCharCode = String(bytes: bytes, encoding: .ascii)
    else {
      return "\(status)"
    }

    return "\(status) ('\(fourCharCode)')"
  }

  nonisolated static func isRecoverableAudioSetupStatus(_ status: OSStatus) -> Bool {
    status == OSStatus(kAudioHardwareIllegalOperationError)
      || status == OSStatus(35)
      || status == OSStatus(-10877)
  }

  private static func fetchInputDevices() -> [AudioInputDevice] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize
    ) == noErr else {
      return []
    }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    guard deviceCount > 0 else { return [] }

    var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &deviceIDs
    ) == noErr else {
      return []
    }

    return deviceIDs
      .compactMap { makeInputDevice(for: $0) }
      .sorted { lhs, rhs in
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
  }

  private static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &deviceID
    ) == noErr, deviceID != kAudioObjectUnknown else {
      return nil
    }

    return deviceID
  }

  private static func makeInputDevice(for deviceID: AudioDeviceID) -> AudioInputDevice? {
    guard inputChannelCount(for: deviceID) > 0,
      let uid = stringProperty(
        kAudioDevicePropertyDeviceUID,
        scope: kAudioObjectPropertyScopeGlobal,
        deviceID: deviceID
      ),
      let name = stringProperty(
        kAudioObjectPropertyName,
        scope: kAudioObjectPropertyScopeGlobal,
        deviceID: deviceID
      )
    else {
      return nil
    }

    return AudioInputDevice(uid: uid, name: name, deviceID: deviceID)
  }

  private static func inputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
      dataSize > 0
    else {
      return 0
    }

    let bufferListPointer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { bufferListPointer.deallocate() }

    guard AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &dataSize,
      bufferListPointer
    ) == noErr else {
      return 0
    }

    let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
    return UnsafeMutableAudioBufferListPointer(audioBufferList)
      .reduce(UInt32(0)) { total, buffer in total + buffer.mNumberChannels }
  }

  private static func stringProperty(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    deviceID: AudioDeviceID
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    let valuePointer = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
    valuePointer.initialize(to: nil)
    defer {
      valuePointer.deinitialize(count: 1)
      valuePointer.deallocate()
    }

    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, valuePointer) == noErr,
      let value = valuePointer.pointee
    else {
      return nil
    }

    return value.takeRetainedValue() as String
  }
}

enum AudioInputDeviceError: LocalizedError {
  case failedToApplyDevice(OSStatus)

  var errorDescription: String? {
    switch self {
    case .failedToApplyDevice(let status):
      return "Failed to select microphone device (OSStatus \(AudioInputDeviceManager.describeOSStatus(status)))"
    }
  }
}
