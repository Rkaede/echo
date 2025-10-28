import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var overlayPanel: OverlayPanel?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    print("AppDelegate: Application finished launching")

    // Observers will be set up from EchoApp once StateObjects are initialized
  }

  func setupObservers(app: EchoApp) {
    // This will be called from EchoApp after initialization
    print("AppDelegate: Setting up observers")
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
