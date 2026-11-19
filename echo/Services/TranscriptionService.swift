import AVFoundation
import AppKit
import Combine
import Foundation

@MainActor
class TranscriptionService: ObservableObject {
  private let settingsManager = SettingsManager.shared
  private let audioRecorder = AudioRecorder()
  private let apiClient = APIClient.shared
  private let profilesService = ProfilesService.shared
  private let postProcessor = PostProcessingService.shared
  private let failedRecordings = FailedRecordingStore.shared
  private let appState: AppState
  private let pasteService = PasteService.shared
  private let historyManager = HistoryManager.shared
  private let soundManager = SoundManager.shared
  private let notesModeService = NotesModeService.shared
  private let loggerCategory = "TranscriptionService"

  private var isCancelled = false
  private var transcriptionTask: Task<TranscriptionServiceResult, Never>?
  private var transcriptionToken: UUID?

  private var recordingStartTime: Date?
  private var transcriptionStartTime: Date?

  init(appState: AppState) {
    // The waveform reads mic levels straight from AudioLevelMeter, so nothing is forwarded
    // into AppState here.
    self.appState = appState
  }

  // MARK: - Public Interface

  nonisolated static func recordingStartSoundSettleDelayNanoseconds(
    inputIsWireless: Bool
  ) -> UInt64? {
    inputIsWireless ? 250_000_000 : nil
  }

  /// About one display frame. Starting the mic (~140ms) and cold-starting the playback engine
  /// for the start sound (70–150ms) both block the main thread, so each is preceded by a
  /// yield this long to let the overlay render the new status before the stall.
  nonisolated static let overlayRenderYieldNanoseconds: UInt64 = 16_000_000

