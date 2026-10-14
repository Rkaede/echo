import AppKit
import Combine
import SwiftUI

/// Owns the recording overlay panel and shows or hides it straight from `AppState.status`.
///
/// This lives in AppKit rather than in `.onChange` modifiers on a SwiftUI scene, so showing
/// the overlay never waits for a scene update pass. The panel is created once at launch, and
/// a status change orders it front and starts the fade in the same main-thread turn that
/// changed the status.
@MainActor
final class OverlayPanelController {
  private static let panelWidth: CGFloat = 300
  private static let panelHeight: CGFloat = 72
  private static let fadeInDuration: TimeInterval = 0.08
  private static let fadeOutDuration: TimeInterval = 0.3
  /// A hotkey older than this is assumed not to be what made the overlay appear.
  private static let showLatencyWindow: TimeInterval = 2

  private let appState: AppState
  private let levelMeter: AudioLevelMeter
  private let profilesService: ProfilesService
  private let displayManager: DisplayManager
  private let loggerCategory = "OverlayPanelController"

  private var panel: OverlayPanel?
  private var lastStatus: RecordingStatus = .idle
  private var pendingShowKeyTime: TimeInterval?
  private var cancellables = Set<AnyCancellable>()

  init(
    appState: AppState,
    levelMeter: AudioLevelMeter,
    profilesService: ProfilesService,
    displayManager: DisplayManager
  ) {
    self.appState = appState
    self.levelMeter = levelMeter
    self.profilesService = profilesService
    self.displayManager = displayManager
  }

  func start() {
    createPanel()
    lastStatus = appState.status

    // `$status` publishes from `willSet`, so the new value is passed in rather than read back
    appState.$status
      .sink { [weak self] status in
        self?.statusDidChange(to: status)
      }
      .store(in: &cancellables)

    displayManager.$shouldRepositionOverlay
      .dropFirst()
      .sink { [weak self] _ in
        self?.repositionPanel()
      }
      .store(in: &cancellables)

    displayManager.$spaceDidChange
      .dropFirst()
      .sink { [weak self] _ in
        self?.handleSpaceChange()
      }
      .store(in: &cancellables)
  }

  /// Records when a hotkey that may start a recording was pressed, so the next time the
  /// overlay appears it can log how long that took.
  func noteShowRequested(keyTime: TimeInterval) {
    pendingShowKeyTime = keyTime
  }

  // MARK: - Panel

  private func createPanel() {
    let contentRect = displayManager.getOptimalOverlayPosition(
      windowWidth: Self.panelWidth,
      windowHeight: Self.panelHeight
    ) ?? NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight)

    let panel = OverlayPanel(contentRect: contentRect) {
      OverlayContentView()
        .environmentObject(self.appState)
        .environmentObject(self.profilesService)
        .environmentObject(self.levelMeter)
    }

    // Stays ordered in while idle, just transparent, so it keeps working over fullscreen apps
    panel.alphaValue = appState.status == .idle ? 0 : 1
    panel.orderFrontRegardless()
    self.panel = panel

    log(
      "Created overlay panel with level \(panel.level.rawValue)",
      category: loggerCategory,
      level: .info
    )
  }

  private func statusDidChange(to newStatus: RecordingStatus) {
    let oldStatus = lastStatus
    lastStatus = newStatus
    let showKeyTime = pendingShowKeyTime
    pendingShowKeyTime = nil

    guard let panel else { return }

    if newStatus == .idle && oldStatus != .idle {
      // Fade out to transparent when returning to idle (keep panel visible for fullscreen)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.fadeOutDuration
        panel.animator().alphaValue = 0
      }
    } else if newStatus != .idle && oldStatus == .idle {
      moveToActiveScreen(panel)
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.fadeInDuration
        panel.animator().alphaValue = 1
      }
      logShowLatency(since: showKeyTime)
    }
  }

  private func logShowLatency(since keyTime: TimeInterval?) {
    guard let keyTime else { return }
    let latency = ProcessInfo.processInfo.systemUptime - keyTime
    guard latency >= 0, latency < Self.showLatencyWindow else { return }
    log(
      String(format: "Overlay shown %.0fms after hotkey", latency * 1000),
      category: loggerCategory,
      level: .info
    )
  }

  // MARK: - Positioning

  /// Follows the screen with the mouse cursor, so the overlay appears where the user is
  /// working even if they moved to another display since it was last positioned.
  private func moveToActiveScreen(_ panel: OverlayPanel) {
    guard
      let frame = displayManager.getOptimalOverlayPosition(
        windowWidth: Self.panelWidth,
        windowHeight: Self.panelHeight
      ),
      frame != panel.frame
    else { return }
    panel.setFrame(frame, display: false)
  }

  private func repositionPanel() {
    guard let panel else {
      log(
        "Overlay panel not found for repositioning, creating it",
        category: loggerCategory,
        level: .warning
      )
      createPanel()
      return
    }

    guard
      let optimalPosition = displayManager.getOptimalOverlayPosition(
        windowWidth: Self.panelWidth,
        windowHeight: Self.panelHeight
      )
    else {
      log(
        "Could not determine optimal position for repositioning",
        category: loggerCategory,
        level: .warning
      )
      return
    }

    panel.setFrame(optimalPosition, display: true)
    panel.orderFrontRegardless()
    log("Repositioned overlay panel to: \(optimalPosition)", category: loggerCategory, level: .debug)
  }

  private func handleSpaceChange() {
    log("Space changed - ensuring overlay panel visibility", category: loggerCategory, level: .debug)

    // Wait a bit for space transition to complete, then reposition
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.repositionPanel()

      // Double-check that panel is actually visible after repositioning
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.recreatePanelIfHidden()
      }
    }
  }

  private func recreatePanelIfHidden() {
    guard let panel, !panel.isVisible else { return }

    log(
      "Overlay panel not visible after space change - recreating",
      category: loggerCategory,
      level: .warning
    )

    // Tear the old panel down completely. Left ordered in, its hosting view would keep
    // observing AppState and rendering alongside its replacement.
    panel.orderOut(nil)
    panel.contentView = nil
    panel.close()
    self.panel = nil

    createPanel()
  }
}
