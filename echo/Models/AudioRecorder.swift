import AVFoundation
import Combine
import CoreGraphics
import Foundation

@MainActor
class AudioRecorder: NSObject, ObservableObject {
  private let unifiedEngine = UnifiedAudioEngine.shared
  private var recordingStartTime: Date?
  private var hasCheckedPermission = false
  private var cancellables = Set<AnyCancellable>()

  @Published var isRecording = false
  @Published var hasPermission = false
  @Published var currentLevel: CGFloat = 0
  @Published var waveformSamples: [Float] = []

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

    // Subscribe to unified engine's level updates
    unifiedEngine.$currentInputLevel
      .sink { [weak self] level in
        print("[WAVEFORM DEBUG] AudioRecorder received level: \(level)")
        self?.currentLevel = level
      }
      .store(in: &cancellables)

    // Subscribe to unified engine's waveform samples
    unifiedEngine.$waveformSamples
      .sink { [weak self] samples in
        self?.waveformSamples = samples
      }
      .store(in: &cancellables)
  }

  deinit {
    // Remove audio device change observer
    NotificationCenter.default.removeObserver(self)

    // Note: Can't call async methods in deinit, so cleanup is handled by UnifiedAudioEngine
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

  func getCurrentInputDevice() -> String {
    let selection = AudioInputDeviceManager.shared.resolvedSelection(
      for: SettingsManager.shared.selectedInputDeviceUID
    )
    if let selectedDevice = selection.device {
      return selectedDevice.name
    }

    guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
      return "Unknown"
    }
    return defaultDevice.localizedName
  }


  func startRecording() async throws {
    print("AudioRecorder: Starting recording via UnifiedAudioEngine")

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

    do {
      // Start recording via unified engine. Internally this verifies the HAL is actually
      // delivering audio frames before returning, so no additional settle delay is needed.
      try await unifiedEngine.startRecording(to: recordingURL)

      recordingStartTime = Date()
      isRecording = true

      print("AudioRecorder: Recording started successfully via UnifiedAudioEngine")

    } catch {
      currentRecordingURL = nil
      print("AudioRecorder: Failed to start recording: \(error)")
      throw RecordingError.failedToStartRecording
    }
  }

  func stopRecording() async -> URL? {
    print("AudioRecorder: Stopping recording")
    guard isRecording else { return nil }

    let recordingURL = await unifiedEngine.stopRecording()

    isRecording = false
    recordingStartTime = nil
    currentRecordingURL = nil

    // Audio cleanup is handled by UnifiedAudioEngine
    deactivateAudioSession()

    return recordingURL
  }

  func cancelRecording() async {
    print("AudioRecorder: Cancelling recording (isRecording: \(isRecording))")

    if isRecording {
      await unifiedEngine.cancelRecording()
    }

    // Always clean up state
    isRecording = false
    recordingStartTime = nil
    currentRecordingURL = nil

    // Audio cleanup is handled by UnifiedAudioEngine
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