  func startRecording(
    mode: RecordingMode = .toggle,
    shouldPlayStartSound: () -> Bool = { true }
  ) async -> TranscriptionServiceResult {
    log("------------------------------------------------------", category: loggerCategory, level: .info)
    log("startRecording called with mode: \(mode)", category: loggerCategory, level: .info)

    // Cancel any in-flight transcription task from a previous session
    transcriptionTask?.cancel()
    transcriptionTask = nil
    transcriptionToken = nil

    // Reset cancellation flag for new recording
    isCancelled = false

    // Set recording mode in app state
    appState.setRecordingMode(mode)

    // Update status immediately so animation starts before any blocking work
    appState.updateStatus(.initiatingRecording)
    appState.transcriptionText = ""

    // Give the overlay a frame to render "Preparing mic..." before the blocking mic start
    try? await Task.sleep(nanoseconds: Self.overlayRenderYieldNanoseconds)

    // Ensure API key is loaded before starting recording
    log("Ensuring API key is loaded...", category: loggerCategory, level: .debug)
    settingsManager.ensureAPIKeyLoaded()

    // Check we have the key for the provider the active model runs on
    let transcriptionProvider = TranscriptionData.provider(for: activeTranscriptionModel)
    guard settingsManager.hasAPIKey(for: transcriptionProvider) else {
      log(
        "No \(transcriptionProvider.displayName) API key found! Please configure in Settings.",
        category: loggerCategory, level: .error)
      let error = TranscriptionError.noAPIKey(transcriptionProvider)
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

      // Bluetooth inputs need time to stabilize in input mode before the start sound
      // plays — playing too early triggers "reconfig pending" errors. Wired inputs
      // don't mode-switch, so they only wait a frame: enough for the overlay to show
      // "Speak now" before the playback engine's cold start blocks the main thread.
      let startSoundDelay = Self.recordingStartSoundSettleDelayNanoseconds(
        inputIsWireless: audioRecorder.isCurrentCaptureInputWireless()
      ) ?? Self.overlayRenderYieldNanoseconds
      try? await Task.sleep(nanoseconds: startSoundDelay)

      // NOW play the start sound (if enabled), unless the recording was already stopped or
      // cancelled during the delay. The device is already in input mode, so playing a short
      // beep won't trigger another disruptive mode switch on Bluetooth devices
      if appState.status == .recording && shouldPlayStartSound() {
        soundManager.playRecordingStartSound()
      }

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
    // Capture the destination before stopping the mic or awaiting the network. Later
    // app switches must not send the transcript into an unrelated application.
    let targetApp = NSWorkspace.shared.frontmostApplication
    let recordingEndTime = Date()

    guard let audioFileURL = await audioRecorder.stopRecording() else {
      log("Failed to stop recording", category: loggerCategory, level: .error)
      let error = TranscriptionError.recordingStopFailed
      appState.setError(error.localizedDescription)
      return .failure(error)
    }

    if isCancelled {
      log("Stop recording aborted due to cancellation", category: loggerCategory, level: .info)
      audioRecorder.deleteRecording()
      return .success(())
    }

    // Calculate recording duration
    let recordingDuration = recordingStartTime.map { recordingEndTime.timeIntervalSince($0) } ?? 0

    // Decide whether this is worth uploading at all. Whisper invents stock phrases when
    // handed silence, so an accidental trigger would otherwise paste "Thank you." into
    // whatever app is focused.
    let signal = audioRecorder.recordingSignal(duration: recordingDuration)
    log(
      String(
        format: "Recording signal: peak %.1f dBFS, %ld voiced frames over %.2fs",
        signal.peakPowerDecibels, signal.voicedFrameCount, signal.duration
      ),
      category: loggerCategory,
      level: .info
    )

    if case .reject(let reason) = SpeechGate.preflightDecision(for: signal) {
      log(
        "Skipping transcription: \(reason.logDescription)",
        category: loggerCategory,
        level: .info
      )
      audioRecorder.deleteRecording()
      notesModeService.discardPendingScreenshot()
      appState.updateStatus(.noSpeechDetected)
      return .success(())
    }

    log("Recording stopped, file at: \(audioFileURL)", category: loggerCategory, level: .info)
    appState.updateStatus(.processing)

    // Capture the screen right away (concurrently with the upload) so the notes
    // screenshot reflects what was visible while dictating
    if notesModeService.isActive {
      Task {
        await self.notesModeService.captureScreenshotForNextEntry()
      }
    }

    // Get active application context
    let activeApp = targetApp?.localizedName
    let targetProcessIdentifier = targetApp?.processIdentifier
    log("Paste target: \(targetApp?.bundleIdentifier ?? "unknown"), PID: \(targetProcessIdentifier ?? -1)",
        category: loggerCategory, level: .info)

    return await startPipeline(
      audioFileURL: audioFileURL, recordingDuration: recordingDuration, activeApp: activeApp,
      targetProcessIdentifier: targetProcessIdentifier)
  }

  /// Transcribes the most recent failed recording again, using the active profile, and
  /// pastes into the frontmost app. The recording is deleted once it transcribes.
  func retryFailedRecording() async -> TranscriptionServiceResult {
    guard let audioFileURL = failedRecordings.latest else { return .success(()) }
    switch appState.status {
    case .idle, .inserted, .cancelled, .noSpeechDetected, .error:
      break
    default:
      log("Not retrying while busy (\(appState.status))", category: loggerCategory, level: .info)
      return .success(())
    }

    let duration =
      (try? AVAudioFile(forReading: audioFileURL)).map {
        Double($0.length) / $0.processingFormat.sampleRate
      } ?? 0
    let targetApp = NSWorkspace.shared.frontmostApplication
    log(
      "Retrying failed recording \(audioFileURL.lastPathComponent) (\(Int(duration)) s)",
      category: loggerCategory, level: .info)

    isCancelled = false
    appState.updateStatus(.processing)
    return await startPipeline(
      audioFileURL: audioFileURL, recordingDuration: duration,
      activeApp: targetApp?.localizedName,
      targetProcessIdentifier: targetApp?.processIdentifier, retrying: true)
  }

  /// Runs the transcription pipeline as the current task, so a cancel or a newer recording
  /// supersedes it.
  private func startPipeline(
    audioFileURL: URL,
    recordingDuration: TimeInterval,
    activeApp: String?,
    targetProcessIdentifier: pid_t?,
    retrying: Bool = false
  ) async -> TranscriptionServiceResult {
    let token = UUID()
    transcriptionToken = token

    transcriptionTask?.cancel()
    transcriptionTask = Task { [audioFileURL, recordingDuration, activeApp, token] in
      await self.runTranscriptionPipeline(
        audioFileURL: audioFileURL,
        recordingDuration: recordingDuration,
        activeApp: activeApp,
        targetProcessIdentifier: targetProcessIdentifier,
        token: token,
        retrying: retrying
      )
    }

    let result = await transcriptionTask?.value ?? .success(())
    if transcriptionToken == token {
      transcriptionTask = nil
    }
    return result
  }

  func cancelRecording() async -> TranscriptionServiceResult {
    log("Cancelling recording", category: loggerCategory, level: .info)

    // Mark as cancelled to prevent completion of ongoing operations
    isCancelled = true
    transcriptionToken = nil
    transcriptionTask?.cancel()
    transcriptionTask = nil

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

    // A screenshot captured for this recording will never get a transcription
    notesModeService.discardPendingScreenshot()

    return .success(())
  }

  // MARK: - Private Methods

  private func runTranscriptionPipeline(
    audioFileURL: URL,
    recordingDuration: TimeInterval,
    activeApp: String?,
    targetProcessIdentifier: pid_t?,
    token: UUID,
    retrying: Bool = false
  ) async -> TranscriptionServiceResult {
    let localToken = token

    func shouldContinue(stage: String) -> Bool {
      if Task.isCancelled {
        log("Task cancelled during \(stage)", category: loggerCategory, level: .info)
        return false
      }
      if isCancelled {
        log("Cancelled flag set during \(stage)", category: loggerCategory, level: .info)
        return false
      }
      if transcriptionToken != localToken {
        log("Stale transcription task during \(stage)", category: loggerCategory, level: .info)
        return false
      }
      return true
    }

    // Ensure cleanup happens regardless of success or failure. A failed transcription keeps
    // a copy of the recording first (see the catch below); a retry's file belongs to
    // `failedRecordings`, which removes it once it transcribes.
    defer {
      if !retrying {
        audioRecorder.deleteRecording()
      }
    }

    do {
      if !shouldContinue(stage: "transcription start") {
        return .success(())
      }

      log("Starting transcription", category: loggerCategory, level: .info)
      transcriptionStartTime = Date()
      let uploadStartTime = Date()

      // Choose model from active profile when available
      let (resultWithTiming, modelToUse) = try await transcribeRecording(
        audioFileURL: audioFileURL, model: activeTranscriptionModel,
        recordingDuration: recordingDuration)

      if !shouldContinue(stage: "transcription response") {
        log(
          "Ignoring transcription result due to cancellation",
          category: loggerCategory,
          level: .warning
        )
        return .success(())
      }

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
        category: loggerCategory,
        level: .info
      )

      let transcribedText = resultWithTiming.result.text.trimmingCharacters(in: .whitespaces)

      // The energy gate cannot tell a quiet room from a noisy one, so give the model the
      // final say: if it flagged every segment as non-speech, the text is a hallucination.
      if case .reject(let reason) = SpeechGate.transcriptDecision(
        segments: resultWithTiming.result.segments
      ) {
        log(
          "Discarding transcription '\(transcribedText.prefix(40))': \(reason.logDescription)",
          category: loggerCategory,
          level: .info
        )
        appState.transcriptionText = ""
        notesModeService.discardPendingScreenshot()
        appState.updateStatus(.noSpeechDetected)
        return .success(())
      }

      appState.transcriptionText = transcribedText

      // Save successful transcription to history if enabled. The cleaned text is added to
      // the same row after post-processing.
      var historySave: (id: UUID, task: Task<Bool, Never>)?
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
            log(
              "Failed to save audio file, continuing without audio",
              category: loggerCategory,
              level: .warning
            )
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
          totalTranscriptionTime: totalTime,
          profileId: profilesService.activeProfile?.id
        )

        historySave = (historyEntryId, historyManager.saveTranscription(historyEntry))
        log(
          "Called saveTranscription for '\(transcribedText.prefix(30))...'\(audioFileReference != nil ? " with audio" : "")",
          category: loggerCategory,
          level: .info
        )
      } else {
        log(
          "History save skipped - isEmpty: \(!transcribedText.isEmpty), enableHistory: \(settingsManager.enableHistory)",
          category: loggerCategory,
          level: .debug
        )
      }

