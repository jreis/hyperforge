// EventSynthesizer.swift
// Low-level CGEvent helpers for keystrokes, scroll, and unicode typing.
// Synthetic events are tagged so HyperKeyEngine does not re-intercept them
// while Hyper (F18) is still held — e.g. Hyper+X → ⌘W for close window.

import AppKit
import CoreGraphics
import Foundation

enum EventSynthesizer {
    private static let lock = NSLock()
    /// Number of upcoming keyboard events that must pass through the tap untouched.
    private static var passThroughRemaining = 0

    /// True while we are expecting our own injected key events.
    static var hasPassThrough: Bool {
        lock.lock(); defer { lock.unlock() }
        return passThroughRemaining > 0
    }

    /// Call from the event tap when a keyboard event arrives; returns true if this
    /// event should skip Hyper/Vim handling (it is one we just posted).
    @discardableResult
    static func consumePassThroughIfNeeded() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard passThroughRemaining > 0 else { return false }
        passThroughRemaining -= 1
        return true
    }

    private static func expectPassThrough(_ count: Int) {
        lock.lock()
        passThroughRemaining += count
        lock.unlock()
    }

    /// Post a key down/up pair (or a single edge when `keyDown` is set).
    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], keyDown: Bool? = nil) {
        if let keyDown {
            expectPassThrough(1)
            guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
            else {
                // Roll back the reservation if we failed to create the event.
                _ = consumePassThroughIfNeeded()
                return
            }
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
        } else {
            expectPassThrough(2)  // down + up
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            else {
                // Best-effort: clear both reservations.
                _ = consumePassThroughIfNeeded()
                _ = consumePassThroughIfNeeded()
                return
            }
            down.flags = flags
            down.post(tap: .cghidEventTap)
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    /// ⌘W-style close: press Command, press W, release W, release Command.
    /// More reliable than a single key event with flags for some apps.
    static func postCommandKey(_ keyCode: CGKeyCode) {
        // left Command = 0x37
        let cmd: CGKeyCode = 0x37
        expectPassThrough(4)
        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (cmd, true, .maskCommand),
            (keyCode, true, .maskCommand),
            (keyCode, false, .maskCommand),
            (cmd, false, []),
        ]
        for (code, down, flags) in events {
            guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            else { continue }
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
            usleep(1_000)
        }
    }

    static func postScroll(dy: Int32) {
        guard
            let ev = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: dy,
                wheel2: 0,
                wheel3: 0
            )
        else { return }
        ev.post(tap: .cghidEventTap)
    }

    static func postScrollHorizontal(dx: Int32) {
        guard
            let ev = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: dx,
                wheel3: 0
            )
        else { return }
        ev.post(tap: .cghidEventTap)
    }

    /// Type a string via unicode keyboard events (slow enough for apps to accept).
    static func typeString(_ str: String) {
        HyperLog.event("typeString: \(str.prefix(40))")
        for ch in str {
            expectPassThrough(2)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                _ = consumePassThroughIfNeeded()
                _ = consumePassThroughIfNeeded()
                continue
            }
            var utf16 = Array(String(ch).utf16)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
            guard let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                _ = consumePassThroughIfNeeded()
                continue
            }
            up.post(tap: .cghidEventTap)
            usleep(5_000)
        }
    }
}
