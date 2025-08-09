import Foundation
import Combine

@MainActor
class TranscriptionService: ObservableObject {
  private let settingsManager = SettingsManager.shared
  private let audioRecorder = AudioRecorder()
  private let apiClient = GroqAPIClient.shared
  private let appState: AppState
  private let pasteService = PasteService.shared
  
  private var cancellables = Set<AnyCancellable>()
  private var isCancelled = false
  
  init(appState: AppState) {
    self.appState = appState
    // Monitor recording state changes
    audioRecorder.$isRecording
      .sink { [weak self] isRecording in
        if isRecording {
          self?.appState.updateStatus(.recording)
        }
      }
      .store(in: &cancellables)
  }
  
  // MARK: - Public Interface
  
  func startRecording(mode: RecordingMode = .toggle) async -> TranscriptionServiceResult {
    // Reset cancellation flag for new recording
    isCancelled = false
    
    // Set recording mode in app state
    appState.setRecordingMode(mode)
    
    // Ensure API key is loaded before starting recording
    settingsManager.ensureAPIKeyLoaded()
    
    // Check if we have an API key after loading
    guard settingsManager.hasAPIKey else {
      let error = TranscriptionError.noAPIKey
      appState.setError(error.localizedDescription)
      return .failure(error)
    }
    
    // Request microphone permission if needed
    let hasAudioPermission = await audioRecorder.requestPermission()
    guard hasAudioPermission else {
      let error = TranscriptionError.noMicrophonePermission
      appState.setError(error.localizedDescription)
      return .failure(error)
    }
    
    do {
      print("TranscriptionService: Starting recording")
      appState.updateStatus(.initiatingRecording)
      appState.transcriptionText = ""
      try await audioRecorder.startRecording()
      
      // Update current input device in AppState
      appState.currentInputDevice = audioRecorder.getCurrentInputDevice()
      
      print("TranscriptionService: Recording started successfully")
      appState.updateStatus(.recording)
      return .success(())
      
    } catch {
      print("TranscriptionService: Failed to start recording: \(error)")
      
      // If we get an "already recording" error, try to clean up and reset
      if let recordingError = error as? RecordingError, recordingError == .alreadyRecording {
        print("TranscriptionService: Already recording error detected, attempting cleanup")
        await audioRecorder.cancelRecording()
        appState.resetToIdle()
        
        // Try once more after cleanup
        do {
          print("TranscriptionService: Retrying recording after cleanup")
          try await audioRecorder.startRecording()
          appState.currentInputDevice = audioRecorder.getCurrentInputDevice()
          appState.updateStatus(.recording)
          return .success(())
        } catch {
          print("TranscriptionService: Retry also failed: \(error)")
        }
      }
      
      let transcriptionError = TranscriptionError.recordingFailed(error)
      appState.setError(transcriptionError.localizedDescription)
      return .failure(transcriptionError)
    }
  }
  
  func stopRecordingAndTranscribe() async -> TranscriptionServiceResult {
    print("TranscriptionService: Stopping recording")
    guard let audioFileURL = await audioRecorder.stopRecording() else {
      print("TranscriptionService: Failed to stop recording")
      let error = TranscriptionError.recordingStopFailed
      appState.setError(error.localizedDescription)
      return .failure(error)
    }
    
    print("TranscriptionService: Recording stopped, file at: \(audioFileURL)")
    appState.updateStatus(.processing)
    
    // Ensure cleanup happens regardless of success or failure
    defer {
      audioRecorder.deleteRecording()
    }
    
    do {
      print("TranscriptionService: Starting transcription")
      let result = try await apiClient.transcribeAudio(fileURL: audioFileURL, apiKey: settingsManager.apiKey)
      print("TranscriptionService: Transcription completed: '\(result.text.prefix(50))...'")
      
      // Check if cancelled after API call completes
      if isCancelled {
        print("TranscriptionService: Ignoring transcription result due to cancellation")
        return .success(())
      }
      
      let transcribedText = result.text.trimmingCharacters(in: .whitespaces)
      appState.transcriptionText = transcribedText
      
      // Check cancellation before auto-paste
      if isCancelled {
        print("TranscriptionService: Skipping auto-paste due to cancellation")
        return .success(())
      }
      
      // Automatically paste the transcribed text
      if !transcribedText.isEmpty {
        let pasteSuccess = await performAutoPaste(text: transcribedText)
        if !pasteSuccess {
          print("TranscriptionService: Auto-paste failed, but transcription succeeded")
        }
      } else {
        print("TranscriptionService: No text to paste (empty result)")
      }
      
      // Final check before marking as inserted
      if isCancelled {
        print("TranscriptionService: Skipping completion status due to cancellation")
        return .success(())
      }
      
      appState.updateStatus(.inserted)
      print("TranscriptionService: Transcription workflow completed")
      
      return .success(())
      
    } catch {
      print("TranscriptionService: Transcription failed: \(error)")
      let transcriptionError = TranscriptionError.transcriptionFailed(error)
      appState.setError(transcriptionError.localizedDescription)
      return .failure(transcriptionError)
    }
  }
  
