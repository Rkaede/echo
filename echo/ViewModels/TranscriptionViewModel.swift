import Combine
import Foundation

@MainActor
class TranscriptionViewModel: ObservableObject {
  private let settingsManager: SettingsManager
  private let appState: AppState
  private let transcriptionService: TranscriptionService

  private var cancellables = Set<AnyCancellable>()
  private lazy var fnCoordinator = FnRecordingCoordinator(
    start: { [weak self] in await self?.startRecordingOnly() },
    stop: { [weak self] in await self?.stopRecordingOnly() },
    cancel: { [weak self] in
      guard let self, [.recording, .confirmingCancel].contains(self.appState.status) else { return }
      _ = await self.transcriptionService.cancelRecording()
    },
    setToggleMode: { [weak self] in
      guard let self, [.initiatingRecording, .recording].contains(self.appState.status) else { return }
      self.appState.setRecordingMode(.toggle)
    }
  )

  func handleFnAction(_ action: FnRecordingGesture.Action) {
    if appState.status == .confirmingCancel { appState.returnFromConfirmation() }
    fnCoordinator.handle(action)
  }

  var canStartFnRecording: Bool { fnCoordinator.canStart }

  init(appState: AppState, settingsManager: SettingsManager, transcriptionService: TranscriptionService? = nil) {
    self.appState = appState
    self.settingsManager = settingsManager
    self.transcriptionService = transcriptionService ?? TranscriptionService(appState: appState)
  }

  convenience init(appState: AppState, transcriptionService: TranscriptionService? = nil) {
    self.init(appState: appState, settingsManager: SettingsManager.shared, transcriptionService: transcriptionService)
  }

  var hasAPIKey: Bool {
    settingsManager.hasAPIKey
  }

  var apiKey: String {
    get { settingsManager.apiKey }
    set { settingsManager.apiKey = newValue }
  }

  func saveAPIKey() {
    // This now happens automatically through the settings manager
  }

  func toggleRecording() async {
    print("TranscriptionViewModel: toggleRecording called, current status: \(appState.status)")
    switch appState.status {
    case .idle, .error, .inserted, .cancelled, .noSpeechDetected:
      print("TranscriptionViewModel: Starting recording from \(appState.status) state")
      await startRecording()
    case .recording:
      print("TranscriptionViewModel: Stopping recording")
      await stopRecording()
    case .initiatingRecording, .processing, .postProcessing, .confirmingCancel:
      print("TranscriptionViewModel: Ignoring toggle, currently in \(appState.status) state")
      break
    }
    print("TranscriptionViewModel: toggleRecording completed")
  }
  
  func startRecordingOnly() async {
    // Allow immediate restart from transient completion states.
    switch appState.status {
    case .idle, .error, .inserted, .cancelled, .noSpeechDetected:
      await startRecording(mode: .pushToTalk)
    case .recording, .initiatingRecording, .processing, .postProcessing, .confirmingCancel:
      // Don't start if already recording or processing
      print("TranscriptionViewModel: Cannot start push-to-talk recording - already in \(appState.status) state")
      break
    }
  }
  
  func stopRecordingOnly() async {
    // Only stop recording if we're currently recording
    switch appState.status {
    case .recording:
      await stopRecording()
    case .idle, .error, .initiatingRecording, .processing, .postProcessing, .inserted, .cancelled,
      .noSpeechDetected, .confirmingCancel:
      // Don't stop if not recording
      print("TranscriptionViewModel: Cannot stop push-to-talk recording - currently in \(appState.status) state")
      break
    }
  }
  
  func cancelRecording() async {
    if fnCoordinator.cancelDuringStartup() { return }
    // Only cancel if we're currently recording, processing, or confirming cancel
    switch appState.status {
    case .recording, .processing, .confirmingCancel:
      print("TranscriptionViewModel: Cancelling recording from \(appState.status) state")
      let result = await transcriptionService.cancelRecording()
      switch result {
      case .success:
        print("TranscriptionViewModel: Recording cancelled successfully")
      case .failure:
        print("TranscriptionViewModel: Failed to cancel recording")
      }
    case .idle, .error, .initiatingRecording, .postProcessing, .inserted, .cancelled,
      .noSpeechDetected:
      // Don't cancel if not in a cancellable state
      print("TranscriptionViewModel: Cannot cancel recording - currently in \(appState.status) state")
      break
    }
  }

  private func startRecording(mode: RecordingMode = .toggle) async {
    let result = await transcriptionService.startRecording(mode: mode) { [weak self] in
      // Fn startup owns deferred stop/cancel intent until the service returns. Suppress
      // the sound even while the recording status still says the mic is ready.
      self?.fnCoordinator.hasPendingEndRequest == false
    }
    switch result {
    case .success:
      break // Service handles state updates
    case .failure:
      break // Service handles error reporting
    }
  }

  private func stopRecording() async {
    let result = await transcriptionService.stopRecordingAndTranscribe()
    switch result {
    case .success:
      break // Service handles state updates
    case .failure:
      break // Service handles error reporting
    }
  }

  var statusText: String {
    switch appState.status {
    case .idle:
      return "Ready"
    case .initiatingRecording:
      return "Starting..."
    case .recording:
      return "Recording..."
    case .processing:
      return "Processing..."
    case .postProcessing:
      return "Post-processing..."
    case .inserted:
      return "Inserted"
    case .cancelled:
      return "Cancelled"
    case .noSpeechDetected:
      return "No speech detected"
    case .confirmingCancel:
      return "Are you sure? (Esc)"
    case .error:
      return "Error: \(appState.errorMessage)"
    }
  }

  var buttonTitle: String {
    switch appState.status {
    case .recording:
      return "Stop"
    case .processing:
      return "Processing..."
    case .cancelled:
      return "Cancelled"
    case .confirmingCancel:
      return "Confirming..."
    default:
      return "Record"
    }
  }

  var isButtonDisabled: Bool {
    switch appState.status {
    case .processing, .postProcessing, .initiatingRecording, .confirmingCancel:
      return true
    default:
      // Only check API key - microphone permission will be requested when needed
      return !hasAPIKey
    }
  }
}
