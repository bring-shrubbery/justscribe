//
//  ShortcutConfig.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 06/02/2026.
//

import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

struct ShortcutConfig: Codable, Equatable {
    var keyCode: Int?   // nil for modifier-only shortcuts
    var modifiers: UInt // NSEvent.ModifierFlags.rawValue (device-independent)

    var isModifierOnly: Bool { keyCode == nil }

    static let userDefaultsKey = "customShortcutConfig"

    /// The set of modifier flags we support in shortcuts
    static let allowedModifierFlags: NSEvent.ModifierFlags = [.control, .shift, .option, .command]

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    // MARK: - Display

    var displayString: String {
        var parts: [String] = []

        let flags = modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        if let keyCode = keyCode {
            parts.append(Self.keyName(for: keyCode))
        }

        return parts.joined()
    }

    var readableDescription: String {
        var parts: [String] = []

        let flags = modifierFlags
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Command") }

        if let keyCode = keyCode {
            parts.append(Self.keyName(for: keyCode))
        }

        return parts.joined(separator: " + ")
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func load() -> ShortcutConfig? {
        // Try our own storage first
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return config
        }

        // Migrate from KeyboardShortcuts library
        if let shortcut = KeyboardShortcuts.getShortcut(for: .activateTranscription) {
            let config = ShortcutConfig(
                keyCode: Int(shortcut.carbonKeyCode),
                modifiers: shortcut.modifiers.intersection(.deviceIndependentFlagsMask).rawValue
            )
            config.save()
            return config
        }

        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - KeyboardShortcuts Bridge

    /// Convert to a KeyboardShortcuts.Shortcut (only valid for non-modifier-only configs)
    func toKeyboardShortcut() -> KeyboardShortcuts.Shortcut? {
        guard let keyCode = keyCode else { return nil }
        let key = KeyboardShortcuts.Key(rawValue: keyCode)
        return KeyboardShortcuts.Shortcut(key, modifiers: modifierFlags)
    }

    // MARK: - Default

    static let defaultConfig = ShortcutConfig(
        keyCode: Int(kVK_Space),
        modifiers: NSEvent.ModifierFlags([.control, .shift])
            .intersection(.deviceIndependentFlagsMask).rawValue
    )

    // MARK: - Key Name Mapping

    static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "Esc"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PageUp"
        case kVK_PageDown: return "PageDown"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "Key\(keyCode)"
        }
    }
}
