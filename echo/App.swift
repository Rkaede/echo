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
  @StateObject private var updateManager: UpdateManager

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
