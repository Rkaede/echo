import Foundation

/// Centralized mapping of keyboard key codes and display representations
/// Used by both Profile shortcut parsing and ShortcutRecorderView
enum KeyCodeMapping {
  // MARK: - Special Keys

  static let specialKeys: [String: Int64] = [
    "return": 36,
    "tab": 48,
    "space": 49,
    "delete": 51,
    "left": 123,
    "right": 124,
    "down": 125,
    "up": 126,
    "f1": 122,
    "f2": 120,
    "f3": 99,
    "f4": 118,
    "f5": 96,
    "f6": 97,
    "f7": 98,
    "f8": 100,
    "f9": 101,
    "f10": 109,
    "f11": 103,
    "f12": 111,
  ]

  // MARK: - Character Keys

  static let characterKeys: [String: Int64] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
    "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
    "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25,
    "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
    ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
    "`": 50,
  ]

  // MARK: - Shifted Character Mapping

  static let shiftedCharacters: [Character: String] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
    "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\",
    ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
    "~": "`",
  ]

  // MARK: - Display Symbols

  static let displaySymbols: [String: String] = [
    "cmd": "⌘",
    "ctrl": "⌃",
    "alt": "⌥",
    "shift": "⇧",
    "return": "↩︎",
    "tab": "⇥",
    "space": "Space",
    "delete": "⌫",
    "left": "←",
    "right": "→",
    "up": "↑",
    "down": "↓",
  ]

  // MARK: - Key Code Lookup

  /// Get key code for a string representation
  static func keyCode(for key: String) -> Int64? {
    let lowercased = key.lowercased()

    // Check special keys first
    if let code = specialKeys[lowercased] {
      return code
    }

    // Check character keys
    if let code = characterKeys[lowercased] {
      return code
    }

    // Handle shifted characters
    if key.count == 1, let scalar = key.unicodeScalars.first {
      if let baseKey = shiftedCharacters[Character(String(scalar))] {
        return characterKeys[baseKey]
      }
    }

    return nil
  }

  /// Get key code from NSEvent keyCode (for reverse lookup in ShortcutRecorderView)
  static func keyString(from keyCode: UInt16) -> String? {
    // Check special keys
    switch keyCode {
    case 36: return "return"
    case 48: return "tab"
    case 49: return "space"
    case 51: return "delete"
    case 123: return "left"
    case 124: return "right"
    case 125: return "down"
    case 126: return "up"
    case 122...135:
      let index = Int(keyCode) - 121
      return "f\(index)"
    default:
      return nil
    }
  }

  /// Get display symbol for a key string
  static func displaySymbol(for key: String) -> String {
    displaySymbols[key.lowercased()] ?? key.uppercased()
  }
}
