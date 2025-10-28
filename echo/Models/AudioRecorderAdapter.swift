import AVFoundation
import Combine
import CoreGraphics
import Foundation

// Create a typealias to avoid naming conflicts with delegate methods
typealias AudioRecorderEngine = AudioRecorderUpdated

/// Adapter that bridges AudioRecorderUpdated to the existing app architecture
/// Converts delegate pattern to @Published properties and provides @MainActor guarantees
@MainActor
class AudioRecorderAdapter: NSObject, ObservableObject {
  private let recorder: AudioRecorderEngine
  private var hasCheckedPermission = false
  
  @Published var isRecording = false
  @Published var isInitiating = false
  @Published var hasPermission = false
  @Published var currentLevel: CGFloat = 0
  
  private var currentRecordingURL: URL?
  private var recordingCompletionHandler: ((URL?) -> Void)?
  
  override init() {
    recorder = AudioRecorderEngine()
    super.init()
    recorder.delegate = self
  }
  
  // MARK: - Permission Management
  
  /// Check current permission status without requesting
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
  
  /// Request permission explicitly (called from onboarding or when recording)
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
  
  // MARK: - Recording Control
  
  func getCurrentInputDevice() -> String {
    guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
      return "Unknown"
    }
    return defaultDevice.localizedName
  }
  
  func startRecording() async throws {
    print("AudioRecorderAdapter: Starting recording via AudioRecorderUpdated")
    
    // Ensure we've checked permissions
    checkPermissionStatus()
    
    guard hasPermission else {
      throw RecordingError.noPermission
    }
    
    guard !isRecording && !isInitiating else {
      throw RecordingError.alreadyRecording
    }
    
    // Start recording - delegate will handle state updates
    try await recorder.startRecording()
    
    print("AudioRecorderAdapter: Recording started successfully")
  }
  
  func stopRecording() async -> URL? {
    print("AudioRecorderAdapter: Stopping recording")
    
    guard isRecording || isInitiating else { 
      print("AudioRecorderAdapter: Not currently recording")
      return nil 
    }
    
    // Use continuation to wait for delegate callback
    return await withCheckedContinuation { continuation in
      recordingCompletionHandler = { url in
        continuation.resume(returning: url)
      }
      
      // Stop the recording - delegate will handle callback
      recorder.stopRecording()
      
      // Safety timeout in case delegate doesn't fire
      Task {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        if self.recordingCompletionHandler != nil {
          print("AudioRecorderAdapter: Timeout waiting for recording completion")
          self.recordingCompletionHandler = nil
          continuation.resume(returning: nil)
        }
      }
    }
  }
  
  func cancelRecording() async {
    print("AudioRecorderAdapter: Cancelling recording (isRecording: \(isRecording), isInitiating: \(isInitiating))")
    
    if isRecording || isInitiating {
      recorder.stopRecording()
    }
    
    // Clean up state
    isRecording = false
    isInitiating = false
    currentRecordingURL = nil
    recordingCompletionHandler = nil
    currentLevel = 0
    
    // Delete any recording file
    if let url = currentRecordingURL {
      try? FileManager.default.removeItem(at: url)
      currentRecordingURL = nil
    }
    
    print("AudioRecorderAdapter: Recording cancellation completed")
  }
  
  func deleteRecording() {
    if let url = currentRecordingURL {
      do {
        try FileManager.default.removeItem(at: url)
        print("AudioRecorderAdapter: Successfully deleted recording at \(url)")
      } catch {
        print("AudioRecorderAdapter: Failed to delete recording at \(url): \(error)")
      }
      currentRecordingURL = nil
    }
  }
}

// MARK: - AudioRecorderUpdatedDelegate

extension AudioRecorderAdapter: AudioRecorderUpdatedDelegate {
  nonisolated func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didChangeState state: RecordingState) {
    Task { @MainActor in
      switch state {
      case .idle:
        print("AudioRecorderAdapter: State changed to idle")
        self.isRecording = false
        self.isInitiating = false
        self.currentLevel = 0
        
      case .initiating:
        print("AudioRecorderAdapter: State changed to initiating")
        self.isInitiating = true
        self.isRecording = false
        
      case .recording:
        print("AudioRecorderAdapter: State changed to recording")
        self.isInitiating = false
        self.isRecording = true
        
      case .paused:
        print("AudioRecorderAdapter: State changed to paused")
        // Treat paused as still recording for now
        self.isInitiating = false
        self.isRecording = true
        
      case .failed(let error):
        print("AudioRecorderAdapter: State changed to failed: \(error.localizedDescription)")
        self.isRecording = false
        self.isInitiating = false
        self.currentLevel = 0
      }
    }
  }
  
  nonisolated func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didUpdateAudioLevel level: Float, peakLevel: Float) {
    Task { @MainActor in
      // Update the current level for waveform visualization
      self.currentLevel = CGFloat(level)
    }
  }
  
  nonisolated func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didFinishRecordingAt url: URL) {
    Task { @MainActor in
      print("AudioRecorderAdapter: Recording finished at \(url)")
      self.currentRecordingURL = url
      
      // Call completion handler if waiting
      if let handler = self.recordingCompletionHandler {
        handler(url)
        self.recordingCompletionHandler = nil
      }
      
      // Reset state
      self.isRecording = false
      self.isInitiating = false
    }
  }
  
  nonisolated func AudioRecorderUpdatedDidFinishPlayback(_ recorder: AudioRecorderUpdated) {
    // Not used in current implementation
    Task { @MainActor in
      print("AudioRecorderAdapter: Playback finished")
    }
  }
}
