import AppKit
import ScreenCaptureKit

/// Captures screenshots for notes mode using ScreenCaptureKit.
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

  /// Captures a screen, excluding Echo's own overlay windows, and writes it as a PNG to
  /// `url`. Without an annotation this is the screen the user is working on (the one
  /// with the mouse cursor). With one it is the annotated screen, with the strokes drawn
  /// in and the image cropped to the area they mark. Returns true on success.
  static func capturePNG(to url: URL, annotation: ScreenAnnotation? = nil) async -> Bool {
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

      let activeScreen = annotation?.screen ?? DisplayManager.shared.getActiveScreen()
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

      var image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)

      // The strokes only line up with the display they were drawn on
      if let annotation, display.displayID == activeDisplayID {
        let screenSize = CGSize(width: display.width, height: display.height)
        if let annotated = annotate(image, strokes: annotation.strokes, screenSize: screenSize) {
          image = annotated
        } else {
          log("Failed to draw annotation into screenshot", category: loggerCategory, level: .error)
        }
      }

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

  /// Draws strokes into a capture of their screen and crops the result to the area
  /// they mark. `screenSize` is in points; the image may be at any pixel scale.
  nonisolated static func annotate(
    _ image: CGImage, strokes: [[CGPoint]], screenSize: CGSize
  ) -> CGImage? {
    guard
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }

    let scale = CGFloat(image.width) / screenSize.width
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.scaleBy(x: scale, y: scale)
    ScreenAnnotation.draw(strokes, in: context)

    let crop = ScreenAnnotation.cropRect(
      around: ScreenAnnotation.bounds(of: strokes),
      in: CGRect(origin: .zero, size: screenSize)
    )
    // CGImage crops in pixels from the top-left; the strokes use a bottom-left origin
    let pixelCrop = CGRect(
      x: crop.minX * scale,
      y: (screenSize.height - crop.maxY) * scale,
      width: crop.width * scale,
      height: crop.height * scale
    ).integral
    return context.makeImage()?.cropping(to: pixelCrop)
  }
}
