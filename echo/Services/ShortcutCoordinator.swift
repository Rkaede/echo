import Combine
import Foundation

enum ProfileSwitchDirection {
  case next
  case previous
}

/// Turns global shortcuts into recording actions.
///
/// `GlobalShortcutMonitor` calls these handlers directly from its event tap. They used to be
/// relayed through @Published flags and `.onChange` modifiers on the Settings scene, which put
/// a SwiftUI update pass between every key press and the recording starting.
@MainActor
final class ShortcutCoordinator {
  private let appState: AppState
  private let viewModel: TranscriptionViewModel
  private let overlayController: OverlayPanelController
  private let shortcutMonitor: GlobalShortcutMonitor
  private let profilesService: ProfilesService
  private let notesModeService: NotesModeService
  private let settings: SettingsManager
  private var cancellables = Set<AnyCancellable>()

  init(
    appState: AppState,
    viewModel: TranscriptionViewModel,
    overlayController: OverlayPanelController,
    shortcutMonitor: GlobalShortcutMonitor,
    profilesService: ProfilesService,
    notesModeService: NotesModeService,
    settings: SettingsManager
  ) {
    self.appState = appState
    self.viewModel = viewModel
    self.overlayController = overlayController
    self.shortcutMonitor = shortcutMonitor
    self.profilesService = profilesService
    self.notesModeService = notesModeService
    self.settings = settings
  }

  func start() {
    shortcutMonitor.recordingStatus = { [weak self] in
      self?.appState.status ?? .idle
    }
    shortcutMonitor.canStartRecording = { [weak self] in
      self?.viewModel.canStartFnRecording ?? false
    }
    shortcutMonitor.onFnAction = { [weak self] action, keyTime in
      guard let self else { return }
      if action == .start {
        self.overlayController.noteShowRequested(keyTime: keyTime)
      }
      self.viewModel.handleFnAction(action)
    }
    shortcutMonitor.onCancelRecording = { [weak self] in
      self?.handleCancelRecording()
    }
    shortcutMonitor.onToggleNotesMode = { [weak self] in
      self?.handleNotesModeToggle()
    }
    shortcutMonitor.onDrawModifierChanged = { [weak self] isPressed in
      self?.notesModeService.setDrawModifierPressed(isPressed)
    }
    shortcutMonitor.onActivateNextProfile = { [weak self] in
      self?.handleProfileSwitch(direction: .next)
    }
    shortcutMonitor.onActivatePreviousProfile = { [weak self] in
      self?.handleProfileSwitch(direction: .previous)
    }
    // `$status` publishes from `willSet`, so the new value is passed in rather than read back
    appState.$status
      .sink { [weak self] status in
        self?.updateRecordingStateInGlobalShortcutMonitor(status: status)
        self?.updateRecordingStateInNotesMode(status: status)
      }
      .store(in: &cancellables)

    shortcutMonitor.loadNotesModeShortcut(settings.notesModeShortcut)
    shortcutMonitor.loadProfileNavigationShortcuts(
      previous: settings.previousProfileShortcut,
      next: settings.nextProfileShortcut
    )
  }

  // MARK: - Handlers

  private func handleNotesModeToggle() {
    print("ShortcutCoordinator: Notes mode shortcut triggered")
    notesModeService.toggle()
  }

  private func handleCancelRecording() {
    Task {
      print("ShortcutCoordinator: Escape key pressed - checking cancellation logic")

      if appState.status == .initiatingRecording {
        shortcutMonitor.resetFnGesture()
        await viewModel.cancelRecording()
        return
      }
      switch (appState.recordingMode, appState.status) {
      case (.toggle, .recording), (.toggle, .processing):
        if appState.status == .confirmingCancel {
          print("ShortcutCoordinator: Second Escape press - confirming cancellation")
          await viewModel.cancelRecording()
        } else {
          print("ShortcutCoordinator: First Escape press in toggle mode - showing confirmation")
          appState.startConfirmingCancel()
        }
      case (.pushToTalk, _), (nil, _):
        print("ShortcutCoordinator: Direct cancellation for push-to-talk mode")
        await viewModel.cancelRecording()
      default:
        if appState.status == .confirmingCancel {
          print("ShortcutCoordinator: Confirming cancellation")
          await viewModel.cancelRecording()
        } else {
          print(
            "ShortcutCoordinator: Escape pressed but no applicable cancellation logic for mode: \(String(describing: appState.recordingMode)), status: \(appState.status)"
          )
        }
      }
    }
  }

  private func handleProfileSwitch(direction: ProfileSwitchDirection) {
    guard appState.status == .recording else { return }

    let previousProfile = profilesService.activeProfile

    switch direction {
    case .next:
      profilesService.activateNextProfile()
    case .previous:
      profilesService.activatePreviousProfile()
    }

    // Show profile switch feedback if profile changed
    if let newProfile = profilesService.activeProfile,
      newProfile.id != previousProfile?.id
    {
      appState.showProfileSwitch(newProfile)
    }
  }

  private func updateRecordingStateInNotesMode(status: RecordingStatus) {
    switch status {
    case .recording:
      notesModeService.setRecording(true)
    case .confirmingCancel:
      // Unchanged: the recording carries on unless the cancel is confirmed
      break
    default:
      notesModeService.setRecording(false)
    }
  }

  private func updateRecordingStateInGlobalShortcutMonitor(status: RecordingStatus) {
    let isRecording = status == .initiatingRecording || status == .recording
      || status == .processing || status == .confirmingCancel
    shortcutMonitor.setRecording(isRecording)
    if ![.initiatingRecording, .recording, .confirmingCancel].contains(status) {
      shortcutMonitor.resetFnGesture()
    }
  }
}
