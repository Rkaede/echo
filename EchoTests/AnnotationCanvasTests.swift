import AppKit
import Testing

@testable import Echo

@MainActor
@Suite("Notes annotation mouse input")
struct AnnotationCanvasTests {
  @Test(arguments: [NSEvent.ModifierFlags(), .shift, .function, .command])
  func firstClickDrawsWithoutRequiringShift(modifiers: NSEvent.ModifierFlags) throws {
    let canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    let down = try event(.leftMouseDown, at: CGPoint(x: 20, y: 30), modifiers: modifiers)
    #expect(canvas.acceptsFirstMouse(for: down))
    canvas.mouseDown(with: down)
    canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 80, y: 90)))
    canvas.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 80, y: 90)))
    canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 100, y: 100)))
    #expect(canvas.strokes == [[CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)]])

    canvas.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 120, y: 130)))
    #expect(canvas.strokes.count == 2)
  }

  @Test func endingAndClearingStrokesRejectsLateDragEvents() throws {
    let canvas = AnnotationCanvasView(frame: .zero)
    canvas.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 20, y: 30)))
    canvas.endStroke()
    canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 80, y: 90)))
    #expect(canvas.strokes == [[CGPoint(x: 20, y: 30)]])

    canvas.removeAllStrokes()
    canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 100, y: 100)))
    #expect(canvas.strokes.isEmpty)
  }

  private func event(
    _ type: NSEvent.EventType, at point: CGPoint, modifiers: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: modifiers, timestamp: 0,
      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    ))
  }
}
