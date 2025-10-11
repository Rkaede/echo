import Foundation
import SwiftUI
import CoreGraphics

struct Profile: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var isDefault: Bool
    var isEnabled: Bool
    var shortcut: String?
    var transcriptionModel: String
    var postProcessingEnabled: Bool
    var postProcessingPrompt: String
    var postProcessingModel: String
    var iconName: String?
    var iconColor: String?
    let createdAt: Date
    var updatedAt: Date
}

struct AppAssignment: Identifiable, Codable, Equatable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
    let profileId: String
    let createdAt: Date
}

enum ProfileValidationError: LocalizedError {
    case invalidTitle
    case duplicateTitle
    case reservedShortcut
    case duplicateShortcut
    case invalidModel
    case invalidPostProcessingModel
    case invalidIcon
    case invalidColor
    case invalidPromptPlaceholders
    case defaultMustBeEnabled

    var errorDescription: String? {
        switch self {
        case .invalidTitle: return "Title must be 1–64 characters."
        case .duplicateTitle: return "Another profile already uses this title."
        case .reservedShortcut: return "This shortcut is reserved."
        case .duplicateShortcut: return "Another profile already uses this shortcut."
        case .invalidModel: return "Selected model is not supported."
        case .invalidPostProcessingModel: return "Selected post-processing model is not supported."
        case .invalidIcon: return "Invalid icon name."
        case .invalidColor: return "Invalid color value."
        case .invalidPromptPlaceholders: return "Unknown placeholders in prompt. Only {{TRANSCRIPTION}} supported."
        case .defaultMustBeEnabled: return "Default profile must remain enabled."
        }
    }
}

enum ShortcutUtils {
    static let reserved: Set<String> = [
        "cmd+q", "cmd+w", "cmd+h", "cmd+m"
    ]

    static func normalize(_ raw: String) -> String {
        let parts = raw.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "+")
        var mods: [String] = []
        var key: String = ""
        for p in parts {
            switch p {
            case "cmd", "ctrl", "control", "alt", "option", "shift":
                let norm = (p == "control" ? "ctrl" : (p == "option" ? "alt" : String(p)))
                mods.append(norm)
            default:
                key = String(p)
            }
        }
        let orderedMods = ["ctrl", "alt", "shift", "cmd"].filter { mods.contains($0) }
        return (orderedMods + (key.isEmpty ? [] : [key])).joined(separator: "+")
    }

    struct ParsedShortcut {
        let keyCode: Int64
        let modifiers: CGEventFlags
        let key: String
    }

    static func parse(_ shortcut: String) -> ParsedShortcut? {
        let normalized = normalize(shortcut)
        let parts = normalized.split(separator: "+").map { String($0) }

        guard !parts.isEmpty else { return nil }

        var modifiers = CGEventFlags()
        var keyString = ""

        for part in parts {
            switch part {
            case "cmd":
                modifiers.insert(.maskCommand)
            case "ctrl":
                modifiers.insert(.maskControl)
            case "alt":
                modifiers.insert(.maskAlternate)
            case "shift":
                modifiers.insert(.maskShift)
            default:
                keyString = part
            }
        }

        guard !keyString.isEmpty, let keyCode = keyCodeForString(keyString) else { return nil }

        return ParsedShortcut(keyCode: keyCode, modifiers: modifiers, key: keyString)
    }

    private static func keyCodeForString(_ key: String) -> Int64? {
        // Special keys
        switch key.lowercased() {
        case "return": return 36
        case "tab": return 48
        case "space": return 49
        case "delete": return 51
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111
        default:
            break
        }

        // Character keys - map common characters to key codes
        // This is a simplified mapping for common keys
        let charToKeyCode: [String: Int64] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
            "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
            "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
            "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
            "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
            ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
            "`": 50
        ]

        if let code = charToKeyCode[key.lowercased()] {
            return code
        }

        // For single character input, try to get the key code from the character
        if key.count == 1, let scalar = key.unicodeScalars.first {
            // Check if it's a shifted character and map to the base key
            let shiftedChars: [Character: String] = [
                "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
                "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
                "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\",
                ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
                "~": "`"
            ]

            if let baseKey = shiftedChars[Character(String(scalar))] {
                return charToKeyCode[baseKey]
            }
        }

        return nil
    }
}

enum ProfileValidator {
    static func validatePrompt(_ prompt: String) -> Bool {
        // Allow empty; if enabled and empty, service can warn later.
        guard !prompt.isEmpty else { return true }
        // Only allow {{TRANSCRIPTION}} placeholder if any braces are present
        let pattern = #"\{\{([A-Z_]+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
            for m in matches {
                if let r = Range(m.range(at: 1), in: prompt) {
                    if prompt[r] != "TRANSCRIPTION" { return false }
                }
            }
        }
        return true
    }
}
