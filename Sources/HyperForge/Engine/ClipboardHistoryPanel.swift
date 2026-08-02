// ClipboardHistoryPanel.swift
// Hyper+V / Hyper+⇧V → NSMenu at cursor. Esc closes (not lock). That's it.
//
// Rules:
//   • Swallow V via the engine (handle returns true → return nil). Never clear f18Held on open.
//   • While menu is open, Hyper+Esc is suppressed (pass Esc through to NSMenu).
//   • After popUp returns, resync Hyper released (modal menus often drop Caps keyUp).
//   • Clear latched Caps Lock LED on open if needed (Karabiner blocks normal Caps toggle).

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false

    nonisolated static var isShowing: Bool {
        lock.lock(); defer { lock.unlock() }
        return tracking
    }

    nonisolated static func setTracking(_ value: Bool) {
        lock.lock(); tracking = value; lock.unlock()
    }

    static func show() {
        // If Caps Lock LED is stuck ON (common after earlier bugs), clear it so
        // the next non-Hyper keystroke isn't capitalised. Does not affect F18 hold.
        EventSynthesizer.clearCapsLockIfLatched()

        _ = ClipboardService.shared.poll()
        let items = Array(ClipboardService.shared.history.prefix(15))

        let menu = NSMenu(title: "Clipboard")
        menu.autoenablesItems = false

        if items.isEmpty {
            let empty = NSMenuItem(
                title: "No history yet — copy some text first",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, text) in items.enumerated() {
                let item = NSMenuItem(
                    title: "\(i + 1).  \(preview(text))",
                    action: #selector(Target.paste(_:)),
                    keyEquivalent: i < 9 ? "\(i + 1)" : ""
                )
                item.tag = i
                item.target = Target.shared
                item.toolTip = text
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: "Clear history",
                action: #selector(Target.clear(_:)),
                keyEquivalent: ""
            )
            clear.target = Target.shared
            menu.addItem(clear)
        }

        setTracking(true)
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)

        // popUp is modal; when it returns the menu is gone.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

        setTracking(false)
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        // Caps keyUp was often eaten by the modal menu — treat Hyper as released.
        HyperKeyEngine.shared.resyncHyperAfterMenu()

        HyperLog.event("clipboard menu finished items=\(items.count)")
    }

    static func hide() {
        setTracking(false)
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
    }

    private static func preview(_ text: String) -> String {
        let one = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if one.count <= 56 { return one }
        return String(one.prefix(53)) + "…"
    }
}

@MainActor
private final class Target: NSObject {
    static let shared = Target()

    @objc func paste(_ sender: NSMenuItem) {
        ClipboardService.shared.pasteHistoryItem(at: sender.tag)
    }

    @objc func clear(_ sender: NSMenuItem) {
        ClipboardService.shared.clearHistory()
        Banner.show("History cleared", style: .neutral, symbol: "trash")
    }
}
