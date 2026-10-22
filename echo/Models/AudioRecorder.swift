import AVFoundation
import Combine
import CoreGraphics
import Foundation

struct AudioRecorderCaptureRoute: Equatable {
  let captureDevice: AudioInputDevice?
  let deviceToMakeDefault: AudioInputDevice?
  let deviceToRestore: AudioInputDevice?
}

/// Tick-to-tick timing of the metering poll over one recording.
///
/// The poll runs on the main actor, so its real interval stretches whenever the main thread
/// is busy. A mean well above `RecordingSignal.meteringInterval` means the UI is falling
/// behind, which makes this the cheapest regression signal for overlay and waveform lag.
struct MeteringCadence: Equatable {
  private(set) var tickCount = 0
  private(set) var maxInterval: TimeInterval = 0
  private var totalInterval: TimeInterval = 0
  private var lastTickTime: TimeInterval?

  /// Mean gap between consecutive ticks, or nil until there have been at least two.
  var meanInterval: TimeInterval? {
    tickCount > 1 ? totalInterval / Double(tickCount - 1) : nil
  }

  mutating func recordTick(at time: TimeInterval) {
    if let lastTickTime {
      let interval = time - lastTickTime
      totalInterval += interval
      maxInterval = max(maxInterval, interval)
    }
    lastTickTime = time
    tickCount += 1
  }
}

