import AppKit
import CoreGraphics
import Foundation

class PasteService {
  static let shared = PasteService()

  private init() {}

  func pasteToFocusedApp(_ text: String) async -> Bool {
    print("PasteService: Attempting to paste text: '\(text.prefix(50))...'")

    // Check for accessibility permissions
    guard checkAccessibilityPermissions() else {
      print("PasteService: Accessibility permissions not granted")
      return false
    }

    print("PasteService: Accessibility permissions confirmed")

    // Copy text to clipboard
    NSPasteboard.general.clearContents()
    let success = NSPasteboard.general.setString(text, forType: .string)
    print("PasteService: Clipboard set successfully: \(success)")

    // Small delay to ensure clipboard is ready
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Simulate paste
    print("PasteService: Simulating Cmd+V paste")
    await simulatePaste()

    print("PasteService: Paste operation completed")
    return true
  }

  private func simulatePaste() async {
    print("PasteService: Creating event source")
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      print("PasteService: Failed to create event source")
      return
    }

    print("PasteService: Creating key down event")
    // Key down event for 'v' with Cmd modifier
    guard
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0x09,  // 'v' key code
        keyDown: true)
    else {
      print("PasteService: Failed to create key down event")
      return
    }
    keyDown.flags = .maskCommand

    print("PasteService: Creating key up event")
    // Key up event for 'v' with Cmd modifier
    guard
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0x09,  // 'v' key code
        keyDown: false)
    else {
      print("PasteService: Failed to create key up event")
      return
    }
    keyUp.flags = .maskCommand

    // Post the events
    print("PasteService: Posting key down event")
    keyDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: 10_000_000)
    print("PasteService: Posting key up event")
    keyUp.post(tap: .cghidEventTap)
    print("PasteService: Key events posted successfully")
  }

  func checkAccessibilityPermissions() -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
    let hasPermission = AXIsProcessTrustedWithOptions(options)
    print("PasteService: Accessibility permission status: \(hasPermission)")
    return hasPermission
  }

  func promptForAccessibilityPermission() -> Bool {
    print("PasteService: Prompting for accessibility permission")
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    let hasPermission = AXIsProcessTrustedWithOptions(options)
    print("PasteService: Accessibility permission after prompt: \(hasPermission)")
    return hasPermission
  }

  func openAccessibilityPreferences() {
    print("PasteService: Opening accessibility preferences")
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
      print("PasteService: Successfully opened accessibility preferences")
    } else {
      print("PasteService: Failed to create URL for accessibility preferences")
    }
  }
}
