import AppKit
import SwiftUI

@main
struct EchoApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.openWindow) private var openWindow
  @StateObject private var globalShortcutMonitor = GlobalShortcutMonitor.shared
  @StateObject private var appState: AppState
  @StateObject private var viewModel: TranscriptionViewModel
  @StateObject private var settings = SettingsManager.shared
  @StateObject private var displayManager = DisplayManager.shared
  @StateObject private var tempFileManager = TempFileManager.shared
  @StateObject private var historyManager = HistoryManager.shared
  @StateObject private var profilesService = ProfilesService.shared
  @StateObject private var notesModeService = NotesModeService.shared
  @StateObject private var updateManager: UpdateManager
  private var overlayPanel: OverlayPanel?

  init() {
    LoggingService.shared.startConsoleCapture()

    let appState = AppState()
    _appState = StateObject(wrappedValue: appState)
    _viewModel = StateObject(wrappedValue: TranscriptionViewModel(appState: appState))

    // Start updates at launch even when no windows or recording overlay are opened.
    let updateManager = UpdateManager()
    _updateManager = StateObject(wrappedValue: updateManager)
  }

  var body: some Scene {
    onboardingWindow
    settingsWindow
    historyWindow
    menuBarExtra
  }

  private var onboardingWindow: some Scene {
    Window("Welcome to Echo", id: "onboarding") {
      OnboardingView()
    }
    .restorationBehavior(.disabled)
    .windowLevel(.floating)
    .defaultSize(
      width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight
    )
    .defaultLaunchBehavior(settings.hasCompletedOnboarding ? .suppressed : .presented)
  }

  private var settingsWindow: some Scene {
    Window("Settings", id: "settings") {
      SettingsView()
        .environmentObject(updateManager)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
          createOverlayPanel()
        }
    }
    .restorationBehavior(.disabled)
    .windowLevel(.floating)
    .defaultSize(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .defaultLaunchBehavior(.suppressed)
    .windowStyle(.hiddenTitleBar)
    .onChange(of: globalShortcutMonitor.shouldStartPushToTalk) { _, _ in handlePushToTalkStart() }
    .onChange(of: globalShortcutMonitor.shouldStopPushToTalk) { _, _ in handlePushToTalkStop() }
    .onChange(of: displayManager.shouldRepositionOverlay) { _, _ in repositionOverlayPanel() }
    .onChange(of: displayManager.spaceDidChange) { _, _ in handleSpaceChange() }
    .onChange(of: globalShortcutMonitor.shouldCancelRecording) { _, _ in handleCancelRecording() }
    .onChange(of: globalShortcutMonitor.shouldToggleNotesMode) { _, _ in handleNotesModeToggle() }
    .onChange(of: globalShortcutMonitor.shouldActivateNextProfile) { _, _ in handleProfileSwitch(direction: .next) }
    .onChange(of: globalShortcutMonitor.shouldActivatePreviousProfile) { _, _ in handleProfileSwitch(direction: .previous) }
    .onChange(of: historyManager.recentTranscriptions) { _, _ in updateHistoryState() }
    .onChange(of: historyManager.totalCount) { _, _ in updateHistoryState() }
    .onChange(of: appState.status) { old, new in
      updateRecordingStateInGlobalShortcutMonitor()
      handleOverlayVisibility(oldStatus: old, newStatus: new)
    }
    .onChange(of: profilesService.profiles) { _, _ in
      globalShortcutMonitor.loadProfileShortcuts(from: profilesService.profiles)
    }
    .onChange(of: globalShortcutMonitor.triggeredProfileId) { _, new in
      if let profileId = new {
        handleProfileShortcut(profileId: profileId)
      }
    }
  }

  private var historyWindow: some Scene {
    Window("Echo History", id: "history") {
      HistoryView()
        .environmentObject(appState)
    }
    .restorationBehavior(.disabled)
    .defaultSize(width: 900, height: 600)
    .defaultLaunchBehavior(.suppressed)
  }

  private var menuBarExtra: some Scene {
    MenuBarExtra("Echo", systemImage: "record.circle.fill") {
      menuContent
    }
    .menuBarExtraStyle(.menu)
  }

  // MARK: - Overlay Panel Management

  private func createOverlayPanel() {
    DispatchQueue.main.async {
      // Create panel if it doesn't exist
      if self.appDelegate.overlayPanel == nil {
        print("App: Creating overlay panel programmatically for fullscreen compatibility")

        let windowWidth: CGFloat = 300
        let windowHeight: CGFloat = 72

        // Get optimal position for overlay
        let displayManagerInstance = DisplayManager.shared
        let contentRect = displayManagerInstance.getOptimalOverlayPosition(
          windowWidth: windowWidth,
          windowHeight: windowHeight
        ) ?? NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        // Create the overlay panel with SwiftUI content wrapper
        let panel = OverlayPanel(contentRect: contentRect) {
          OverlayContentView()
            .environmentObject(self.appState)
            .environmentObject(self.profilesService)
        }

        // Set initial opacity based on status
        panel.alphaValue = self.appState.status == .idle ? 0 : 1.0

        // Show the panel
        panel.orderFrontRegardless()

        // Store reference
        self.appDelegate.overlayPanel = panel

        print("App: Overlay panel created successfully with level \(panel.level.rawValue)")

        // Initialize services after panel is created
        self.tempFileManager.performStartupCleanup()
        self.tempFileManager.startPeriodicCleanup()
        LoggingService.shared.cleanupOldLogs()
        self.globalShortcutMonitor.loadProfileShortcuts(from: self.profilesService.profiles)
        self.globalShortcutMonitor.loadNotesModeShortcut(self.settings.notesModeShortcut)
        self.globalShortcutMonitor.loadProfileNavigationShortcuts(
          previous: self.settings.previousProfileShortcut,
          next: self.settings.nextProfileShortcut
        )
      }
    }
  }

  private func handleProfileShortcut(profileId: String) {
    let startTime = Date()
    print("App: [PERF] Profile shortcut handler started at \(startTime)")

    Task {
      print("App: Profile shortcut triggered for profile \(profileId)")

      // Reset the trigger to allow the same shortcut to fire again
      globalShortcutMonitor.triggeredProfileId = nil

      // Activate the profile
      profilesService.activateProfile(id: profileId)

      // Ensure overlay panel is created
      createOverlayPanel()

      print("App: Triggering recording toggle for profile shortcut")
      let toggleStart = Date()
      await viewModel.toggleRecording()
      let toggleDuration = Date().timeIntervalSince(toggleStart)
      print("App: [PERF] toggleRecording took \(toggleDuration * 1000)ms")

      let totalDuration = Date().timeIntervalSince(startTime)
      print("App: [PERF] Profile shortcut handler total duration: \(totalDuration * 1000)ms")
    }
  }

  private func handlePushToTalkStart() {
    Task {
      print("App: Push-to-talk start triggered via GlobalShortcutMonitor")

      // Ensure overlay panel is created
      createOverlayPanel()

      print("App: Starting push-to-talk recording")
      await viewModel.startRecordingOnly()
    }
  }

  private func handlePushToTalkStop() {
    Task {
      print("App: Push-to-talk stop triggered via GlobalShortcutMonitor")
      print("App: Stopping push-to-talk recording")
      await viewModel.stopRecordingOnly()
    }
  }

  private func handleNotesModeToggle() {
    print("App: Notes mode shortcut triggered")

    // Ensure overlay panel is created
    createOverlayPanel()

    notesModeService.toggle()
  }

  private func handleCancelRecording() {
    Task {
      print("App: Escape key pressed - checking cancellation logic")

      // Ensure overlay panel is created
      createOverlayPanel()

      switch (appState.recordingMode, appState.status) {
      case (.toggle, .recording), (.toggle, .processing):
        if appState.status == .confirmingCancel {
          print("App: Second Escape press - confirming cancellation")
          await viewModel.cancelRecording()
        } else {
          print("App: First Escape press in toggle mode - showing confirmation")
          appState.startConfirmingCancel()
        }
      case (.pushToTalk, _), (nil, _):
        print("App: Direct cancellation for push-to-talk mode")
        await viewModel.cancelRecording()
      default:
        if appState.status == .confirmingCancel {
          print("App: Confirming cancellation")
          await viewModel.cancelRecording()
        } else {
          print(
            "App: Escape pressed but no applicable cancellation logic for mode: \(String(describing: appState.recordingMode)), status: \(appState.status)"
          )
        }
      }
    }
  }

  private func handleSpaceChange() {
    print("App: Space changed - ensuring overlay panel visibility")

    // Wait a bit for space transition to complete, then reposition
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.repositionOverlayPanel()

      // Double-check that panel is actually visible after repositioning
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let panel = self.appDelegate.overlayPanel {
          if !panel.isVisible {
            print("App: Overlay panel not visible after space change - recreating")
            self.appDelegate.overlayPanel = nil
            self.createOverlayPanel()
          }
        }
      }
    }
  }

  private func updateHistoryState() {
    appState.updateHistoryState(
      count: historyManager.totalCount, recent: historyManager.recentTranscriptions)
  }

  private func updateRecordingStateInGlobalShortcutMonitor() {
    let isRecording =
      appState.status == .recording || appState.status == .processing
      || appState.status == .confirmingCancel
    globalShortcutMonitor.setRecording(isRecording)
  }

  @MainActor
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

  private func handleOverlayVisibility(oldStatus: RecordingStatus, newStatus: RecordingStatus) {
    let startTime = Date()
    print("App: [PERF] handleOverlayVisibility started - oldStatus: \(oldStatus), newStatus: \(newStatus)")

    guard let panel = appDelegate.overlayPanel else {
      return
    }

    if newStatus == .idle && oldStatus != .idle {
      // Fade out to transparent when returning to idle (keep panel visible for fullscreen)
      print("App: Fading out overlay panel to transparent")
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        panel.animator().alphaValue = 0
      })
      let duration = Date().timeIntervalSince(startTime)
      print("App: [PERF] handleOverlayVisibility (fade out) took \(duration * 1000)ms")
    } else if newStatus != .idle && oldStatus == .idle {
      // Fade in - panel level is already set correctly
      print("App: Showing overlay panel")

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.2
        panel.animator().alphaValue = 1.0
      })

      // Ensure panel is front
      panel.orderFrontRegardless()

      let totalDuration = Date().timeIntervalSince(startTime)
      print("App: [PERF] handleOverlayVisibility (fade in) took \(totalDuration * 1000)ms")
    }
  }

  private func repositionOverlayPanel() {
    DispatchQueue.main.async {
      guard let panel = self.appDelegate.overlayPanel else {
        print("App: Warning - Overlay panel not found for repositioning, creating it")
        self.createOverlayPanel()
        return
      }

      let windowWidth: CGFloat = 300
      let windowHeight: CGFloat = 72

      let displayManagerInstance = DisplayManager.shared
      if let optimalPosition = displayManagerInstance.getOptimalOverlayPosition(
        windowWidth: windowWidth,
        windowHeight: windowHeight
      ) {
        panel.setFrame(optimalPosition, display: true)
        panel.orderFrontRegardless()

        print("App: Repositioned overlay panel to: \(optimalPosition)")
      } else {
        print("App: Warning - Could not determine optimal position for repositioning")
      }
    }
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private var menuContent: some View {
    Group {
      Button("History...") {
        openHistoryWindow()
      }

      Button("Settings...") {
        openSettingsWindow()
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      Button(notesModeService.isActive ? "Stop Notes Mode" : "Start Notes Mode") {
        notesModeService.toggle()
      }

      Divider()

      #if DEBUG
      Button("Waveform Debug...") {
        openWaveformDebugWindow()
      }
      .keyboardShortcut("d", modifiers: [.command, .shift])

      Divider()
      #endif

      Button("Check for Updates...") {
        checkForUpdates()
      }

      Divider()

      Button("Quit") {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }

  #if DEBUG
  private func openWaveformDebugWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Waveform Debug"
    window.contentView = NSHostingView(rootView: WaveformDebugView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  #endif

  private var recentTranscriptionsMenu: some View {
    Menu("Recent Transcriptions") {
      ForEach(appState.recentTranscriptions.prefix(5)) { transcription in
        Button(action: {
          copyToClipboard(transcription.transcribedText)
        }) {
          VStack(alignment: .leading) {
            Text(transcription.truncatedText)
              .lineLimit(1)
            Text(transcription.formattedTimestamp)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Divider()

      Button("View All History...") {
        openHistoryWindow()
      }
    }
  }

  private func openHistoryWindow() {
    openWindow(id: "history")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if let historyWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "history" }) {
        historyWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }

  private func openSettingsWindow() {
    openWindow(id: "settings")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" })
      {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }

  private func checkForUpdates() {
    updateManager.checkForUpdates()
  }

}

private enum ProfileSwitchDirection {
  case next
  case previous
}