      // A retried recording has transcribed (and been copied to history), so let it go.
      if retrying {
        failedRecordings.remove(audioFileURL)
      }

      if !shouldContinue(stage: "pre post-processing") {
        log("Skipping post-processing due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      var finalText = transcribedText

      // Optional post-processing based on active profile
      if let profile = profilesService.activeProfile, profile.postProcessingEnabled,
        !transcribedText.isEmpty
      {
        appState.updateStatus(.postProcessing)
        let ppModel = PostProcessingModelOption.resolve(profile.postProcessingModel).value
        do {
          let processed = try await postProcessor.processText(
            transcribedText, promptTemplate: profile.postProcessingPrompt,
            postProcessingModel: ppModel)
          if shouldContinue(stage: "post-processing") {
            finalText = processed
            appState.transcriptionText = processed
            if let historySave {
              historyManager.savePostProcessing(
                id: historySave.id, text: processed, model: ppModel, after: historySave.task)
            }
          }
        } catch {
          log("Post-processing failed: \(error)", category: loggerCategory, level: .warning)
          // Fall back to raw text; proceed without blocking
        }
      }

      if !shouldContinue(stage: "auto-paste") {
        log("Skipping auto-paste due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      // In notes mode the text goes into the note instead of the focused app
      if !finalText.isEmpty {
        if notesModeService.isActive {
          notesModeService.addTranscription(finalText)
          soundManager.playTranscriptionCompleteSound()
        } else {
          let outcome = await pasteService.pasteToFocusedApp(
            finalText, targetProcessIdentifier: targetProcessIdentifier,
            restoreClipboard: settingsManager.restoreClipboard)
          guard shouldContinue(stage: "paste result") else { return .success(()) }
          switch outcome {
          case .posted:
            soundManager.playTranscriptionCompleteSound()
          case .cancelled:
            return .success(())
          case .failed(let failure, let copied):
            if failure == .accessibilityPermission {
              pasteService.promptForAccessibilityPermission()
            }
            let message = failure.errorMessage(
              copiedToClipboard: copied, historyEnabled: settingsManager.enableHistory)
            let error = TranscriptionError.autoPasteFailed(message)
            appState.setError(message, recoveryHint: failure.recoveryHint(
              copiedToClipboard: copied, historyEnabled: settingsManager.enableHistory))
            return .failure(error)
          }
        }
      } else {
        log("No text to paste (empty result)", category: loggerCategory, level: .warning)
      }

      if !shouldContinue(stage: "completion") {
        log("Skipping completion status due to cancellation", category: loggerCategory, level: .warning)
        return .success(())
      }

      appState.updateStatus(.inserted)
      log("Transcription workflow completed", category: loggerCategory, level: .info)
      log("------------------------------------------------------", category: loggerCategory, level: .info)

      return .success(())

    } catch {
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        log("Transcription task cancelled", category: loggerCategory, level: .info)
        return .success(())
      }

      if !shouldContinue(stage: "error handling") {
        return .success(())
      }

      log("Transcription failed: \(error)", category: loggerCategory, level: .error)
      let transcriptionError = TranscriptionError.transcriptionFailed(error)
      // Keep the recording so it can be retried; a long dictation is too costly to lose.
      if retrying || failedRecordings.save(audioFileURL) != nil {
        appState.setError(
          transcriptionError.localizedDescription + " The recording was kept.",
          recoveryHint: "Retry from the Echo menu", title: "Transcription failed")
      } else {
        appState.setError(transcriptionError.localizedDescription)
      }
      return .failure(transcriptionError)
    }
  }
}

// MARK: - Result Types

enum TranscriptionServiceResult {
  case success(Void)
  case failure(TranscriptionError)
}

extension TranscriptionService {
  /// The transcription model for the active profile, or the legacy global setting.
  var activeTranscriptionModel: String {
    profilesService.activeProfile?.transcriptionModel ?? settingsManager.selectedModel
  }

