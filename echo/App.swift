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
  @State private var updateManager: UpdateManager?
  @State private var overlayWindow: NSWindow?

  init() {
    let appState = AppState()
    _appState = StateObject(wrappedValue: appState)
    _viewModel = StateObject(wrappedValue: TranscriptionViewModel(appState: appState))
  }

  var body: some Scene {
    Window("Welcome to Echo", id: "onboarding") {
      OnboardingView()
    }
    .restorationBehavior(.disabled)
    .windowLevel(.floating)
    .defaultSize(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
    .defaultLaunchBehavior(settings.hasCompletedOnboarding ? .suppressed : .presented)

    Window("Settings", id: "settings") {
      SettingsView()
        .environmentObject(updateManager ?? UpdateManager())
    }
    .restorationBehavior(.disabled)
    .defaultSize(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .defaultLaunchBehavior(.suppressed)

    Window("Overlay", id: "overlay") {
      VStack {
        Spacer()
        OverlayView(status: appState.status)
          .padding(.horizontal, 20)  // Add padding for spring overshoot
      }
      .frame(width: 300, height: 60)  // Increased width for padding
      .background(Color.clear)
      .ignoresSafeArea()
      .onAppear {
        configureOverlayWindow()
      }
      .environmentObject(appState)
    }
    .windowStyle(.plain)
    .windowLevel(.floating)
    .defaultSize(width: 300, height: 60)  // Increased width for padding
    .defaultLaunchBehavior(.presented)

    MenuBarExtra("Echo", systemImage: "record.circle.fill") {
      Button("Settings...") {
        openWindow(id: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
          }
        }
      }
      .keyboardShortcut(",", modifiers: .command)
      
      Button("Check for Updates...") {
        if updateManager == nil {
          updateManager = UpdateManager()
        }
        updateManager?.checkForUpdates()
      }

      Divider()

      Button("Quit Echo") {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
    .menuBarExtraStyle(.menu)
    .onChange(of: hotkeyManager.shouldTriggerRecording) {
      Task {
        print("App: Toggle hotkey triggered - shouldTriggerRecording changed")

        // Open overlay window if not already open
        if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
          print("App: Opening overlay window")
          openWindow(id: "overlay")
        } else {
          print("App: Overlay window already open")
          // Reposition to active monitor
          repositionOverlayWindow()
        }

        // Toggle recording
        print("App: Triggering recording toggle")
        await viewModel.toggleRecording()
      }
    }
    .onChange(of: globalShortcutMonitor.shouldStartPushToTalk) {
      Task {
        print("App: Push-to-talk start triggered via GlobalShortcutMonitor")

        // Open overlay window if not already open
        if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
          print("App: Opening overlay window for push-to-talk")
          openWindow(id: "overlay")
        } else {
          print("App: Overlay window already open")
          // Reposition to active monitor
          repositionOverlayWindow()
        }

        // Start recording only
        print("App: Starting push-to-talk recording")
        await viewModel.startRecordingOnly()
      }
    }
    .onChange(of: globalShortcutMonitor.shouldStopPushToTalk) {
      Task {
        print("App: Push-to-talk stop triggered via GlobalShortcutMonitor")
        
        // Stop recording only
        print("App: Stopping push-to-talk recording")
        await viewModel.stopRecordingOnly()
      }
    }
    .onChange(of: displayManager.shouldRepositionOverlay) {
      print("App: Display configuration changed, repositioning overlay")
      repositionOverlayWindow()
    }
    .onChange(of: globalShortcutMonitor.shouldCancelRecording) {
      Task {
        print("App: Escape key pressed - checking cancellation logic")
        
        // Open overlay window if not already open (to show cancellation status)
        if NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) == nil {
          print("App: Opening overlay window for cancellation feedback")
          openWindow(id: "overlay")
        }
        
        // Handle cancellation based on recording mode
        switch (appState.recordingMode, appState.status) {
        case (.toggle, .recording), (.toggle, .processing):
          if appState.status == .confirmingCancel {
            // Second press - actually cancel
            print("App: Second Escape press - confirming cancellation")
            await viewModel.cancelRecording()
          } else {
            // First press - show confirmation
            print("App: First Escape press in toggle mode - showing confirmation")
            appState.startConfirmingCancel()
          }
        case (.pushToTalk, _), (nil, _):
          // Direct cancellation for push-to-talk or unknown mode
          print("App: Direct cancellation for push-to-talk mode")
          await viewModel.cancelRecording()
        default:
          // Handle confirmingCancel state or other states
          if appState.status == .confirmingCancel {
            print("App: Confirming cancellation")
            await viewModel.cancelRecording()
          } else {
            print("App: Escape pressed but no applicable cancellation logic for mode: \(String(describing: appState.recordingMode)), status: \(appState.status)")
          }
        }
      }
    }
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
        self.overlayWindow = window

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
      if let window = self.overlayWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "overlay" }) {
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

}
