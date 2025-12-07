import AppKit
import Combine
import Foundation

@MainActor
class TranscriptionService: ObservableObject {
  private let settingsManager = SettingsManager.shared
  private let audioRecorder = AudioRecorder()
  private let apiClient = GroqAPIClient.shared
  private let profilesService = ProfilesService.shared
  private let postProcessor = PostProcessingService.shared
  private let appState: AppState
  private let pasteService = PasteService.shared
  private let historyManager = HistoryManager.shared
  private let soundManager = SoundManager.shared
  private let loggerCategory = "TranscriptionService"

  private var cancellables = Set<AnyCancellable>()
  private var isCancelled = false

  private var recordingStartTime: Date?
  private var transcriptionStartTime: Date?

  init(appState: AppState) {
    self.appState = appState

    // Monitor audio level changes for waveform visualization
    audioRecorder.$currentLevel
      .sink { [weak self] level in
        print("[WAVEFORM DEBUG] TranscriptionService received level: \(level)")
        self?.appState.currentInputLevel = level
      }
      .store(in: &cancellables)

    // Forward waveform samples to AppState
    audioRecorder.$waveformSamples
      .sink { [weak self] samples in
        self?.appState.waveformSamples = samples
      }
      .store(in: &cancellables)
  }

  // MARK: - Public Interface

  func startRecording(mode: RecordingMode = .toggle) async -> TranscriptionServiceResult {
    log("------------------------------------------------------", category: loggerCategory, level: .info)
    log("startRecording called with mode: \(mode)", category: loggerCategory, level: .info)

    // Reset cancellation flag for new recording
    isCancelled = false

    // Set recording mode in app state
    appState.setRecordingMode(mode)

    // Update status immediately so animation starts before any blocking work
    appState.updateStatus(.initiatingRecording)
    appState.transcriptionText = ""

    // Ensure API key is loaded before starting recording
    log("Ensuring API key is loaded...", category: loggerCategory, level: .debug)
    settingsManager.ensureAPIKeyLoaded()

    // Check if we have an API key after loading
    guard settingsManager.hasAPIKey else {
      log("No API key found! Please configure in Settings.", category: loggerCategory, level: .error)
      let error = TranscriptionError.noAPIKey
      appState.setError(error.localizedDescription)
      return .failure(error)
    }
    log("API key found, proceeding with recording...", category: loggerCategory, level: .debug)

    // Request microphone permission if needed
    log("Requesting microphone permission...", category: loggerCategory, level: .debug)
    let hasAudioPermission = await audioRecorder.requestPermission()
    log("Microphone permission result: \(hasAudioPermission)", category: loggerCategory, level: .info)

    guard hasAudioPermission else {
      log("No microphone permission, showing error", category: loggerCategory, level: .error)
      let error = TranscriptionError.noMicrophonePermission
      appState.setError(error.localizedDescription)
      return .failure(error)
    }

    do {
      log("Have permission, starting recording", category: loggerCategory, level: .info)

      // Start recording FIRST (before playing any sounds)
      // This configures the audio device for input mode
      recordingStartTime = Date()
      try await audioRecorder.startRecording()

      // Update current input device in AppState
      appState.currentInputDevice = audioRecorder.getCurrentInputDevice()

      log("Recording started successfully", category: loggerCategory, level: .info)
      appState.updateStatus(.recording)

      // Wait 200-300ms for Bluetooth device to stabilize in input mode
      // This prevents "reconfig pending" errors when playing the start sound
      try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms

      // NOW play the start sound (if enabled)
      // The device is already in input mode, so playing a short beep won't
      // trigger another disruptive mode switch on Bluetooth devices
      soundManager.playRecordingStartSound()

      return .success(())

    } catch {
      log("Failed to start recording: \(error)", category: loggerCategory, level: .error)

      // If we get an "already recording" error, try to clean up and reset
      if let recordingError = error as? RecordingError, recordingError == .alreadyRecording {
        log("Already recording error detected, attempting cleanup", category: loggerCategory, level: .warning)
        await audioRecorder.cancelRecording()
        appState.resetToIdle()

        // Try once more after cleanup
        do {
          log("Retrying recording after cleanup", category: loggerCategory, level: .info)
          recordingStartTime = Date()
          try await audioRecorder.startRecording()
          appState.currentInputDevice = audioRecorder.getCurrentInputDevice()
          appState.updateStatus(.recording)

          return .success(())
        } catch {
          log("Retry also failed: \(error)", category: loggerCategory, level: .error)
        }
      }

      let transcriptionError = TranscriptionError.recordingFailed(error)
      appState.setError(transcriptionError.localizedDescription)
      return .failure(transcriptionError)
    }
  }

