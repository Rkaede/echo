import AppKit
import SwiftUI

/// Moves the window when its content is dragged. Buttons, fields and lists handle their own
/// clicks first, so they keep working. It follows the pointer in screen coordinates, since
/// the view's own coordinates move with the window. SwiftUI's WindowDragGesture didn't move
/// Echo's windows.
struct DragsWindow: ViewModifier {
  @State private var window: NSWindow?
  @State private var start: (mouse: NSPoint, origin: NSPoint)?

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 2)
          .onChanged { value in
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            // On the first change, back out the distance already moved (screen y points up).
            let pressedAt = NSPoint(x: mouse.x - value.translation.width, y: mouse.y + value.translation.height)
            let start = start ?? (pressedAt, window.frame.origin)
            self.start = start
            window.setFrameOrigin(
              NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
            )
          }
          .onEnded { _ in start = nil }
      )
      .allowsWindowActivationEvents(true)
      .background(WindowFinder { window = $0 })
  }
}

/// Hands back the NSWindow hosting a view once the view is in one.
struct WindowFinder: NSViewRepresentable {
  let onWindow: (NSWindow) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window { onWindow(window) }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
