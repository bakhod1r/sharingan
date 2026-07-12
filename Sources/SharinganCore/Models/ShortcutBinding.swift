import Foundation
#if canImport(Carbon)
import Carbon.HIToolbox
#endif

/// A user-configurable global hotkey: a virtual key code plus a Carbon modifier mask.
///
/// `keyCode` matches both the Carbon `kVK_*` constants and `NSEvent.keyCode`.
/// `modifiers` is a Carbon mask (`controlKey | optionKey | shiftKey | cmdKey`).
public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A global hotkey must carry at least one modifier, otherwise it would
    /// swallow ordinary typing system-wide.
    public var isValid: Bool { modifiers != 0 }

    /// Human-readable combo, e.g. `⌃⌥Space`.
    public var displayString: String {
        Self.modifierSymbols(modifiers) + Self.keyName(keyCode)
    }

    public static func modifierSymbols(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    /// Best-effort name for a virtual key code. Covers the keys a user is
    /// likely to bind; unknown codes fall back to `Key(n)`.
    public static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space:            return "Space"
        case kVK_Return:           return "Return"
        case kVK_Tab:              return "Tab"
        case kVK_Escape:           return "Esc"
        case kVK_Delete:           return "Delete"
        case kVK_ANSI_Equal:       return "="
        case kVK_ANSI_Minus:       return "-"
        case kVK_ANSI_Slash:       return "/"
        case kVK_ANSI_Period:      return "."
        case kVK_ANSI_Comma:       return ","
        case kVK_LeftArrow:        return "←"
        case kVK_RightArrow:       return "→"
        case kVK_UpArrow:          return "↑"
        case kVK_DownArrow:        return "↓"
        case kVK_ANSI_A:  return "A"
        case kVK_ANSI_B:  return "B"
        case kVK_ANSI_C:  return "C"
        case kVK_ANSI_D:  return "D"
        case kVK_ANSI_E:  return "E"
        case kVK_ANSI_F:  return "F"
        case kVK_ANSI_G:  return "G"
        case kVK_ANSI_H:  return "H"
        case kVK_ANSI_I:  return "I"
        case kVK_ANSI_J:  return "J"
        case kVK_ANSI_K:  return "K"
        case kVK_ANSI_L:  return "L"
        case kVK_ANSI_M:  return "M"
        case kVK_ANSI_N:  return "N"
        case kVK_ANSI_O:  return "O"
        case kVK_ANSI_P:  return "P"
        case kVK_ANSI_Q:  return "Q"
        case kVK_ANSI_R:  return "R"
        case kVK_ANSI_S:  return "S"
        case kVK_ANSI_T:  return "T"
        case kVK_ANSI_U:  return "U"
        case kVK_ANSI_V:  return "V"
        case kVK_ANSI_W:  return "W"
        case kVK_ANSI_X:  return "X"
        case kVK_ANSI_Y:  return "Y"
        case kVK_ANSI_Z:  return "Z"
        case kVK_ANSI_0:  return "0"
        case kVK_ANSI_1:  return "1"
        case kVK_ANSI_2:  return "2"
        case kVK_ANSI_3:  return "3"
        case kVK_ANSI_4:  return "4"
        case kVK_ANSI_5:  return "5"
        case kVK_ANSI_6:  return "6"
        case kVK_ANSI_7:  return "7"
        case kVK_ANSI_8:  return "8"
        case kVK_ANSI_9:  return "9"
        default:          return "Key(\(code))"
        }
    }
}