  func stopRecordingAndTranscribe() async -> TranscriptionServiceResult {
    log("Stopping recording", category: loggerCategory, level: .info)
    let recordingEndTime = Date()

    guard let audioFileURL = await audioRecorder.stopRecording() else {
      log("Failed to stop recording", category: loggerCategory, level: .error)
      let error = TranscriptionError.recordingStopFailed
      appState.setError(error.localizedDescription)
      return .failure(error)
    }

    log("Recording stopped, file at: \(audioFileURL)", category: loggerCategory, level: .info)
    appState.updateStatus(.processing)

    // Calculate recording duration
    let recordingDuration = recordingStartTime.map { recordingEndTime.timeIntervalSince($0) } ?? 0

    // Get active application context
    let activeApp = getActiveApplicationName()

    // Ensure cleanup happens regardless of success or failure
    defer {
      audioRecorder.deleteRecording()
    }

    do {
      log("Starting transcription", category: loggerCategory, level: .info)
      transcriptionStartTime = Date()
      let uploadStartTime = Date()

      // Choose model from active profile when available
      let modelToUse =
        profilesService.activeProfile?.transcriptionModel ?? settingsManager.selectedModel
      let resultWithTiming = try await apiClient.transcribeAudio(
        fileURL: audioFileURL, apiKey: settingsManager.apiKey, model: modelToUse)

      let transcriptionEndTime = Date()
      let totalTime = transcriptionEndTime.timeIntervalSince(transcriptionStartTime!)

      // Extract timing data
      let pureUploadTime = resultWithTiming.uploadTime
      let downloadTime = resultWithTiming.downloadTime
      let totalNetworkTime = resultWithTiming.totalNetworkTime

      // Legacy uploadTime calculation (for backward compatibility)
      let legacyUploadTime = transcriptionEndTime.timeIntervalSince(uploadStartTime)

      log(
        "Transcription completed: '\(resultWithTiming.result.text.prefix(50))...'",
        category: loggerCategory, level: .info
      )

      // Check if cancelled after API call completes
      if isCancelled {
        log("Ignoring transcription result due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      let transcribedText = resultWithTiming.result.text.trimmingCharacters(in: .whitespaces)
      appState.transcriptionText = transcribedText

      // Save successful transcription to history if enabled
      if !transcribedText.isEmpty && settingsManager.enableHistory {
        log("Preparing to save transcription to history", category: loggerCategory, level: .debug)

        // Generate ID for this history entry
        let historyEntryId = UUID()

        // Save audio file if enabled and we have the recording file
        var audioFileReference: String? = nil
        if settingsManager.saveAudioWithHistory {
          audioFileReference = AudioStorageManager.shared.saveAudioFile(
            from: audioFileURL, transcriptionId: historyEntryId)

          if audioFileReference != nil {
            log("Saved audio file for history entry", category: loggerCategory, level: .debug)
          } else {
            log("Failed to save audio file, continuing without audio", category: loggerCategory, level: .warning)
          }
        }

        let historyEntry = TranscriptionHistory(
          id: historyEntryId,
          transcribedText: transcribedText,
          duration: recordingDuration,
          audioFileReference: audioFileReference,
          languageDetected: resultWithTiming.result.language,
          modelUsed: modelToUse,
          applicationContext: activeApp,
          uploadTime: legacyUploadTime,  // Legacy field for backward compatibility
          pureUploadTime: pureUploadTime,
          downloadTime: downloadTime,
          totalNetworkTime: totalNetworkTime,
          groqProcessingTime: totalTime - legacyUploadTime,  // Server processing time
          totalTranscriptionTime: totalTime
        )

        historyManager.saveTranscription(historyEntry)
        log(
          "Called saveTranscription for '\(transcribedText.prefix(30))...'\(audioFileReference != nil ? " with audio" : "")",
          category: loggerCategory, level: .info
        )
      } else {
        log(
          "History save skipped - isEmpty: \(!transcribedText.isEmpty), enableHistory: \(settingsManager.enableHistory)",
          category: loggerCategory, level: .debug
        )
      }

      // Check cancellation before auto-paste
      if isCancelled {
        log("Skipping auto-paste due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      var finalText = transcribedText

      // Optional post-processing based on active profile
      if let profile = profilesService.activeProfile, profile.postProcessingEnabled,
        !transcribedText.isEmpty
      {
        appState.updateStatus(.postProcessing)
        let ppModel =
          profile.postProcessingModel.isEmpty
          ? PostProcessingModelOption.defaultOptionValue
          : profile.postProcessingModel
        do {
          let processed = try await postProcessor.processText(
            transcribedText, promptTemplate: profile.postProcessingPrompt,
            postProcessingModel: ppModel)
          // If not cancelled during processing, update final text and UI
          if !isCancelled {
            finalText = processed
            appState.transcriptionText = processed
          }
        } catch {
          log("Post-processing failed: \(error)", category: loggerCategory, level: .warning)
          // Fall back to raw text; proceed without blocking
        }
      }

      // Automatically paste the chosen text
      if !finalText.isEmpty {
        let pasteSuccess = await performAutoPaste(text: finalText)
        if !pasteSuccess {
          log("Auto-paste failed, but transcription succeeded", category: loggerCategory, level: .warning)
        } else {
          // Play completion sound only if paste was successful
          soundManager.playTranscriptionCompleteSound()
        }
      } else {
        log("No text to paste (empty result)", category: loggerCategory, level: .warning)
      }

      // Final check before marking as inserted
      if isCancelled {
        log("Skipping completion status due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      appState.updateStatus(.inserted)
      log("Transcription workflow completed", category: loggerCategory, level: .info)
      log("------------------------------------------------------", category: loggerCategory, level: .info)

      return .success(())

    } catch {
      log("Transcription failed: \(error)", category: loggerCategory, level: .error)
      let transcriptionError = TranscriptionError.transcriptionFailed(error)
      appState.setError(transcriptionError.localizedDescription)
      return .failure(transcriptionError)
    }
  }

  func cancelRecording() async -> TranscriptionServiceResult {
    log("Cancelling recording", category: loggerCategory, level: .info)

    // Mark as cancelled to prevent completion of ongoing operations
    isCancelled = true

    switch appState.status {
    case .recording:
      // Cancel active recording
      await audioRecorder.cancelRecording()
      log("Active recording cancelled", category: loggerCategory, level: .info)

    case .processing:
      // For processing state, we can't cancel the API call, but we'll ignore the result
      log("Cannot cancel API transcription in progress, will ignore result", category: loggerCategory, level: .warning)

    case .confirmingCancel:
      // For confirming cancel, we need to check what the previous state was
      if let previousStatus = appState.previousStatusBeforeConfirmation {
        log(
          "Cancelling from confirmation, previous state was: \(previousStatus)",
          category: loggerCategory, level: .debug
        )
        if previousStatus == .recording {
          // We were recording, so cancel the recording
          await audioRecorder.cancelRecording()
          log("Cancelled active recording from confirmation", category: loggerCategory, level: .info)
        } else {
          // We were processing, just mark as cancelled
          log("Cancelled processing from confirmation", category: loggerCategory, level: .info)
        }
      } else {
        // Fallback: assume we were recording and try to cancel
        log("No previous status found, assuming recording state", category: loggerCategory, level: .warning)
        await audioRecorder.cancelRecording()
      }

    default:
      log("No active recording to cancel (status: \(appState.status))", category: loggerCategory, level: .debug)
    }

    // Update app state to cancelled
    appState.updateStatus(.cancelled)
    log("Recording cancelled", category: loggerCategory, level: .info)

    return .success(())
  }

  // MARK: - Private Methods

  private func getActiveApplicationName() -> String? {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      return nil
    }
    return frontmostApp.localizedName
  }

  private func performAutoPaste(text: String) async -> Bool {
    log("Attempting to paste transcribed text", category: loggerCategory, level: .debug)

    // Check and request accessibility permissions if needed
    if !pasteService.checkAccessibilityPermissions() {
      log("No accessibility permissions, requesting...", category: loggerCategory, level: .warning)
      // Request permission - this should show the system prompt
      let granted = pasteService.promptForAccessibilityPermission()
      if !granted {
        log("Accessibility permission denied", category: loggerCategory, level: .error)
        appState.setError(
          "Please grant accessibility permissions in System Settings to enable auto-paste")
        // Also open the preferences to make it easier
        pasteService.openAccessibilityPreferences()
        return false
      } else {
        log("Accessibility permission granted, attempting paste", category: loggerCategory, level: .info)
        let success = await pasteService.pasteToFocusedApp(
          text, restoreClipboard: settingsManager.restoreClipboard)
        log("Paste success: \(success)", category: loggerCategory, level: .info)
        return success
      }
    } else {
      log("Accessibility permissions already granted, pasting", category: loggerCategory, level: .debug)
      let success = await pasteService.pasteToFocusedApp(
        text, restoreClipboard: settingsManager.restoreClipboard)
      log("Paste success: \(success)", category: loggerCategory, level: .info)
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
