import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

struct ShortcutRecorderView: View {
  @Binding var shortcut: String?
  @State private var isRecording = false

  private var hasShortcut: Bool {
    guard let shortcut, !shortcut.isEmpty else { return false }
    return true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ZStack(alignment: .trailing) {
        shortcutDisplay
          .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .onTapGesture {
            guard !isRecording, !hasShortcut else { return }
            beginRecording()
          }

        if hasShortcut, !isRecording {
          Button(action: clearShortcut) {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(.primary)
              .frame(width: 20, height: 20)
              .background(
                Circle()
                  .fill(Color.secondary.opacity(0.2))
              )
          }
          .buttonStyle(.plain)
          .padding(.trailing, 4)
        }
      }

      #if os(macOS)
        if isRecording {
          ShortcutCaptureRepresentable(
            onShortcut: { recordShortcut($0) },
            onCancel: { cancelRecording() }
          )
          .frame(width: 0, height: 0)
        }
      #endif
    }
    .onDisappear {
      #if os(macOS)
        if isRecording {
          HotkeyManager.shared.resumeToggleHotkey()
        }
      #endif
    }
  }

  private var shortcutDisplay: some View {
    let displayText: String = {
      if isRecording {
        return "Recording…"
      }
      if let shortcut, !shortcut.isEmpty {
        return ShortcutRecorderView.displayText(for: shortcut)
      }
      return "Record Shortcut"
    }()

    let backgroundColor: Color = {
      if isRecording {
        return Color.accentColor.opacity(0.18)
      }
      if hasShortcut {
        return Color.secondary.opacity(0.1)
      }
      return Color.secondary.opacity(0.08)
    }()

    let foregroundColor: Color = {
      if isRecording {
        return .accentColor
      }
      if hasShortcut {
        return .primary
      }
      return .primary
    }()

    return HStack {
      Spacer(minLength: 4)
      Text(displayText)
        .font(.body)
        .fontWeight(isRecording ? .semibold : .regular)
        .foregroundColor(foregroundColor)
        .multilineTextAlignment(.center)
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
      Spacer(minLength: 4)
    }
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(backgroundColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.secondary.opacity(isRecording ? 0.4 : 0.25), lineWidth: 1)
    )
  }

  private func beginRecording() {
    #if os(macOS)
      HotkeyManager.shared.suspendToggleHotkey()
      isRecording = true
    #endif
  }

  private func clearShortcut() {
    shortcut = nil
    isRecording = false
  }

  private func cancelRecording() {
    #if os(macOS)
      HotkeyManager.shared.resumeToggleHotkey()
    #endif
    shortcut = nil
    isRecording = false
  }

  private func recordShortcut(_ shortcutText: String) {
    #if os(macOS)
      HotkeyManager.shared.resumeToggleHotkey()
    #endif
    shortcut = ShortcutUtils.normalize(shortcutText)
    isRecording = false
  }

  static func displayText(for shortcut: String) -> String {
    let parts = shortcut.split(separator: "+")
    let mapped = parts.map { part -> String in
      switch part.lowercased() {
      case "cmd": return "⌘"
      case "ctrl": return "⌃"
      case "alt": return "⌥"
      case "shift": return "⇧"
      case "return": return "↩︎"
      case "tab": return "⇥"
      case "space": return "Space"
      case "delete": return "⌫"
      case "left": return "←"
      case "right": return "→"
      case "up": return "↑"
      case "down": return "↓"
      default: return part.uppercased()
      }
    }
    return mapped.joined(separator: " ")
  }
}

#if os(macOS)
  private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    var onShortcut: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
      let view = ShortcutCaptureView()
      view.onShortcut = onShortcut
      view.onCancel = onCancel
      DispatchQueue.main.async {
        view.window?.makeFirstResponder(view)
      }
      return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
      nsView.onShortcut = onShortcut
      nsView.onCancel = onCancel
      DispatchQueue.main.async {
        if nsView.window?.firstResponder !== nsView {
          nsView.window?.makeFirstResponder(nsView)
        }
      }
    }
  }

  private final class ShortcutCaptureView: NSView {
    var onShortcut: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window?.firstResponder !== self else { return }
        self.window?.makeFirstResponder(self)
      }
    }

    override func keyDown(with event: NSEvent) {
      guard !handle(event: event) else { return }
      super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
      // Ignore modifier-only changes to avoid premature recording
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      if handle(event: event) { return true }
      return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    private func handle(event: NSEvent) -> Bool {
      if event.keyCode == 53 {  // Escape key code
        onCancel?()
        return true
      }
      guard !event.isARepeat, let shortcutString = Self.describeShortcut(from: event) else {
        return false
      }
      onShortcut?(shortcutString)
      return true
    }

    private static func describeShortcut(from event: NSEvent) -> String? {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      var components: [String] = []

      if flags.contains(.command) { components.append("cmd") }
      if flags.contains(.control) { components.append("ctrl") }
      if flags.contains(.option) { components.append("alt") }
      if flags.contains(.shift) { components.append("shift") }

      guard let keyComponent = keyRepresentation(for: event) else { return nil }
      components.append(keyComponent)
      return components.joined(separator: "+")
    }

    private static func keyRepresentation(for event: NSEvent) -> String? {
      switch event.keyCode {
      case 36: return "return"
      case 48: return "tab"
      case 49: return "space"
      case 51: return "delete"
      case 123: return "left"
      case 124: return "right"
      case 125: return "down"
      case 126: return "up"
      case 122...135:
        let index = Int(event.keyCode) - 121
        return "f\(index)"
      default:
        break
      }

      guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
        return nil
      }
      let scalarView = characters.unicodeScalars
      if scalarView.count == 1, let scalar = scalarView.first {
        switch scalar {
        case " ":
          return "space"
        default:
          return String(scalar).lowercased()
        }
      }

      return characters.lowercased()
    }
  }
#endif