  /// How long to wait for an OpenRouter transcription before falling back to Groq Whisper.
  /// MAI-Transcribe-2's median was 0.8 s in Echo's benchmark, but about one request in 80
  /// took over 15 s. Longer recordings take a little longer to transcribe. It is applied as
  /// the request's idle timeout, so a long upload that is still sending does not trip it.
  nonisolated static func fallbackTimeout(forRecordingDuration duration: TimeInterval)
    -> TimeInterval
  {
    4 + max(0, duration) / 30
  }

  /// Transcribes a recording of any length. One over `LongRecordingSplitter.maxPartSeconds`
  /// is cut into parts at pauses, which are transcribed a few at a time and joined.
  func transcribeRecording(
    audioFileURL: URL, model: String, recordingDuration: TimeInterval
  ) async throws -> (TranscriptionResultWithTiming, String) {
    var parts: [LongRecordingSplitter.Part] = []
    if recordingDuration > LongRecordingSplitter.maxPartSeconds {
      parts = try await Task.detached(priority: .userInitiated) {
        try LongRecordingSplitter.split(audioFileURL)
      }.value
    }
    guard parts.count > 1 else {
      return try await transcribe(
        audioFileURL: audioFileURL, model: model, recordingDuration: recordingDuration)
    }
    defer {
      for part in parts { try? FileManager.default.removeItem(at: part.url) }
    }
    log(
      "Transcribing a \(Int(recordingDuration)) s recording in \(parts.count) parts",
      category: loggerCategory, level: .info)

    // A few parts at a time: each waits for a slot before starting.
    let maxConcurrent = 3
    let results = try await withThrowingTaskGroup(
      of: (Int, TranscriptionResultWithTiming, String).self
    ) { group in
      var results = [(TranscriptionResultWithTiming, String)?](repeating: nil, count: parts.count)
      for (index, part) in parts.enumerated() {
        if index >= maxConcurrent, let (done, result, used) = try await group.next() {
          results[done] = (result, used)
        }
        group.addTask {
          let (result, used) = try await self.transcribe(
            audioFileURL: part.url, model: model, recordingDuration: part.duration)
          return (index, result, used)
        }
      }
      for try await (done, result, used) in group {
        results[done] = (result, used)
      }
      return results.compactMap { $0 }
    }

    return Self.combine(
      results.map(\.0), models: results.map(\.1), partDurations: parts.map(\.duration))
  }

