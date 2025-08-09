import AppKit
import Foundation
import Combine

class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    
    @Published var shouldRepositionOverlay = false
    
    private var displayChangeNotification: NSObjectProtocol?
    
    private init() {
        setupDisplayChangeMonitoring()
    }
    
    deinit {
        if let notification = displayChangeNotification {
            NotificationCenter.default.removeObserver(notification)
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
    }
    
    private func handleDisplayChange() {
        // Trigger overlay repositioning with a slight delay to ensure screen changes are complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
    func calculateOverlayPosition(for screen: NSScreen, windowWidth: CGFloat, windowHeight: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        let xPos = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let yPos = screenFrame.origin.y + 10  // 10px from bottom of screen
        
        return NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight)
    }
    
    /// Convenience method to get the optimal overlay position for the current active screen
    func getOptimalOverlayPosition(windowWidth: CGFloat, windowHeight: CGFloat) -> NSRect? {
        guard let activeScreen = getActiveScreen() else {
            return nil
        }
        
        return calculateOverlayPosition(for: activeScreen, windowWidth: windowWidth, windowHeight: windowHeight)
    }
}
