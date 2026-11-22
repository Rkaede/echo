import AppKit
import SwiftUI

@main
struct EchoApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.openWindow) private var openWindow
  // Only state this struct's body actually reads belongs here: every @Published change on an
  // observed object re-runs every scene below. Recording state, the overlay and hotkeys are
  // owned by AppDelegate instead.
  @StateObject private var settings = SettingsManager.shared
  @StateObject private var notesModeService = NotesModeService.shared
  @StateObject private var failedRecordings = FailedRecordingStore.shared
  @StateObject private var updateManager: UpdateManager
  #if DEBUG
  /// Changed by the debug menu to give the onboarding window a fresh view, so it restarts at
  /// the first step with the saved keys reloaded.
  @State private var onboardingRunID = UUID()
  #endif

  init() {
    LoggingService.shared.startConsoleCapture()

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
        #if DEBUG
        .id(onboardingRunID)
        #endif
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
    }
    .restorationBehavior(.disabled)
    .windowLevel(.floating)
    .defaultSize(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .defaultLaunchBehavior(.suppressed)
    .windowStyle(.hiddenTitleBar)
  }

  private var historyWindow: some Scene {
    Window("Echo History", id: "history") {
      HistoryView()
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

      notesModeMenuItem

      Divider()

      if failedRecordings.latest != nil {
        Button("Retry Failed Recording") {
          appDelegate.retryFailedRecording()
        }

        Divider()
      }

      #if DEBUG
      Button("Waveform Debug...") {
        openWaveformDebugWindow()
      }
      .keyboardShortcut("d", modifiers: [.command, .shift])

      Button("Show Onboarding...") {
        restartOnboarding()
      }

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

  // The global shortcut is handled by GlobalShortcutMonitor; this only shows it in the menu.
  // Keys SwiftUI cannot display natively (function keys) are appended to the title instead.
  private var notesModeMenuItem: some View {
    let title = notesModeService.isActive ? "Stop Notes Mode" : "Start Notes Mode"
    let shortcut = settings.notesModeShortcut
    let menuShortcut = ShortcutUtils.menuShortcut(for: shortcut)
    let needsTitleHint = !shortcut.isEmpty && menuShortcut == nil
    let label =
      needsTitleHint ? "\(title)  \(ShortcutRecorderView.displayText(for: shortcut))" : title

    return Button(label) {
      notesModeService.toggle()
    }
    .keyboardShortcut(menuShortcut)
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

  /// Shows onboarding from its first step without clearing `hasCompletedOnboarding`.
  private func restartOnboarding() {
    onboardingRunID = UUID()
    showWindow(id: "onboarding")
  }
  #endif

  private func openHistoryWindow() {
    showWindow(id: "history")
  }

  private func openSettingsWindow() {
    showWindow(id: "settings")
  }

  /// Opens a window scene and brings it forward; a menu bar app is not active by default.
  private func showWindow(id: String) {
    openWindow(id: id)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }

  private func checkForUpdates() {
    updateManager.checkForUpdates()
  }

}
