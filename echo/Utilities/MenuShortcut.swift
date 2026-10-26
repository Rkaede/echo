import SwiftUI

extension ShortcutUtils {
  /// A SwiftUI shortcut for showing a stored shortcut string (e.g. `ctrl+alt+n`) beside a
  /// menu item. Returns nil for keys SwiftUI cannot represent, such as the function keys.
  static func menuShortcut(for shortcut: String) -> KeyboardShortcut? {
    guard let parsed = parse(shortcut), let key = menuKey(for: parsed.key) else { return nil }
    var modifiers = EventModifiers()
    if parsed.modifiers.contains(.maskControl) { modifiers.insert(.control) }
    if parsed.modifiers.contains(.maskAlternate) { modifiers.insert(.option) }
    if parsed.modifiers.contains(.maskShift) { modifiers.insert(.shift) }
    if parsed.modifiers.contains(.maskCommand) { modifiers.insert(.command) }
    return KeyboardShortcut(key, modifiers: modifiers)
  }

  private static func menuKey(for key: String) -> KeyEquivalent? {
    switch key {
    case "return": return .return
    case "tab": return .tab
    case "space": return .space
    case "delete": return .delete
    case "left": return .leftArrow
    case "right": return .rightArrow
    case "up": return .upArrow
    case "down": return .downArrow
    default:
      guard key.count == 1, let character = key.first else { return nil }
      return KeyEquivalent(character)
    }
  }
}
