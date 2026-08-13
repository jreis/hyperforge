// SystemControls.swift
// Hardware-style system controls (volume, brightness, Focus/DND). Volume and
// brightness post the same NX system-defined events real media keys generate, so
// macOS applies the change and shows its native on-screen HUD — no private
// CoreAudio/DisplayServices calls needed.

import AppKit
import Foundation

enum SystemControls {
    // NX_KEYTYPE_* constants (IOKit/hidsystem/ev_keymap.h)
    private static let keySoundUp: Int32 = 0
    private static let keySoundDown: Int32 = 1
    private static let keyMute: Int32 = 7
    private static let keyBrightnessUp: Int32 = 2
    private static let keyBrightnessDown: Int32 = 3

    static func volumeUp() { postMediaKey(keySoundUp) }
    static func volumeDown() { postMediaKey(keySoundDown) }
    static func toggleMute() { postMediaKey(keyMute) }
    static func brightnessUp() { postMediaKey(keyBrightnessUp) }
    static func brightnessDown() { postMediaKey(keyBrightnessDown) }

    /// Runs a "Toggle Focus" Shortcut the user creates in Shortcuts.app (with a
    /// "Set Focus" action) — macOS has no stable public API for Focus/DND, and
    /// Shortcuts' own Focus actions are Apple's sanctioned way to script it.
    static func toggleFocus() {
        let name = "Toggle Focus"
        if ShortcutsService.listNames().contains(name) {
            ShortcutsService.run(name: name)
        } else {
            Banner.show(
                "No “\(name)” Shortcut",
                subtitle: "Create one in Shortcuts.app with a Set Focus action",
                style: .warning,
                symbol: "moon"
            )
        }
    }

    /// Posts the same NX system-defined key event a hardware media key sends.
    private static func postMediaKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (Int(key) << 16) | (down ? 0xa00 : 0xb00)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
