import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  // The recording pipeline, overlay and hotkeys are owned here rather than by the SwiftUI
  // `App`, so their state changes never re-run the app's scenes, menu bar or windows.
  private var overlayController: OverlayPanelController?
  private var shortcutCoordinator: ShortcutCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    print("AppDelegate: Application finished launching")

    let appState = AppState()
    let viewModel = TranscriptionViewModel(appState: appState)

    // Build the overlay panel now so the first recording doesn't pay for creating it
    let overlayController = OverlayPanelController(
      appState: appState,
      levelMeter: AudioLevelMeter.shared,
      profilesService: ProfilesService.shared,
      displayManager: DisplayManager.shared
    )
    overlayController.start()
    self.overlayController = overlayController

    let shortcutCoordinator = ShortcutCoordinator(
      appState: appState,
      viewModel: viewModel,
      overlayController: overlayController,
      shortcutMonitor: GlobalShortcutMonitor.shared,
      profilesService: ProfilesService.shared,
      notesModeService: NotesModeService.shared,
      settings: SettingsManager.shared
    )
    shortcutCoordinator.start()
    self.shortcutCoordinator = shortcutCoordinator

    TempFileManager.shared.performStartupCleanup()
    TempFileManager.shared.startPeriodicCleanup()
    LoggingService.shared.cleanupOldLogs()
  }
}

/// Custom NSPanel subclass for overlay that appears over fullscreen apps
class OverlayPanel: NSPanel {
  init<Content: View>(
    contentRect: NSRect,
    backing: NSWindow.BackingStoreType = .buffered,
    defer flag: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: backing,
      defer: flag
    )

    // Configure panel for fullscreen compatibility
    self.isFloatingPanel = true
    self.level = .screenSaver  // Highest non-system level

    // CRITICAL: fullScreenAuxiliary works with NSPanel but not SwiftUI Window scene
    self.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,  // Allows panel to appear in fullscreen spaces
      .stationary,
      .ignoresCycle,
    ]

    // Window appearance
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false

    // Prevent hiding when other apps activate
    self.hidesOnDeactivate = false

    // Allow window to be visible in all contexts
    self.sharingType = .readOnly

    // Immediate appearance without animation
    self.animationBehavior = .none

    // Owners hold a strong reference and may close() the panel, so AppKit must not also
    // release it on close
    self.isReleasedWhenClosed = false

    // Set up SwiftUI content
    let hostingView = NSHostingView(rootView: content())
    self.contentView = hostingView

    print("OverlayPanel: Created with level \(self.level.rawValue)")
  }

  // Override to prevent panel from becoming key (non-activating)
  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }
}