  /// Joins the results for consecutive parts of one recording. A part the speech gate
  /// rejects (all silence, where Whisper invents text) adds no text, but its segments are
  /// kept, so a recording that is silent throughout is still rejected as a whole.
  nonisolated static func combine(
    _ parts: [TranscriptionResultWithTiming], models: [String], partDurations: [TimeInterval]
  ) -> (TranscriptionResultWithTiming, String) {
    var texts: [String] = []
    var segments: [TranscriptionResult.Segment] = []
    var offset: TimeInterval = 0
    for (part, duration) in zip(parts, partDurations) {
      if case .transcribe = SpeechGate.transcriptDecision(segments: part.result.segments) {
        let text = part.result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { texts.append(text) }
      }
      for segment in part.result.segments ?? [] {
        segments.append(
          TranscriptionResult.Segment(
            id: segments.count, start: segment.start + offset, end: segment.end + offset,
            text: segment.text, averageLogProbability: segment.averageLogProbability,
            noSpeechProbability: segment.noSpeechProbability,
            compressionRatio: segment.compressionRatio))
      }
      offset += duration
    }

    var modelsUsed: [String] = []
    for model in models where !modelsUsed.contains(model) { modelsUsed.append(model) }

    let result = TranscriptionResult(
      text: texts.joined(separator: " "), language: parts.first?.result.language,
      duration: offset, segments: segments.isEmpty ? nil : segments)
    let timing = TranscriptionResultWithTiming(
      result: result,
      uploadTime: parts.reduce(0) { $0 + $1.uploadTime },
      downloadTime: parts.reduce(0) { $0 + $1.downloadTime },
      totalNetworkTime: parts.reduce(0) { $0 + $1.totalNetworkTime })
    return (timing, modelsUsed.joined(separator: " + "))
  }

