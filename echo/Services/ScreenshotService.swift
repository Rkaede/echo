import AppKit
import ScreenCaptureKit

/// Captures full-screen screenshots for notes mode using ScreenCaptureKit.
@MainActor
enum ScreenshotService {
  private static let loggerCategory = "ScreenshotService"

  static var hasScreenCapturePermission: Bool {
    CGPreflightScreenCaptureAccess()
  }

  /// Prompts the user for Screen Recording permission when it has not been granted yet.
  /// Returns true when permission is currently available. The system prompt only
  /// appears once; afterwards the user must enable Echo in System Settings.
  @discardableResult
  static func requestPermissionIfNeeded() -> Bool {
    if CGPreflightScreenCaptureAccess() {
      return true
    }
    let granted = CGRequestScreenCaptureAccess()
    log(
      "Screen Recording permission requested, granted: \(granted)",
      category: loggerCategory,
      level: granted ? .info : .warning
    )
    return granted
  }

  /// Captures the screen the user is working on (the one with the mouse cursor),
  /// excluding Echo's own overlay windows, and writes it as a PNG to `url`.
  /// Returns true on success.
  static func capturePNG(to url: URL) async -> Bool {
    guard CGPreflightScreenCaptureAccess() else {
      log(
        "Screen Recording permission not granted; skipping screenshot",
        category: loggerCategory,
        level: .warning
      )
      return false
    }

    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)

      let activeScreen = DisplayManager.shared.getActiveScreen()
      let activeDisplayID =
        (activeScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
        .uint32Value

      guard
        let display = content.displays.first(where: { $0.displayID == activeDisplayID })
          ?? content.displays.first
      else {
        log("No displays available for screenshot", category: loggerCategory, level: .error)
        return false
      }

      // Leave Echo's own overlay windows (recording status, notes panel) out of the capture
      let ownPid = ProcessInfo.processInfo.processIdentifier
      let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPid }
      let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

      let scale = activeScreen?.backingScaleFactor ?? 2
      let configuration = SCStreamConfiguration()
      configuration.width = Int(CGFloat(display.width) * scale)
      configuration.height = Int(CGFloat(display.height) * scale)
      configuration.showsCursor = false

      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)

      let bitmap = NSBitmapImageRep(cgImage: image)
      guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        log("Failed to encode screenshot as PNG", category: loggerCategory, level: .error)
        return false
      }
      try pngData.write(to: url, options: .atomic)
      log(
        "Screenshot saved to \(url.lastPathComponent) (\(pngData.count / 1024) KB)",
        category: loggerCategory,
        level: .info
      )
      return true
    } catch {
      log("Screenshot capture failed: \(error)", category: loggerCategory, level: .error)
      return false
    }
  }
}
