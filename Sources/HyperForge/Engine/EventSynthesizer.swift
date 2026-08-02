// EventSynthesizer.swift
// Low-level CGEvent helpers for keystrokes, scroll, and unicode typing.
// Synthetic events are tagged with eventSourceUserData so HyperKeyEngine
// never re-intercepts them (more reliable than a pass-through counter).

import AppKit
import CoreGraphics
import Foundation

enum EventSynthesizer {
    /// 'HyFg' — marks keys we inject so the session tap lets them through.
    static let syntheticMarker: Int64 = 0x4879_4667

    private static let lock = NSLock()
    /// Legacy counter kept as a backup for events that lose userData.
    private static var passThroughRemaining = 0

    private static let source: CGEventSource? = {
        // combinedSessionState is what most apps (incl. Chromium) accept as “real” input.
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.localEventsSuppressionInterval = 0
        return src
    }()

    private static let hidSource: CGEventSource? = {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.localEventsSuppressionInterval = 0
        return src
    }()

    static var hasPassThrough: Bool {
        lock.lock(); defer { lock.unlock() }
        return passThroughRemaining > 0
    }

    @discardableResult
    static func consumePassThroughIfNeeded() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard passThroughRemaining > 0 else { return false }
        passThroughRemaining -= 1
        return true
    }

    /// Prefer marker; fall back to counter for older paths.
    static func shouldPassThrough(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return true
        }
        return consumePassThroughIfNeeded()
    }

    private static func expectPassThrough(_ count: Int) {
        lock.lock()
        passThroughRemaining += count
        lock.unlock()
    }

    private static func makeKeyEvent(
        virtualKey keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> CGEvent? {
        // Prefer session source; fall back to HID source if creation fails.
        let ev =
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            ?? CGEvent(keyboardEventSource: hidSource, virtualKey: keyCode, keyDown: keyDown)
            ?? CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
        guard let ev else { return nil }
        ev.flags = flags
        ev.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        ev.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        return ev
    }

    /// HID stream only (re-enters our tap; marker lets us pass through).
    /// Do not also postToPid — that can double-fire or skip the tap and desync counters.
    private static func deliver(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }

    /// Post a key down/up pair (or a single edge when `keyDown` is set).
    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], keyDown: Bool? = nil) {
        if let keyDown {
            guard let ev = makeKeyEvent(virtualKey: keyCode, keyDown: keyDown, flags: flags)
            else { return }
            deliver(ev)
        } else {
            guard let down = makeKeyEvent(virtualKey: keyCode, keyDown: true, flags: flags),
                  let up = makeKeyEvent(virtualKey: keyCode, keyDown: false, flags: flags)
            else { return }
            deliver(down)
            deliver(up)
        }
    }

    /// Key-up only (no down). Used to unstick modifiers after modal NSMenu ate the real keyUp.
    static func postKeyUp(_ keyCode: CGKeyCode) {
        guard let up = makeKeyEvent(virtualKey: keyCode, keyDown: false, flags: []) else { return }
        deliver(up)
    }

    /// Unstick ⌘⌥⌃⇧ + F18 after a bad latch. Does not touch Caps Lock by default.
    static func releaseStuckHyperKeys() {
        let ups: [CGKeyCode] = [
            0x37, 0x36, // ⌘ left / right
            0x3A, 0x3D, // ⌥ left / right
            0x3B, 0x3E, // ⌃ left / right
            0x38, 0x3C, // ⇧ left / right
            0x4F, 0x6D, // F18 / HID F18 (Karabiner Caps→F18)
        ]
        for code in ups {
            postKeyUp(code)
        }
        HyperLog.event("releaseStuckHyperKeys: modifier + F18 keyUps posted")
    }

    /// If the Caps Lock *toggle* (LED) is latched ON, pulse Caps once to turn it off.
    ///
    /// Critical with Karabiner Caps→F18: the physical Caps key never reaches the OS, so
    /// a latched Caps Lock LED can only be cleared by injecting caps_lock. Otherwise the
    /// user is stuck typing CAPITALS forever and Hyper+V looks like a capital V.
    static func clearCapsLockIfLatched() {
        let flags = CGEventSource.flagsState(.hidSystemState)
        guard flags.contains(.maskAlphaShift) else { return }
        // Our event tap swallows real caps_lock — mark as synthetic so it passes through.
        postKey(0x39 /* caps_lock */)
        HyperLog.event("clearCapsLockIfLatched: pulsed Caps Lock to clear LED")
    }

    /// ⌘W-style close: press Command, press W, release W, release Command.
    static func postCommandKey(_ keyCode: CGKeyCode) {
        let cmd: CGKeyCode = 0x37
        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (cmd, true, .maskCommand),
            (keyCode, true, .maskCommand),
            (keyCode, false, .maskCommand),
            (cmd, false, []),
        ]
        for (code, down, flags) in events {
            guard let ev = makeKeyEvent(virtualKey: code, keyDown: down, flags: flags)
            else { continue }
            deliver(ev)
        }
    }

    static func postScroll(dy: Int32) {
        guard
            let ev = CGEvent(
                scrollWheelEvent2Source: source ?? hidSource,
                units: .pixel,
                wheelCount: 1,
                wheel1: dy,
                wheel2: 0,
                wheel3: 0
            )
        else { return }
        ev.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        deliver(ev)
    }

    static func postScrollHorizontal(dx: Int32) {
        guard
            let ev = CGEvent(
                scrollWheelEvent2Source: source ?? hidSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: dx,
                wheel3: 0
            )
        else { return }
        ev.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        deliver(ev)
    }

    static func typeString(_ str: String) {
        HyperLog.event("typeString: \(str.prefix(40).replacingOccurrences(of: "\n", with: "↵"))")
        for ch in str {
            switch ch {
            case "\n", "\r":
                postKey(KeyCode.return)
            case "\t":
                postKey(KeyCode.tab)
            default:
                guard let down = makeKeyEvent(virtualKey: 0, keyDown: true, flags: []),
                      let up = makeKeyEvent(virtualKey: 0, keyDown: false, flags: [])
                else { continue }
                var utf16 = Array(String(ch).utf16)
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                deliver(down)
                deliver(up)
            }
        }
    }
}
