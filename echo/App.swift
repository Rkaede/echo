import AppKit
import HotKey
import SwiftUI

@main
struct EchoApp: App {
  @Environment(\.openWindow) private var openWindow
  @StateObject private var hotkeyManager = HotkeyManager.shared
  @StateObject private var globalShortcutMonitor = GlobalShortcutMonitor.shared
  @StateObject private var appState: AppState
  @StateObject private var viewModel: TranscriptionViewModel
  @StateObject private var settings = SettingsManager.shared
  @StateObject private var displayManager = DisplayManager.shared
  @StateObject private var tempFileManager = TempFileManager.shared
  @StateObject private var historyManager = HistoryManager.shared
  @State private var updateManager: UpdateManager?
  @State private var overlayWindowRef: NSWindow?

  init() {
    let appState = AppState()
    _appState = StateObject(wrappedValue: appState)
    _viewModel = StateObject(wrappedValue: TranscriptionViewModel(appState: appState))
  }

  var body: some Scene {
    onboardingWindow
    settingsWindow
    historyWindow
    overlayWindow
    menuBarExtra
  }

  private var onboardingWindow: some Scene {
    Window("Welcome to Echo", id: "onboarding") {
      OnboardingView()
    }
    .restorationBehavior(.disabled)
    .windowLevel(.floating)
    .defaultSize(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
    .defaultLaunchBehavior(settings.hasCompletedOnboarding ? .suppressed : .presented)
  }
  
  private var settingsWindow: some Scene {
    Window("Settings", id: "settings") {
      SettingsView()
        .environmentObject(updateManager ?? UpdateManager())
    }
    .restorationBehavior(.disabled)
    .defaultSize(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .defaultLaunchBehavior(.suppressed)
    .windowStyle(.hiddenTitleBar)
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
  
  private var overlayWindow: some Scene {
    Window("Overlay", id: "overlay") {
      VStack {
        Spacer()
        OverlayView(status: appState.status)
          .padding(.horizontal, 20)
      }
      .frame(width: 300, height: 60)
      .background(Color.clear)
      .ignoresSafeArea()
      .onAppear {
        configureOverlayWindow()
      }
      .environmentObject(appState)
    }
    .windowStyle(.plain)
    .windowLevel(.floating)
    .defaultSize(width: 300, height: 60)
    .defaultLaunchBehavior(.presented)
  }
  
  private var menuBarExtra: some Scene {
    MenuBarExtra("Echo", systemImage: "record.circle.fill") {
      menuContent
    }
    .menuBarExtraStyle(.menu)
    .onChange(of: hotkeyManager.shouldTriggerRecording) {
      handleHotkeyToggle()
    }
    .onChange(of: globalShortcutMonitor.shouldStartPushToTalk) {
      handlePushToTalkStart()
    }
    .onChange(of: globalShortcutMonitor.shouldStopPushToTalk) {
      handlePushToTalkStop()
    }
    .onChange(of: displayManager.shouldRepositionOverlay) {
      repositionOverlayWindow()
    }
    .onChange(of: globalShortcutMonitor.shouldCancelRecording) {
      handleCancelRecording()
    }
    .onChange(of: historyManager.recentTranscriptions) {
      updateHistoryState()
    }
    .onChange(of: historyManager.totalCount) {
      updateHistoryState()
    }
  }

  private func handleHotkeyToggle() {
    Task {
      print("App: Toggle hotkey triggered - shouldTriggerRecording changed")

      if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
        print("App: Opening overlay window")
        openWindow(id: "overlay")
      } else {
        print("App: Overlay window already open")
        repositionOverlayWindow()
      }

      print("App: Triggering recording toggle")
      await viewModel.toggleRecording()
    }
  }
  
  private func handlePushToTalkStart() {
    Task {
      print("App: Push-to-talk start triggered via GlobalShortcutMonitor")

      if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
        print("App: Opening overlay window for push-to-talk")
        openWindow(id: "overlay")
      } else {
        print("App: Overlay window already open")
        repositionOverlayWindow()
      }

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
  
  private func handleCancelRecording() {
    Task {
      print("App: Escape key pressed - checking cancellation logic")
      
      if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
        print("App: Opening overlay window for cancellation feedback")
        openWindow(id: "overlay")
      }
      
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
          print("App: Escape pressed but no applicable cancellation logic for mode: \(String(describing: appState.recordingMode)), status: \(appState.status)")
        }
      }
    }
  }
  
  private func updateHistoryState() {
    appState.updateHistoryState(count: historyManager.totalCount, recent: historyManager.recentTranscriptions)
  }

  private func configureOverlayWindow() {
    DispatchQueue.main.async {
      if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) {
        // Essential: Set collection behavior for fullscreen support
        window.collectionBehavior = [
          .canJoinAllSpaces,
          .fullScreenAuxiliary,
          .transient,
          .ignoresCycle,
        ]

        // Remove title bar and make non-resizable
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .nonactivatingPanel]
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))

        // Position window at bottom center of active screen
        let windowWidth: CGFloat = 300  // Increased for padding
        let windowHeight: CGFloat = 60
        
        if let optimalPosition = displayManager.getOptimalOverlayPosition(
          windowWidth: windowWidth, 
          windowHeight: windowHeight
        ) {
          window.setFrame(optimalPosition, display: true)
          print("App: Positioned overlay window at optimal location: \(optimalPosition)")
        } else {
          print("App: Warning - Could not determine optimal overlay position")
        }

        // Make window transparent
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        
        // Store reference to overlay window for repositioning
        self.overlayWindowRef = window

        print("App: Configured overlay window")
        
        // Initialize TempFileManager for cleanup
        tempFileManager.performStartupCleanup()
        tempFileManager.startPeriodicCleanup()
        
        // Initialize UpdateManager after overlay window is fully configured
        // This delay ensures that the Sparkle framework's SPUStandardUpdaterController
        // doesn't interfere with the overlay window's level and fullscreen behavior.
        // When Sparkle initializes with startingUpdater: true, it can modify window
        // management behaviors that prevent our overlay from appearing above fullscreen apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          if self.updateManager == nil {
            print("App: Initializing UpdateManager after overlay window setup")
            self.updateManager = UpdateManager()
          }
        }
      }
    }
  }
  
  private func repositionOverlayWindow() {
    DispatchQueue.main.async {
      if let window = self.overlayWindowRef ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) {
        let windowWidth: CGFloat = 300  // Increased for padding
        let windowHeight: CGFloat = 60
        
        if let optimalPosition = self.displayManager.getOptimalOverlayPosition(
          windowWidth: windowWidth,
          windowHeight: windowHeight
        ) {
          window.setFrame(optimalPosition, display: true)
          // Ensure window is visible on current space
          window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
          window.orderFront(nil)
          print("App: Repositioned overlay window to: \(optimalPosition)")
        } else {
          print("App: Warning - Could not determine optimal position for repositioning")
        }
      } else {
        print("App: Warning - Overlay window not found for repositioning")
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
      if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }
  
  private func checkForUpdates() {
    if updateManager == nil {
      updateManager = UpdateManager()
    }
    updateManager?.checkForUpdates()
  }

}
