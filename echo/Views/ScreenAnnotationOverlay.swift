import AppKit

@MainActor
protocol ScreenAnnotationPresenting: AnyObject {
  func setDrawingEnabled(_ enabled: Bool)
  func takeAnnotation() -> ScreenAnnotation?
  func close()
}

/// Lets the user draw over the screen in notes mode. A transparent panel covers one
/// screen and takes mouse input throughout a recording. When recording ends, clicks
/// pass through and the strokes are taken for its screenshot.
@MainActor
final class ScreenAnnotationOverlay: ScreenAnnotationPresenting {
  private var panel: OverlayPanel?
  private var canvas: AnnotationCanvasView?
  private var screen: NSScreen?

  private var hasStrokes: Bool { canvas?.strokes.isEmpty == false }

  func setDrawingEnabled(_ enabled: Bool) {
    guard enabled else {
      canvas?.endStroke()
      panel?.ignoresMouseEvents = true
      if !hasStrokes { panel?.orderOut(nil) }
      return
    }

    // Strokes stay on the screen they were drawn on, since a screenshot covers one display
    if !hasStrokes, let activeScreen = DisplayManager.shared.getActiveScreen() {
      screen = activeScreen
      if let panel {
        panel.setFrame(activeScreen.frame, display: false)
      } else {
        makePanel(frame: activeScreen.frame)
      }
    }
    panel?.ignoresMouseEvents = false
    panel?.orderFrontRegardless()
  }

  /// Hands over the strokes for a screenshot and clears them from the screen.
  func takeAnnotation() -> ScreenAnnotation? {
    guard let canvas, let screen, hasStrokes else { return nil }
    let annotation = ScreenAnnotation(screen: screen, strokes: canvas.strokes)
    canvas.removeAllStrokes()
    if panel?.ignoresMouseEvents == true { panel?.orderOut(nil) }
    return annotation
  }

  func close() {
    panel?.close()
    panel = nil
    canvas = nil
    screen = nil
  }

  private func makePanel(frame: NSRect) {
    let canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: frame.size))
    canvas.autoresizingMask = [.width, .height]

    let panel = OverlayPanel(contentRect: frame, contentView: canvas)
    // Just below Echo's status overlay, so the notes bar's stop button stays clickable
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    panel.ignoresMouseEvents = true

    self.canvas = canvas
    self.panel = panel
  }
}

/// Collects freehand strokes from mouse drags and draws them.
final class AnnotationCanvasView: NSView {
  private(set) var strokes: [[CGPoint]] = []
  private var isStroking = false

  // The panel never becomes key, so the first click has to draw rather than focus it
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    strokes.append([convert(event.locationInWindow, from: nil)])
    isStroking = true
    invalidateLatestSegment()
  }

  override func mouseDragged(with event: NSEvent) {
    guard isStroking else { return }
    strokes[strokes.count - 1].append(convert(event.locationInWindow, from: nil))
    invalidateLatestSegment()
  }

  override func mouseUp(with event: NSEvent) {
    isStroking = false
  }

  func endStroke() {
    isStroking = false
  }

  func removeAllStrokes() {
    strokes = []
    isStroking = false
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    ScreenAnnotation.draw(strokes, in: context)
  }

  /// The smoothed curve only changes around its last few samples, so redraw just
  /// that area (with room for the shadow) instead of the whole screen.
  private func invalidateLatestSegment() {
    guard let stroke = strokes.last else { return }
    let recent = Array(stroke.suffix(3))
    setNeedsDisplay(ScreenAnnotation.bounds(of: [recent]).insetBy(dx: -6, dy: -6))
  }
}
