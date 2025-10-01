import AppKit
import Combine
import Foundation

class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published var shouldRepositionOverlay = false
    @Published var spaceDidChange = false
    
    private var displayChangeNotification: NSObjectProtocol?
    private var spaceChangeNotification: NSObjectProtocol?
    
    private init() {
        setupDisplayChangeMonitoring()
    }
    
    deinit {
        if let notification = displayChangeNotification {
            NotificationCenter.default.removeObserver(notification)
        }
        if let notification = spaceChangeNotification {
            NSWorkspace.shared.notificationCenter.removeObserver(notification)
        }
    }
    
    private func setupDisplayChangeMonitoring() {
        // Monitor for display configuration changes
        displayChangeNotification = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("DisplayManager: Screen parameters changed!")
            self?.handleDisplayChange()
        }
        
        // Monitor for space/desktop changes
        spaceChangeNotification = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("DisplayManager: Active space changed!")
            self?.handleSpaceChange()
        }
    }
    
    private func handleDisplayChange() {
        // Trigger overlay repositioning with a slight delay to ensure screen changes are complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldRepositionOverlay.toggle()
        }
    }
    
    private func handleSpaceChange() {
        // Trigger overlay repositioning when space changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.spaceDidChange.toggle()
            self.shouldRepositionOverlay.toggle()
        }
    }

    /// Returns the screen that should be considered "active" for overlay positioning
    /// Priority: screen with mouse cursor > main screen > first available screen
    func getActiveScreen() -> NSScreen? {
        // First try to get the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        
        // Find screen containing the mouse cursor
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                print("DisplayManager: Using screen with mouse cursor")
                return screen
            }
        }
        
        // Fallback to main screen
        if let mainScreen = NSScreen.main {
            print("DisplayManager: Using main screen as fallback")
            return mainScreen
        }
        
        // Final fallback to first available screen
        if let firstScreen = NSScreen.screens.first {
            print("DisplayManager: Using first available screen as final fallback")
            return firstScreen
        }
        
        print("DisplayManager: No screens available")
        return nil
    }

  /// Calculates the center-bottom position for the overlay window on the given screen
  func calculateOverlayPosition(for screen: NSScreen, windowWidth: CGFloat, windowHeight: CGFloat)
    -> NSRect
  {
    let screenFrame = screen.frame
    let xPos = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
    let yPos = screenFrame.origin.y + 2  // 2px from bottom of screen

    return NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight)
  }

    /// Convenience method to get the optimal overlay position for the current active screen
    func getOptimalOverlayPosition(windowWidth: CGFloat, windowHeight: CGFloat) -> NSRect? {
        guard let activeScreen = getActiveScreen() else {
            return nil
        }
        
        return calculateOverlayPosition(
            for: activeScreen, windowWidth: windowWidth, windowHeight: windowHeight)
    }
    
    /// Checks if any application is currently in full-screen mode
    func isAnyAppInFullScreen() -> Bool {
        // Check all running applications
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.activationPolicy == .regular {
                // Get windows for this application
                let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                if let windows = windowList as? [[String: Any]] {
                    for window in windows {
                        if let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                           ownerPID == app.processIdentifier,
                           let bounds = window[kCGWindowBounds as String] as? [String: Any],
                           let width = bounds["Width"] as? CGFloat,
                           let height = bounds["Height"] as? CGFloat {
                            
                            // Check if window dimensions match any screen (indicating full-screen)
                            for screen in NSScreen.screens {
                                let screenSize = screen.frame.size
                                if abs(width - screenSize.width) < 10 && abs(height - screenSize.height) < 10 {
                                    print("DisplayManager: Detected full-screen app: \(app.localizedName ?? "Unknown")")
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    /// Returns the optimal window level based on current system state
    func getOptimalWindowLevel() -> CGWindowLevelKey {
        if isAnyAppInFullScreen() {
            print("DisplayManager: Using popUpMenu level for full-screen compatibility")
            return .popUpMenuWindow
        } else {
            print("DisplayManager: Using screenSaver level for normal mode")
            return .screenSaverWindow
        }
    }
}