@MainActor
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  private enum RecordingBackend {
    case none
    case legacyRecorder
  }

  // Sourced from RecordingSignal so the speech gate's voiced-frame threshold (defined in
  // terms of this cadence) can't silently drift out of sync with the actual poll rate.
  nonisolated private static let legacyMeteringIntervalNanoseconds = UInt64(
    RecordingSignal.meteringInterval * 1_000_000_000
  )

  private let levelMeter = AudioLevelMeter.shared
  private var legacyRecorder: AVAudioRecorder?
  private var legacyMeteringTask: Task<Void, Never>?
  private var meteringCadence = MeteringCadence()
  private var activeRecordingBackend: RecordingBackend = .none
  private var peakPowerDecibels = RecordingSignal.silenceFloorDecibels
  private var voicedFrameCount = 0
  private var recordingStartTime: Date?
  private var hasCheckedPermission = false
  private var currentCaptureInputDevice: AudioInputDevice?
  private var defaultInputDeviceToRestore: AudioInputDevice?

  @Published var isRecording = false
  @Published var hasPermission = false

  private var audioFileURL: URL {
    let tempDirectory = FileManager.default.temporaryDirectory
    let echoDirectory = tempDirectory.appendingPathComponent("echo")

    // Create echo directory if it doesn't exist
    try? FileManager.default.createDirectory(at: echoDirectory, withIntermediateDirectories: true)

    let timestamp = Date().timeIntervalSince1970
    return echoDirectory.appendingPathComponent("recording_\(timestamp).wav")
  }

  override init() {
    super.init()
    // Don't check permissions on init - wait until explicitly requested
    setupAudioDeviceChangeNotification()
  }

  deinit {
    // Remove audio device change observer
    NotificationCenter.default.removeObserver(self)

    // Note: Can't call async methods in deinit, so active recordings are cleaned up on stop/cancel.
  }

  // Check current permission status without requesting
  func checkPermissionStatus() {
    guard !hasCheckedPermission else { return }

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      hasPermission = true
    case .denied, .restricted:
      hasPermission = false
    case .notDetermined:
      hasPermission = false
    @unknown default:
      hasPermission = false
    }

    hasCheckedPermission = true
  }

  // Request permission explicitly (called from onboarding or when recording)
  func requestPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      hasPermission = true
      hasCheckedPermission = true
      return true
    case .notDetermined:
      let granted = await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
      hasPermission = granted
      hasCheckedPermission = true
      return granted
    case .denied, .restricted:
      hasPermission = false
      hasCheckedPermission = true
      return false
    @unknown default:
      hasPermission = false
      hasCheckedPermission = true
      return false
    }
  }

  private var currentRecordingURL: URL?

  nonisolated static func shouldUseAudioRecorderCapture(
    defaultInputDevice _: AudioInputDevice?
  ) -> Bool {
    // AVAudioEngine.inputNode can fail inside AVFAudio/HAL before Swift can recover.
    // Route capture through AVAudioRecorder so recording startup avoids that boundary.
    true
  }

  nonisolated static func normalizedLegacyMeterLevel(averagePower: Float) -> CGFloat {
    guard averagePower > -60 else { return 0 }
    let shaped = pow(10, averagePower / 40) * 1.25
    return CGFloat(max(0, min(1, shaped)))
  }

  nonisolated static func legacyRecorderRestartSettleDelayNanoseconds(
    hasExistingRecorder: Bool
  ) -> UInt64? {
    hasExistingRecorder ? 100_000_000 : nil
  }

  nonisolated static let defaultInputSwitchTimeoutNanoseconds: UInt64 = 200_000_000
  nonisolated static let defaultInputSwitchPollIntervalNanoseconds: UInt64 = 20_000_000

  /// Polls until the system default input matches the requested device, so capture setup
  /// resumes as soon as the HAL applies the switch instead of after a fixed sleep.
  @discardableResult
  static func waitForDefaultInputDeviceSwitch(
    timeoutNanoseconds: UInt64 = defaultInputSwitchTimeoutNanoseconds,
    pollIntervalNanoseconds: UInt64 = defaultInputSwitchPollIntervalNanoseconds,
    isSwitchComplete: @MainActor () -> Bool
  ) async -> Bool {
    if isSwitchComplete() {
      return true
    }

    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
    while Date() < deadline {
      try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
      if isSwitchComplete() {
        return true
      }
    }

    return isSwitchComplete()
  }

  nonisolated static func audioRecorderCaptureRoute(
    resolvedSelection: AudioInputDeviceSelection,
    defaultInputDevice: AudioInputDevice?
  ) -> AudioRecorderCaptureRoute {
    guard resolvedSelection.source != .systemDefault,
      let selectedDevice = resolvedSelection.device
    else {
      return systemDefaultAudioRecorderCaptureRoute(defaultInputDevice: defaultInputDevice)
    }

    guard selectedDevice.deviceID != defaultInputDevice?.deviceID else {
      return AudioRecorderCaptureRoute(
        captureDevice: selectedDevice,
        deviceToMakeDefault: nil,
        deviceToRestore: nil
      )
    }

    return AudioRecorderCaptureRoute(
      captureDevice: selectedDevice,
      deviceToMakeDefault: selectedDevice,
      deviceToRestore: defaultInputDevice
    )
  }

  nonisolated private static func systemDefaultAudioRecorderCaptureRoute(
    defaultInputDevice: AudioInputDevice?
  ) -> AudioRecorderCaptureRoute {
    AudioRecorderCaptureRoute(
      captureDevice: defaultInputDevice,
      deviceToMakeDefault: nil,
      deviceToRestore: nil
    )
  }

  /// The name of the mic in use, or an empty string when none can be found.
  func getCurrentInputDevice() -> String {
    if let currentCaptureInputDevice {
      return currentCaptureInputDevice.name
    }

    if let defaultDevice = AudioInputDeviceManager.shared.currentDefaultInputDevice() {
      return defaultDevice.name
    }

    return AVCaptureDevice.default(for: .audio)?.localizedName ?? ""
  }

  /// Whether the device feeding the active capture route (or the system default input when
  /// no capture is active) is on a wireless transport such as Bluetooth. Returns true when
  /// no device can be resolved so callers keep the conservative Bluetooth-safe behavior.
  func isCurrentCaptureInputWireless() -> Bool {
    let device = currentCaptureInputDevice
      ?? AudioInputDeviceManager.shared.currentDefaultInputDevice()
    guard let device else { return true }
    return AudioInputDeviceManager.isWirelessTransport(
      AudioInputDeviceManager.transportType(for: device.deviceID)
    )
  }

  func startRecording() async throws {
    print("AudioRecorder: Starting recording")

    // Ensure we've checked permissions
    checkPermissionStatus()

    guard hasPermission else {
      throw RecordingError.noPermission
    }

    guard !isRecording else {
      throw RecordingError.alreadyRecording
    }

    // Configure audio session for recording
    try configureAudioSession()

    currentRecordingURL = audioFileURL

    guard let recordingURL = currentRecordingURL else {
      throw RecordingError.failedToCreateFile
    }

    let captureRoute = await prepareAudioRecorderCaptureRoute()
    logAudioRecorderCaptureRoute(captureRoute)

    do {
      guard Self.shouldUseAudioRecorderCapture(defaultInputDevice: captureRoute.captureDevice) else {
        throw RecordingError.audioSessionConfigurationFailed
      }

      try await startLegacyRecording(
        to: recordingURL,
        captureDevice: captureRoute.captureDevice
      )

    } catch {
      print("AudioRecorder: Failed to start recording: \(error)")
      cleanupFailedRecording()
      throw error
    }
  }

  private func startLegacyRecording(
    to recordingURL: URL,
    captureDevice: AudioInputDevice?
  ) async throws {
    print(
      "AudioRecorder: Using AVAudioRecorder capture for input device \(Self.describeInputDevice(captureDevice))"
    )

    if let existingRecorder = legacyRecorder {
      existingRecorder.stop()
      existingRecorder.delegate = nil
      legacyRecorder = nil

      if let settleDelay = Self.legacyRecorderRestartSettleDelayNanoseconds(
        hasExistingRecorder: true
      ) {
        try await Task.sleep(nanoseconds: settleDelay)
      }
    }

    let recorder = try AVAudioRecorder(url: recordingURL, settings: legacyRecorderSettings())
    recorder.delegate = self
    recorder.isMeteringEnabled = true

    if !recorder.prepareToRecord() {
      print("AudioRecorder: AVAudioRecorder prepareToRecord returned false; attempting record anyway")
    }

    guard recorder.record() else {
      throw RecordingError.failedToStartRecording
    }

    legacyRecorder = recorder
    currentCaptureInputDevice = captureDevice
    recordingStartTime = Date()
    isRecording = true
    activeRecordingBackend = .legacyRecorder
    levelMeter.reset()
    peakPowerDecibels = RecordingSignal.silenceFloorDecibels
    voicedFrameCount = 0
    startLegacyMetering()

    print("AudioRecorder: Recording started successfully via AVAudioRecorder capture")
  }

  private func prepareAudioRecorderCaptureRoute() async -> AudioRecorderCaptureRoute {
    let manager = AudioInputDeviceManager.shared
    let defaultInputDevice = manager.currentDefaultInputDevice()
    let settings = SettingsManager.shared
    let selection = manager.resolvedSelection(
      preferredUID: settings.selectedInputDeviceUID,
      fallbackUID: settings.fallbackInputDeviceUID
    )
    var route = Self.audioRecorderCaptureRoute(
      resolvedSelection: selection,
      defaultInputDevice: defaultInputDevice
    )

    guard let deviceToMakeDefault = route.deviceToMakeDefault else {
      return route
    }

    do {
      print(
        "AudioRecorder: Temporarily setting system default input to selected device \(Self.describeInputDevice(deviceToMakeDefault)) for AVAudioRecorder capture"
      )
      try AudioInputDeviceManager.setDefaultInputDevice(deviceToMakeDefault.deviceID)
      defaultInputDeviceToRestore = route.deviceToRestore
      let switchStart = Date()
      let switchCompleted = await Self.waitForDefaultInputDeviceSwitch {
        manager.currentDefaultInputDevice()?.deviceID == deviceToMakeDefault.deviceID
      }
      print(
        "AudioRecorder: Default input switch \(switchCompleted ? "completed" : "timed out") after \(Int(Date().timeIntervalSince(switchStart) * 1000))ms"
      )
      manager.refreshDevices()

      let effectiveDefaultInputDevice = manager.currentDefaultInputDevice()
      guard effectiveDefaultInputDevice?.deviceID == deviceToMakeDefault.deviceID else {
        print(
          "AudioRecorder: Selected input device did not become system default; AVAudioRecorder capture will use \(Self.describeInputDevice(effectiveDefaultInputDevice ?? defaultInputDevice))"
        )
        restoreDefaultInputDeviceIfNeeded()
        route = Self.systemDefaultAudioRecorderCaptureRoute(
          defaultInputDevice: effectiveDefaultInputDevice ?? defaultInputDevice
        )
        return route
      }

      return AudioRecorderCaptureRoute(
        captureDevice: effectiveDefaultInputDevice ?? deviceToMakeDefault,
        deviceToMakeDefault: deviceToMakeDefault,
        deviceToRestore: route.deviceToRestore
      )
    } catch {
      print(
        "AudioRecorder: Failed to set selected input device as system default: \(error); AVAudioRecorder capture will use \(Self.describeInputDevice(defaultInputDevice))"
      )
      defaultInputDeviceToRestore = nil
      return Self.systemDefaultAudioRecorderCaptureRoute(defaultInputDevice: defaultInputDevice)
    }
  }

  private func logAudioRecorderCaptureRoute(_ route: AudioRecorderCaptureRoute) {
    let settings = SettingsManager.shared
    let preferredUID = settings.selectedInputDeviceUID
    let fallbackUID = settings.fallbackInputDeviceUID
    let selection = AudioInputDeviceManager.shared.resolvedSelection(
      preferredUID: preferredUID,
      fallbackUID: fallbackUID
    )

    guard preferredUID.isEmpty == false else {
      print(
        "AudioRecorder: AVAudioRecorder capture will use system default input \(Self.describeInputDevice(route.captureDevice))"
      )
      return
    }

    if selection.source == .systemDefault {
      let preferredName = settings.selectedInputDeviceName.isEmpty
        ? preferredUID
        : settings.selectedInputDeviceName
      let unavailableDescription: String
      if fallbackUID.isEmpty {
        unavailableDescription = "Preferred input device '\(preferredName)' is unavailable"
      } else {
        let fallbackName = settings.fallbackInputDeviceName.isEmpty
          ? fallbackUID
          : settings.fallbackInputDeviceName
        unavailableDescription =
          "Preferred input device '\(preferredName)' and fallback input device '\(fallbackName)' are unavailable"
      }
      print(
        "AudioRecorder: \(unavailableDescription); AVAudioRecorder capture will use system default input \(Self.describeInputDevice(route.captureDevice))"
      )
      return
    }

    guard let resolvedDevice = selection.device else {
      print(
        "AudioRecorder: AVAudioRecorder capture will use system default input \(Self.describeInputDevice(route.captureDevice))"
      )
      return
    }

    let sourceName = selection.source.rawValue
    if resolvedDevice.deviceID == route.captureDevice?.deviceID {
      print(
        "AudioRecorder: Using \(sourceName) input device \(Self.describeInputDevice(resolvedDevice))"
      )
    } else {
      print(
        "AudioRecorder: Resolved \(sourceName) input device \(Self.describeInputDevice(resolvedDevice)) could not be applied; AVAudioRecorder capture will use system default input \(Self.describeInputDevice(route.captureDevice))"
      )
    }
  }

  private func restoreDefaultInputDeviceIfNeeded() {
    guard let deviceToRestore = defaultInputDeviceToRestore else { return }

    do {
      try AudioInputDeviceManager.setDefaultInputDevice(deviceToRestore.deviceID)
      AudioInputDeviceManager.shared.refreshDevices()
      print(
        "AudioRecorder: Restored system default input device to \(Self.describeInputDevice(deviceToRestore))"
      )
    } catch {
      print(
        "AudioRecorder: Failed to restore system default input device \(Self.describeInputDevice(deviceToRestore)): \(error)"
      )
    }

    defaultInputDeviceToRestore = nil
  }

  nonisolated private static func describeInputDevice(_ device: AudioInputDevice?) -> String {
    guard let device else { return "unknown default input" }
    return "\(device.name) (\(device.uid), id: \(device.deviceID))"
  }

  private func startLegacyMetering() {
    legacyMeteringTask?.cancel()
    meteringCadence = MeteringCadence()
    updateLegacyMetering()

    legacyMeteringTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: Self.legacyMeteringIntervalNanoseconds)
        guard let self else { return }
        self.updateLegacyMetering()
      }
    }
  }

  private func stopLegacyMetering() {
    let wasMetering = legacyMeteringTask != nil
    legacyMeteringTask?.cancel()
    legacyMeteringTask = nil
    levelMeter.reset()

    if wasMetering {
      logMeteringCadence()
    }
  }

  private func logMeteringCadence() {
    guard let meanInterval = meteringCadence.meanInterval else { return }
    log(
      String(
        format: "Metering cadence: %ld ticks, mean %.1fms, max %.1fms (target %.0fms)",
        meteringCadence.tickCount,
        meanInterval * 1000,
        meteringCadence.maxInterval * 1000,
        RecordingSignal.meteringInterval * 1000
      ),
      category: "AudioRecorder",
      level: .info
    )
  }

  private func updateLegacyMetering() {
    guard activeRecordingBackend == .legacyRecorder,
      let legacyRecorder,
      legacyRecorder.isRecording
    else {
      return
    }

    meteringCadence.recordTick(at: ProcessInfo.processInfo.systemUptime)
    legacyRecorder.updateMeters()

    // Peak rather than average for the speech gate: a single short word in an otherwise
    // quiet recording barely moves the average but shows up clearly in the peak.
    let peakPower = legacyRecorder.peakPower(forChannel: 0)
    peakPowerDecibels = max(peakPowerDecibels, peakPower)
    if SpeechGate.isVoicedFrame(peakPowerDecibels: peakPower) {
      voicedFrameCount += 1
    }

    let level = Self.normalizedLegacyMeterLevel(
      averagePower: legacyRecorder.averagePower(forChannel: 0)
    )
    levelMeter.append(Float(level))
  }

  /// Metering summary for the recording that just finished.
  ///
  /// Stopping a recording deliberately leaves these counters intact — only starting the next
  /// one resets them — so the transcription pipeline can read the signal after
  /// `stopRecording()` has already returned the file.
  func recordingSignal(duration: TimeInterval) -> RecordingSignal {
    RecordingSignal(
      peakPowerDecibels: peakPowerDecibels,
      voicedFrameCount: voicedFrameCount,
      duration: duration
    )
  }

  private func legacyRecorderSettings() -> [String: Any] {
    [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
  }

  func stopRecording() async -> URL? {
    print("AudioRecorder: Stopping recording")
    guard isRecording else { return nil }

    let recordingURL: URL?
    switch activeRecordingBackend {
    case .legacyRecorder:
      recordingURL = await stopLegacyRecording()
    case .none:
      recordingURL = nil
    }

    isRecording = false
    recordingStartTime = nil
    currentRecordingURL = nil
    activeRecordingBackend = .none
    currentCaptureInputDevice = nil
    restoreDefaultInputDeviceIfNeeded()

    deactivateAudioSession()

    return recordingURL
  }

  private func stopLegacyRecording() async -> URL? {
    let recordingURL = currentRecordingURL
    stopLegacyMetering()
    legacyRecorder?.stop()
    try? await Task.sleep(nanoseconds: 100_000_000)
    legacyRecorder?.delegate = nil
    legacyRecorder = nil
    return recordingURL
  }

  func cancelRecording() async {
    print("AudioRecorder: Cancelling recording (isRecording: \(isRecording))")

    if isRecording, activeRecordingBackend == .legacyRecorder {
      stopLegacyMetering()
      legacyRecorder?.stop()
      try? await Task.sleep(nanoseconds: 100_000_000)
      legacyRecorder?.delegate = nil
      legacyRecorder = nil
      deleteRecording()
    }

    // Always clean up state
    isRecording = false
    recordingStartTime = nil
    currentRecordingURL = nil
    activeRecordingBackend = .none
    currentCaptureInputDevice = nil
    restoreDefaultInputDeviceIfNeeded()

    deactivateAudioSession()

    print("AudioRecorder: Recording cancellation completed")
  }

  func deleteRecording() {
    if let url = currentRecordingURL {
      do {
        try FileManager.default.removeItem(at: url)
        print("AudioRecorder: Successfully deleted recording at \(url)")
      } catch {
        print("AudioRecorder: Failed to delete recording at \(url): \(error)")
      }
      currentRecordingURL = nil
    }
  }

  private func cleanupFailedRecording() {
    stopLegacyMetering()
    legacyRecorder?.stop()
    legacyRecorder?.delegate = nil
    legacyRecorder = nil
    activeRecordingBackend = .none
    currentCaptureInputDevice = nil
    restoreDefaultInputDeviceIfNeeded()

    if let url = currentRecordingURL {
      do {
        try FileManager.default.removeItem(at: url)
        print("AudioRecorder: Cleaned up failed recording at \(url)")
      } catch {
        print("AudioRecorder: Failed to clean up failed recording at \(url): \(error)")
      }
      currentRecordingURL = nil
    }
  }


  // MARK: - Audio Configuration

  private func configureAudioSession() throws {
    // On macOS, AVAudioRecorder handles most audio configuration automatically.
    // However, we can perform basic validation to ensure the audio system is ready.

    // Verify we have an available audio input device
    guard AudioInputDeviceManager.shared.currentDefaultInputDevice() != nil
      || AVCaptureDevice.default(for: .audio) != nil
    else {
      print("No audio input device available")
      throw RecordingError.audioSessionConfigurationFailed
    }

    // Additional macOS-specific audio setup could go here if needed
    // For now, we rely on AVAudioRecorder's built-in configuration
  }

  private func deactivateAudioSession() {
    // On macOS, audio session cleanup is typically handled automatically
    // by AVAudioRecorder when it's deallocated. No explicit deactivation needed.
  }

  // MARK: - Audio Device Change Monitoring

  private func setupAudioDeviceChangeNotification() {
    // Monitor for audio input device changes (e.g., AirPods connecting/disconnecting)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioDeviceChange),
      name: AVCaptureDevice.wasConnectedNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioDeviceChange),
      name: AVCaptureDevice.wasDisconnectedNotification,
      object: nil
    )
  }

  @objc private func handleAudioDeviceChange(_ notification: Notification) {
    Task { @MainActor in
      // Only log device changes if we're actively recording
      guard isRecording else { return }

      if notification.name == AVCaptureDevice.wasDisconnectedNotification {
        print("AudioRecorder: Audio input device was disconnected during recording")
        // The recording will likely fail, but AVAudioRecorder will handle the error
        // via audioRecorderEncodeErrorDidOccur delegate method
      } else if notification.name == AVCaptureDevice.wasConnectedNotification {
        print("AudioRecorder: New audio input device connected during recording")
        // Continue with current recording - device changes mid-recording are rare
        // and AVAudioRecorder should handle it gracefully
      }

      // Update the current device name in case it changed
      if let device = notification.object as? AVCaptureDevice,
        device.hasMediaType(.audio)
      {
        print("AudioRecorder: Device change: \(device.localizedName)")
      }
    }
  }

  nonisolated func audioRecorderDidFinishRecording(
    _ recorder: AVAudioRecorder,
    successfully flag: Bool
  ) {
    Task { @MainActor in
      if !flag {
        isRecording = false
        recordingStartTime = nil
        activeRecordingBackend = .none
        currentCaptureInputDevice = nil
        stopLegacyMetering()
        restoreDefaultInputDeviceIfNeeded()
      }
    }
  }

  nonisolated func audioRecorderEncodeErrorDidOccur(
    _ recorder: AVAudioRecorder,
    error: Error?
  ) {
    Task { @MainActor in
      isRecording = false
      recordingStartTime = nil
      activeRecordingBackend = .none
      currentCaptureInputDevice = nil
      stopLegacyMetering()
      restoreDefaultInputDeviceIfNeeded()
      if let error {
        print("AudioRecorder: AVAudioRecorder encode error: \(error)")
      }
    }
  }

}

enum RecordingError: LocalizedError {
  case noPermission
  case alreadyRecording
  case failedToCreateFile
  case failedToStartRecording
  case audioSessionConfigurationFailed

  var errorDescription: String? {
    switch self {
    case .noPermission:
      return "Microphone permission not granted"
    case .alreadyRecording:
      return "Recording is already in progress"
    case .failedToCreateFile:
      return "Failed to create recording file"
    case .failedToStartRecording:
      return "Failed to start recording"
    case .audioSessionConfigurationFailed:
      return "Failed to configure audio session"
    }
  }
}
