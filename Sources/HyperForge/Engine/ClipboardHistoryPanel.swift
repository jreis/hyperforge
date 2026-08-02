// ClipboardHistoryPanel.swift
// Simple clipboard history for Hyper+V / Hyper+⇧V.
//
// Design (intentionally boring):
//   1. Hyper+V → swallow V, show NSMenu at cursor
//   2. Esc → NSMenu dismisses (we never treat it as Hyper+Esc lock)
//   3. Never touch Caps/F18 latch while the menu is open
//   4. After popUp returns, resync Hyper as released (modal menus often drop keyUp)

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    /// True while `NSMenu.popUp` is on the stack (read from event tap).
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false

    nonisolated static var isShowing: Bool {
        lock.lock(); defer { lock.unlock() }
        return tracking
    }

    nonisolated static func setTracking(_ value: Bool) {
        lock.lock(); tracking = value; lock.unlock()
    }

    /// Hyper+V entry point. Call only on the main thread.
    static func show() {
        _ = ClipboardService.shared.poll()
        let items = Array(ClipboardService.shared.history.prefix(12))

        let menu = NSMenu(title: "Clipboard")
        menu.autoenablesItems = false

        if items.isEmpty {
            let empty = NSMenuItem(
                title: "No history — copy text first",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (i, text) in items.enumerated() {
                let title = "\(i + 1).  \(preview(text))"
                let item = NSMenuItem(
                    title: title,
                    action: #selector(ClipboardHistoryMenuTarget.paste(_:)),
                    keyEquivalent: i < 9 ? "\(i + 1)" : ""
                )
                item.tag = i
                item.target = ClipboardHistoryMenuTarget.shared
                item.toolTip = text
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: "Clear history",
                action: #selector(ClipboardHistoryMenuTarget.clear(_:)),
                keyEquivalent: ""
            )
            clear.target = ClipboardHistoryMenuTarget.shared
            menu.addItem(clear)
        }

        // Mark tracking so Hyper+Esc is suppressed while the menu is open.
        setTracking(true)
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)
        defer {
            setTracking(false)
            HyperKeyEngine.shared.noteClipboardPanelVisible(false)
            // Modal menu often ate Caps/F18 keyUp — treat Hyper as released.
            HyperKeyEngine.shared.resyncHyperAfterMenu()
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Kept for call sites that used hide() — NSMenu is already gone after popUp.
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
private final class ClipboardHistoryMenuTarget: NSObject {
    static let shared = ClipboardHistoryMenuTarget()

    @objc func paste(_ sender: NSMenuItem) {
        ClipboardService.shared.pasteHistoryItem(at: sender.tag)
    }

    @objc func clear(_ sender: NSMenuItem) {
        ClipboardService.shared.clearHistory()
        Banner.show("History cleared", style: .neutral, symbol: "trash")
    }
}