  /// Transcribes with the given model. If it runs on OpenRouter and fails or exceeds the
  /// fallback timeout, retries once with Whisper on Groq when a Groq key is available.
  /// Returns the result and the model that produced it, for history.
  func transcribe(
    audioFileURL: URL, model: String, recordingDuration: TimeInterval
  ) async throws -> (TranscriptionResultWithTiming, String) {
    let option = TranscriptionData.option(for: model)
    let provider = option?.provider ?? .groq

    guard provider == .openRouter else {
      let result = try await apiClient.transcribeAudio(
        fileURL: audioFileURL, apiKey: settingsManager.apiKey(for: provider), model: model,
        provider: provider, extraFields: option?.extraFields ?? [:])
      return (result, model)
    }

    do {
      let result = try await apiClient.transcribeAudio(
        fileURL: audioFileURL, apiKey: settingsManager.apiKey(for: .openRouter), model: model,
        provider: .openRouter, extraFields: option?.extraFields ?? [:],
        timeout: Self.fallbackTimeout(forRecordingDuration: recordingDuration))
      return (result, model)
    } catch {
      guard !Task.isCancelled, settingsManager.hasAPIKey(for: .groq) else { throw error }
      log(
        "\(model) failed or timed out (\(error.localizedDescription)); falling back to \(TranscriptionData.fallbackModel)",
        category: loggerCategory, level: .warning)
      let fallback = TranscriptionData.fallbackModel
      let result = try await apiClient.transcribeAudio(
        fileURL: audioFileURL, apiKey: settingsManager.apiKey(for: .groq), model: fallback,
        provider: .groq, extraFields: TranscriptionData.option(for: fallback)?.extraFields ?? [:])
      return (result, fallback)
    }
  }
}

enum TranscriptionError: LocalizedError {
  case noAPIKey(APIProvider)
  case noMicrophonePermission
  case recordingFailed(Error)
  case recordingStopFailed
  case transcriptionFailed(Error)
  case autoPasteFailed(String)

  var errorDescription: String? {
    switch self {
    case .noAPIKey(let provider):
      return provider.missingKeyMessage
    case .noMicrophonePermission:
      return "Please grant microphone permission to record audio"
    case .recordingFailed(let error):
      return "Failed to start recording: \(error.localizedDescription)"
    case .recordingStopFailed:
      return "Failed to stop recording"
    case .transcriptionFailed(let error):
      return "Transcription failed: \(error.localizedDescription)"
    case .autoPasteFailed(let message):
      return message
    }
  }
}
