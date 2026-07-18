import AppKit
import CoreGraphics
import Foundation

@MainActor
class PasteService {
  static let shared = PasteService()
  private let loggerCategory = "PasteService"

  /// How long the pasted text stays on the clipboard before restoration. Slow apps
  /// (notably Electron) can read the clipboard slightly after the Cmd+V event lands.
  nonisolated static let clipboardRestoreDelayNanoseconds: UInt64 = 500_000_000

  private var savedClipboardContent: String?
  private var pendingRestoreTask: Task<Void, Never>?

  private init() {}

  func pasteToFocusedApp(_ text: String, restoreClipboard: Bool = true) async -> Bool {
    log("Attempting to paste text: '\(text.prefix(50))...'", category: loggerCategory, level: .debug)

    // Check for accessibility permissions
    guard checkAccessibilityPermissions() else {
      log("Accessibility permissions not granted", category: loggerCategory, level: .error)
      return false
    }

    log("Accessibility permissions confirmed", category: loggerCategory, level: .debug)

    // A restore from a previous paste may still be pending; finish it now so the
    // snapshot below captures the user's clipboard, not our previous paste text.
    await finishPendingClipboardRestore()

    // Save current clipboard content if restoration is enabled
    if restoreClipboard {
      savedClipboardContent = NSPasteboard.general.string(forType: .string)
      log("Saved clipboard content for restoration", category: loggerCategory, level: .debug)
    }

    // Copy text to clipboard
    NSPasteboard.general.clearContents()
    let success = NSPasteboard.general.setString(text, forType: .string)
    log("Clipboard set successfully: \(success)", category: loggerCategory, level: .debug)

    // Small delay to ensure clipboard is ready
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Simulate paste
    log("Simulating Cmd+V paste", category: loggerCategory, level: .info)
    await simulatePaste()

    // Restore the clipboard in the background so callers (and the completion sound)
    // don't wait out the settle delay. The delay itself is unchanged, so slow apps
    // still read the pasted text before the clipboard swaps back.
    if restoreClipboard {
      scheduleClipboardRestore()
    }

    log("Paste keystroke delivered", category: loggerCategory, level: .info)
    return true
  }

  private func scheduleClipboardRestore() {
    pendingRestoreTask = Task { [weak self] in
      // Cancellation skips the remaining delay but still restores below.
      try? await Task.sleep(nanoseconds: Self.clipboardRestoreDelayNanoseconds)
      self?.restoreSavedClipboard()
    }
  }

  private func finishPendingClipboardRestore() async {
    guard let task = pendingRestoreTask else { return }
    task.cancel()
    await task.value
    pendingRestoreTask = nil
  }

  private func simulatePaste() async {
    log("Creating event source", category: loggerCategory, level: .debug)
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      log("Failed to create event source", category: loggerCategory, level: .error)
      return
    }

    log("Creating key down event", category: loggerCategory, level: .debug)
    // Key down event for 'v' with Cmd modifier
    guard
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0x09,  // 'v' key code
        keyDown: true)
    else {
      log("Failed to create key down event", category: loggerCategory, level: .error)
      return
    }
    keyDown.flags = .maskCommand

    log("Creating key up event", category: loggerCategory, level: .debug)
    // Key up event for 'v' with Cmd modifier
    guard
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0x09,  // 'v' key code
        keyDown: false)
    else {
      log("Failed to create key up event", category: loggerCategory, level: .error)
      return
    }
    keyUp.flags = .maskCommand

    // Post the events
    log("Posting key down event", category: loggerCategory, level: .debug)
    keyDown.post(tap: .cghidEventTap)
    try? await Task.sleep(nanoseconds: 10_000_000)
    log("Posting key up event", category: loggerCategory, level: .debug)
    keyUp.post(tap: .cghidEventTap)
    log("Key events posted successfully", category: loggerCategory, level: .debug)
  }

  func checkAccessibilityPermissions() -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
    let hasPermission = AXIsProcessTrustedWithOptions(options)
    log("Accessibility permission status: \(hasPermission)", category: loggerCategory, level: .debug)
    return hasPermission
  }

  func promptForAccessibilityPermission() -> Bool {
    log("Prompting for accessibility permission", category: loggerCategory, level: .info)
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    let hasPermission = AXIsProcessTrustedWithOptions(options)
    log("Accessibility permission after prompt: \(hasPermission)", category: loggerCategory, level: .info)
    return hasPermission
  }

  func openAccessibilityPreferences() {
    log("Opening accessibility preferences", category: loggerCategory, level: .info)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
      log("Successfully opened accessibility preferences", category: loggerCategory, level: .debug)
    } else {
      log("Failed to create URL for accessibility preferences", category: loggerCategory, level: .error)
    }
  }

  private func restoreSavedClipboard() {
    guard let savedContent = savedClipboardContent else {
      log("No saved clipboard content to restore", category: loggerCategory, level: .debug)
      return
    }

    NSPasteboard.general.clearContents()
    let success = NSPasteboard.general.setString(savedContent, forType: .string)
    log("Clipboard restored successfully: \(success)", category: loggerCategory, level: .debug)

    // Clear the saved content after restoration
    savedClipboardContent = nil
  }
}
