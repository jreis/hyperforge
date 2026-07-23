// KeyCodes.swift
// Virtual key codes used by the Hyper Key engine (Carbon / HID).
// Kept explicit so bindings stay readable and portable.

import CoreGraphics

enum KeyCode {
    // Letters
    static let a: CGKeyCode = 0x00
    static let s: CGKeyCode = 0x01
    static let d: CGKeyCode = 0x02
    static let f: CGKeyCode = 0x03
    static let h: CGKeyCode = 0x04
    static let g: CGKeyCode = 0x05
    static let z: CGKeyCode = 0x06
    static let x: CGKeyCode = 0x07
    static let c: CGKeyCode = 0x08
    static let v: CGKeyCode = 0x09
    static let b: CGKeyCode = 0x0B
    static let q: CGKeyCode = 0x0C
    static let w: CGKeyCode = 0x0D
    static let e: CGKeyCode = 0x0E
    static let r: CGKeyCode = 0x0F
    static let y: CGKeyCode = 0x10
    static let t: CGKeyCode = 0x11
    static let o: CGKeyCode = 0x1F
    static let u: CGKeyCode = 0x20
    static let i: CGKeyCode = 0x22
    static let p: CGKeyCode = 0x23
    static let l: CGKeyCode = 0x25
    static let j: CGKeyCode = 0x26
    static let k: CGKeyCode = 0x28
    static let n: CGKeyCode = 0x2D
    static let m: CGKeyCode = 0x2E

    // Digits (top row)
    static let one: CGKeyCode = 0x12
    static let two: CGKeyCode = 0x13
    static let three: CGKeyCode = 0x14
    static let four: CGKeyCode = 0x15
    static let five: CGKeyCode = 0x17
    static let six: CGKeyCode = 0x16
    static let seven: CGKeyCode = 0x1A
    static let eight: CGKeyCode = 0x1C
    static let nine: CGKeyCode = 0x19
    static let zero: CGKeyCode = 0x1D

    // Numpad digits (ANSI keypad — corners map to quarter snaps)
    static let keypad0: CGKeyCode = 0x52
    static let keypad1: CGKeyCode = 0x53
    static let keypad2: CGKeyCode = 0x54
    static let keypad3: CGKeyCode = 0x55
    static let keypad4: CGKeyCode = 0x56
    static let keypad5: CGKeyCode = 0x57
    static let keypad6: CGKeyCode = 0x58
    static let keypad7: CGKeyCode = 0x59
    static let keypad8: CGKeyCode = 0x5B
    static let keypad9: CGKeyCode = 0x5C

    // Navigation / editing
    static let leftArrow: CGKeyCode = 0x7B
    static let rightArrow: CGKeyCode = 0x7C
    static let downArrow: CGKeyCode = 0x7D
    static let upArrow: CGKeyCode = 0x7E
    static let delete: CGKeyCode = 0x33       // Backspace
    static let forwardDelete: CGKeyCode = 0x75
    static let tab: CGKeyCode = 0x30
    static let space: CGKeyCode = 0x31
    static let `return`: CGKeyCode = 0x24
    static let escape: CGKeyCode = 0x35
    static let semicolon: CGKeyCode = 0x29
    static let quote: CGKeyCode = 0x27  // apostrophe — Run Shortcuts
    static let comma: CGKeyCode = 0x2B
    static let period: CGKeyCode = 0x2F
    static let slash: CGKeyCode = 0x2C
    static let grave: CGKeyCode = 0x32
    static let home: CGKeyCode = 0x73
    static let end: CGKeyCode = 0x77
    static let pageUp: CGKeyCode = 0x74
    static let pageDown: CGKeyCode = 0x79

    // Hyper trigger / help keys
    static let f18: CGKeyCode = 0x4F
    static let f19: CGKeyCode = 0x50  // dedicated help (Karabiner Hyper+/ → F19)
    static let f20: CGKeyCode = 0x5A
    static let hidF18: CGKeyCode = 0x6D
    static let capsLock: CGKeyCode = 0x39
    static let rightControl: CGKeyCode = 0x3E
    static let rightCommand: CGKeyCode = 0x36
    static let leftCommand: CGKeyCode = 0x37

    /// Human-readable label for a key code (best-effort).
    static func displayName(_ code: CGKeyCode) -> String {
        switch code {
        case leftArrow: return "←"
        case rightArrow: return "→"
        case upArrow: return "↑"
        case downArrow: return "↓"
        case `return`: return "Return"
        case tab: return "Tab"
        case escape: return "Esc"
        case space: return "Space"
        case delete: return "Delete"
        case forwardDelete: return "Fwd Del"
        case semicolon: return ";"
        case quote: return "'"
        case comma: return ","
        case period: return "."
        case slash: return "/"
        case grave: return "`"
        case f19: return "F19"
        case f20: return "F20"
        case f18, hidF18: return "F18"
        case rightControl: return "Right ⌃"
        case rightCommand: return "Right ⌘"
        case one: return "1"
        case two: return "2"
        case three: return "3"
        case four: return "4"
        case five: return "5"
        case six: return "6"
        case seven: return "7"
        case eight: return "8"
        case nine: return "9"
        case zero: return "0"
        case keypad0: return "Num 0"
        case keypad1: return "Num 1"
        case keypad2: return "Num 2"
        case keypad3: return "Num 3"
        case keypad4: return "Num 4"
        case keypad5: return "Num 5"
        case keypad6: return "Num 6"
        case keypad7: return "Num 7"
        case keypad8: return "Num 8"
        case keypad9: return "Num 9"
        case a: return "A"
        case b: return "B"
        case c: return "C"
        case d: return "D"
        case e: return "E"
        case f: return "F"
        case g: return "G"
        case h: return "H"
        case i: return "I"
        case j: return "J"
        case k: return "K"
        case l: return "L"
        case m: return "M"
        case n: return "N"
        case o: return "O"
        case p: return "P"
        case q: return "Q"
        case r: return "R"
        case s: return "S"
        case t: return "T"
        case u: return "U"
        case v: return "V"
        case w: return "W"
        case x: return "X"
        case y: return "Y"
        case z: return "Z"
        default: return "0x\(String(code, radix: 16))"
        }
    }
}