  func cancelRecording() async -> TranscriptionServiceResult {
    print("TranscriptionService: Cancelling recording")
    
    // Mark as cancelled to prevent completion of ongoing operations
    isCancelled = true
    
    switch appState.status {
    case .recording:
      // Cancel active recording
      await audioRecorder.cancelRecording()
      print("TranscriptionService: Active recording cancelled")
      
    case .processing:
      // For processing state, we can't cancel the API call, but we'll ignore the result
      print("TranscriptionService: Cannot cancel API transcription in progress, will ignore result")
      
    case .confirmingCancel:
      // For confirming cancel, we need to check what the previous state was
      if let previousStatus = appState.previousStatusBeforeConfirmation {
        print("TranscriptionService: Cancelling from confirmation, previous state was: \(previousStatus)")
        if previousStatus == .recording {
          // We were recording, so cancel the recording
          await audioRecorder.cancelRecording()
          print("TranscriptionService: Cancelled active recording from confirmation")
        } else {
          // We were processing, just mark as cancelled
          print("TranscriptionService: Cancelled processing from confirmation")
        }
      } else {
        // Fallback: assume we were recording and try to cancel
        print("TranscriptionService: No previous status found, assuming recording state")
        await audioRecorder.cancelRecording()
      }
      
    default:
      print("TranscriptionService: No active recording to cancel (status: \(appState.status))")
    }
    
    // Update app state to cancelled
    appState.updateStatus(.cancelled)
    print("TranscriptionService: Recording cancelled")
    
    return .success(())
  }
  
  // MARK: - Private Methods
  
  private func performAutoPaste(text: String) async -> Bool {
    print("TranscriptionService: Attempting to paste transcribed text")
    
    // Check and request accessibility permissions if needed
    if !pasteService.checkAccessibilityPermissions() {
      print("TranscriptionService: No accessibility permissions, requesting...")
      // Request permission - this should show the system prompt
      let granted = pasteService.promptForAccessibilityPermission()
      if !granted {
        print("TranscriptionService: Accessibility permission denied")
        appState.setError("Please grant accessibility permissions in System Settings to enable auto-paste")
        // Also open the preferences to make it easier
        pasteService.openAccessibilityPreferences()
        return false
      } else {
        print("TranscriptionService: Accessibility permission granted, attempting paste")
        let success = await pasteService.pasteToFocusedApp(text)
        print("TranscriptionService: Paste success: \(success)")
        return success
      }
    } else {
      print("TranscriptionService: Accessibility permissions already granted, pasting")
      let success = await pasteService.pasteToFocusedApp(text)
      print("TranscriptionService: Paste success: \(success)")
      return success
    }
  }
}

// MARK: - Result Types

enum TranscriptionServiceResult {
  case success(Void)
  case failure(TranscriptionError)
}

enum TranscriptionError: LocalizedError {
  case noAPIKey
  case noMicrophonePermission
  case recordingFailed(Error)
  case recordingStopFailed
  case transcriptionFailed(Error)
  
  var errorDescription: String? {
    switch self {
    case .noAPIKey:
      return "Please add your Groq API key in Settings"
    case .noMicrophonePermission:
      return "Please grant microphone permission to record audio"
    case .recordingFailed(let error):
      return "Failed to start recording: \(error.localizedDescription)"
    case .recordingStopFailed:
      return "Failed to stop recording"
    case .transcriptionFailed(let error):
      return "Transcription failed: \(error.localizedDescription)"
    }
  }
}