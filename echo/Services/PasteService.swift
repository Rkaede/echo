import AppKit
import CoreGraphics
import Foundation

/// Keep every representation (including images, files and rich text) when restoring.
typealias ClipboardContents = [[NSPasteboard.PasteboardType: Data]]

@MainActor
protocol PasteboardAccess {
  var changeCount: Int { get }
  func contents() -> ClipboardContents
  func writeText(_ text: String) -> Bool
  func restore(_ contents: ClipboardContents) -> Bool
}

@MainActor
private struct SystemPasteboard: PasteboardAccess {
  var changeCount: Int { NSPasteboard.general.changeCount }

  func contents() -> ClipboardContents {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
      Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
        item.data(forType: type).map { (type, $0) }
      })
    }
  }

  func writeText(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  func restore(_ contents: ClipboardContents) -> Bool {
    let items = contents.map { representations in
      let item = NSPasteboardItem()
      for (type, data) in representations {
        item.setData(data, forType: type)
      }
      return item
    }
    NSPasteboard.general.clearContents()
    return items.isEmpty || NSPasteboard.general.writeObjects(items)
  }
}

@MainActor
final class PasteService {
  static let shared = PasteService(pasteboard: SystemPasteboard(), environment: .live)
  private let loggerCategory = "PasteService"

  enum Failure: Equatable {
    case busy, accessibilityPermission, targetChanged, modifiersHeld
    case clipboardWriteFailed, clipboardChanged, eventCreationFailed

    var message: String {
      switch self {
      case .busy: return "Another paste is still in progress."
      case .accessibilityPermission: return "Allow Echo in System Settings > Privacy & Security > Accessibility."
      case .targetChanged: return "The active app changed before the text could be pasted."
      case .modifiersHeld: return "Release the keyboard modifiers before pasting."
      case .clipboardWriteFailed: return "The clipboard could not be updated."
      case .clipboardChanged: return "The clipboard changed before the text could be pasted."
      case .eventCreationFailed: return "Echo could not send the paste shortcut."
      }
    }

    func recoveryHint(copiedToClipboard: Bool, historyEnabled: Bool) -> String {
      if copiedToClipboard { return "Press ⌘V to paste" }
      return historyEnabled ? "Copy from History" : "Try recording again"
    }

    func errorMessage(copiedToClipboard: Bool, historyEnabled: Bool) -> String {
      let recovery = copiedToClipboard
        ? "Text is on the clipboard; press Command+V to paste."
        : (historyEnabled ? "Copy the transcription from History." : "Please try again.")
      return "Transcription succeeded, but automatic paste failed. \(message) \(recovery)"
    }
  }

  enum Outcome: Equatable {
    /// Quartz accepts events without acknowledging insertion; never retry a posted paste.
    case posted
    case failed(Failure, copiedToClipboard: Bool)
    case cancelled
  }

  struct Environment {
    var hasAccessibilityPermission: () -> Bool
    var frontmostProcessIdentifier: () -> pid_t?
    var modifierFlags: () -> CGEventFlags
    var postPaste: (pid_t) -> Bool
    var sleep: (UInt64) async throws -> Void

    static let live = Environment(
      hasAccessibilityPermission: { AXIsProcessTrusted() && CGPreflightPostEventAccess() },
      frontmostProcessIdentifier: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
      modifierFlags: { CGEventSource.flagsState(.hidSystemState) },
      postPaste: { processIdentifier in
        // A private source prevents held Fn/Option/Shift flags leaking into Cmd+V.
        guard let source = CGEventSource(stateID: .privateState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Address the intended process, so a last-moment app switch cannot redirect text.
        // Queue the pair together without a suspension between key down and key up.
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
      },
      sleep: { try await Task.sleep(nanoseconds: $0) }
    )
  }

  /// Electron and busy apps can read the clipboard well after receiving Cmd+V.
  nonisolated static let clipboardRestoreDelayNanoseconds: UInt64 = 2_000_000_000
  private static let blockingModifiers: CGEventFlags = [
    .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
  ]

  private let pasteboard: any PasteboardAccess
  private let environment: Environment
  private var isPasting = false
  private var pendingRestoreTask: Task<Void, Never>?

  init(pasteboard: any PasteboardAccess, environment: Environment) {
    self.pasteboard = pasteboard
    self.environment = environment
  }

  func pasteToFocusedApp(
    _ text: String,
    targetProcessIdentifier: pid_t?,
    restoreClipboard: Bool = true
  ) async -> Outcome {
    guard !isPasting else { return .failed(.busy, copiedToClipboard: false) }
    isPasting = true
    defer { isPasting = false }

    // Let the previous recipient finish reading before replacing its clipboard text.
    // Cancelling the old restore would shorten that recipient's settle window.
    await pendingRestoreTask?.value
    pendingRestoreTask = nil
    guard !Task.isCancelled else { return .cancelled }

    let savedContents = pasteboard.contents()
    guard pasteboard.writeText(text) else {
      _ = pasteboard.restore(savedContents)
      return .failed(.clipboardWriteFailed, copiedToClipboard: false)
    }
    let changeCount = pasteboard.changeCount

    func failed(_ reason: Failure) -> Outcome {
      // Leave our text available for manual paste on failure. Never overwrite a newer copy.
      log("Paste not posted: \(reason); target PID: \(targetProcessIdentifier ?? -1); frontmost PID: \(environment.frontmostProcessIdentifier() ?? -1)",
          category: loggerCategory, level: .warning)
      return .failed(reason, copiedToClipboard: pasteboard.changeCount == changeCount)
    }

    guard environment.hasAccessibilityPermission() else { return failed(.accessibilityPermission) }

    do {
      try await environment.sleep(100_000_000)
      // Wait up to 1.5s for the recording shortcut (or other held modifiers) to release.
      for _ in 0..<75 {
        try Task.checkCancellation()
        guard !environment.modifierFlags().intersection(Self.blockingModifiers).isEmpty else { break }
        try await environment.sleep(20_000_000)
      }
      try Task.checkCancellation()
    } catch {
      restore(savedContents, ifUnchangedSince: changeCount)
      return .cancelled
    }

    guard environment.hasAccessibilityPermission() else { return failed(.accessibilityPermission) }
    guard let targetProcessIdentifier,
      environment.frontmostProcessIdentifier() == targetProcessIdentifier
    else { return failed(.targetChanged) }
    guard environment.modifierFlags().intersection(Self.blockingModifiers).isEmpty else {
      return failed(.modifiersHeld)
    }
    guard pasteboard.changeCount == changeCount else { return failed(.clipboardChanged) }
    guard environment.postPaste(targetProcessIdentifier) else { return failed(.eventCreationFailed) }

    if restoreClipboard {
      pendingRestoreTask = Task { [weak self, environment] in
        do {
          try await environment.sleep(Self.clipboardRestoreDelayNanoseconds)
        } catch { return }
        self?.restore(savedContents, ifUnchangedSince: changeCount)
      }
    }

    log("Paste shortcut posted to PID \(targetProcessIdentifier); characters: \(text.count); insertion is not acknowledged by the target app",
        category: loggerCategory, level: .info)
    return .posted
  }

  private func restore(_ contents: ClipboardContents, ifUnchangedSince changeCount: Int) {
    guard pasteboard.changeCount == changeCount else {
      log("Skipped clipboard restore because the clipboard changed", category: loggerCategory, level: .debug)
      return
    }
    let success = pasteboard.restore(contents)
    log("Clipboard restored successfully: \(success)", category: loggerCategory, level: success ? .debug : .warning)
  }

  func promptForAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}
