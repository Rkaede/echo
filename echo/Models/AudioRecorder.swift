import AVFoundation
import Foundation

@MainActor
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  private var audioRecorder: AVAudioRecorder?
  private var recordingStartTime: Date?
  private var hasCheckedPermission = false

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
  }
  
  deinit {
    // Clean up any remaining recording file when AudioRecorder is deallocated
    if let url = currentRecordingURL {
      try? FileManager.default.removeItem(at: url)
      print("AudioRecorder: Cleaned up recording file in deinit: \(url)")
    }
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
    try await Task.sleep(nanoseconds: 100_000_000)

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

      // Prepare to record with retry logic
      if audioRecorder?.prepareToRecord() != true {
        print("Warning: prepareToRecord failed, attempting to continue")
      }

      guard audioRecorder?.record() == true else {
        audioRecorder = nil
        throw RecordingError.failedToStartRecording
      }

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
