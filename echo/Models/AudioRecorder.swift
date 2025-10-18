import AVFoundation
import CoreGraphics
import Foundation

@MainActor
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  private var audioRecorder: AVAudioRecorder?
  private var recordingStartTime: Date?
  private var hasCheckedPermission = false
  private var meterUpdateTimer: Timer?

  @Published var isRecording = false
  @Published var hasPermission = false
  @Published var currentLevel: CGFloat = 0

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
    // Clean up any remaining recording file when AudioRecorder is deallocated
    if let url = currentRecordingURL {
      try? FileManager.default.removeItem(at: url)
      print("AudioRecorder: Cleaned up recording file in deinit: \(url)")
    }
    meterUpdateTimer?.invalidate()
    meterUpdateTimer = nil

    // Remove audio device change observer
    NotificationCenter.default.removeObserver(self)
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
    guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
      return "Unknown"
    }
    return defaultDevice.localizedName
  }


  func startRecording() async throws {
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

    // Stop any existing recorder first
    audioRecorder?.stop()
    audioRecorder = nil

    // Add a small delay to allow the audio system to reset
    try await Task.sleep(nanoseconds: 10_000_000)

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    currentRecordingURL = audioFileURL

    guard let recordingURL = currentRecordingURL else {
      throw RecordingError.failedToCreateFile
    }

    // Ensure cleanup happens on any failure after this point
    defer {
      if !isRecording {
        // If we failed to start recording, clean up the file
        cleanupFailedRecording()
      }
    }

    do {
      audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
      audioRecorder?.delegate = self
      audioRecorder?.isMeteringEnabled = true

      // Prepare to record with retry logic
      if audioRecorder?.prepareToRecord() != true {
        print("Warning: prepareToRecord failed, attempting to continue")
      }

      guard audioRecorder?.record() == true else {
        audioRecorder = nil
        throw RecordingError.failedToStartRecording
      }

      // Wait briefly to verify the recording actually started
      // This prevents setting isRecording = true if the underlying audio system fails
      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

      // Verify the recorder is still active and recording
      guard let recorder = audioRecorder, recorder.isRecording else {
        print("AudioRecorder: Verification failed - recorder not actually recording")
        audioRecorder = nil
        throw RecordingError.failedToStartRecording
      }

      print("AudioRecorder: Recording verified as active")
      startMetering()
      recordingStartTime = Date()
      isRecording = true

    } catch {
      audioRecorder = nil
      print("Audio recording setup error: \(error)")
      throw RecordingError.failedToStartRecording
    }
  }

  func stopRecording() async -> URL? {
    guard isRecording else { return nil }

    let recordingURL = currentRecordingURL

    audioRecorder?.stop()
    // Add a small delay to ensure the recording is properly finalized
    try? await Task.sleep(nanoseconds: 100_000_000)
    audioRecorder = nil
    isRecording = false
    recordingStartTime = nil

    stopMetering()

    // Audio cleanup is handled automatically by AVAudioRecorder on macOS
    deactivateAudioSession()

    return recordingURL
  }

  func cancelRecording() async {
    print("AudioRecorder: Cancelling recording (isRecording: \(isRecording))")

    if isRecording {
      audioRecorder?.stop()
      // Add a small delay to ensure the recording is properly finalized
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    // Always clean up state, regardless of whether we were actually recording
    audioRecorder = nil
    isRecording = false
    recordingStartTime = nil

    stopMetering()

    // Audio cleanup is handled automatically by AVAudioRecorder on macOS
    deactivateAudioSession()

    // Delete any recording file that might exist
    deleteRecording()

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

  private func startMetering() {
    audioRecorder?.isMeteringEnabled = true
    meterUpdateTimer?.invalidate()
    meterUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        guard let recorder = self.audioRecorder else {
          self.currentLevel = 0
          return
        }
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalized = self.normalizedLevel(from: averagePower)
        let smoothing: CGFloat = 0.2
        let smoothed = smoothing * normalized + (1 - smoothing) * self.currentLevel
        self.currentLevel = smoothed.isNaN ? 0 : smoothed
      }
    }
    if let timer = meterUpdateTimer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func stopMetering() {
    meterUpdateTimer?.invalidate()
    meterUpdateTimer = nil
    currentLevel = 0
  }

  private func normalizedLevel(from decibels: Float) -> CGFloat {
    let minDb: Float = -60  // Changed from -80 to -60 for better sensitivity
    let maxDb: Float = -10  // Cap at -10dB instead of 0dB for normal speech levels

    if decibels <= minDb {
      return 0
    }

    let clamped = min(max(decibels, minDb), maxDb)
    let normalized = (clamped - minDb) / (maxDb - minDb)
    return CGFloat(max(0, min(1, normalized)))
  }

  // MARK: - Audio Configuration

  private func configureAudioSession() throws {
    // On macOS, AVAudioRecorder handles most audio configuration automatically.
    // However, we can perform basic validation to ensure the audio system is ready.

    // Verify we have an available audio input device
    guard AVCaptureDevice.default(for: .audio) != nil else {
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

  // MARK: - AVAudioRecorderDelegate

  nonisolated func audioRecorderDidFinishRecording(
    _ recorder: AVAudioRecorder,
    successfully flag: Bool
  ) {
    Task { @MainActor in
      if !flag {
        isRecording = false
        recordingStartTime = nil
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
      stopMetering()
      if let error = error {
        print("Recording encode error: \(error)")
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
