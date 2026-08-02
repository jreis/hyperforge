// ClipboardHistoryPanel.swift
// Hyper+V → show history. Esc closes. Swallow V so Ghostty never sees it.
//
// Uses a temporary NSStatusItem to present the menu. That is the reliable way
// for LSUIElement (menu-bar-only) apps — plain NSMenu.popUp often never appears.

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false
    private static var statusItem: NSStatusItem?

    nonisolated static var isShowing: Bool {
        lock.lock(); defer { lock.unlock() }
        return tracking
    }

    nonisolated static func setTracking(_ value: Bool) {
        lock.lock(); tracking = value; lock.unlock()
    }

    static func show() {
        // Avoid re-entrancy if already open.
        if isShowing {
            HyperDebug.log("clipboard.show ignored (already open)")
            return
        }

        HyperDebug.log("clipboard.show begin")

        _ = ClipboardService.shared.poll()
        let items = Array(ClipboardService.shared.history.prefix(15))

        let menu = NSMenu(title: "Clipboard")
        menu.autoenablesItems = false
        menu.delegate = MenuLifecycle.shared

        if items.isEmpty {
            let empty = NSMenuItem(
                title: "No history — copy text, then Hyper+V again",
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
                    keyEquivalent: ""
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

        // Temporary status item → performClick is the reliable LSUIElement popup path.
        // Call only when Caps is already up (see scheduleClipboardMenuAfterCapsRelease).
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: "Clipboard"
            )
            button.toolTip = "HyperForge clipboard"
            item.menu = menu
            button.performClick(nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            menuDidClose()
        }

        HyperDebug.log("clipboard.show finished items=\(items.count)")
    }

    static func hide() {
        menuDidClose()
    }

    fileprivate static func menuDidClose() {
        guard isShowing || statusItem != nil else { return }
        setTracking(false)
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        if let item = statusItem {
            item.menu = nil
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        // Modal/status menu often eats Caps keyUp — resync Hyper as released.
        HyperKeyEngine.shared.resyncHyperAfterMenu()
        HyperDebug.log("clipboard.menuDidClose")
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

@MainActor
private final class MenuLifecycle: NSObject, NSMenuDelegate {
    static let shared = MenuLifecycle()

    func menuDidClose(_ menu: NSMenu) {
        ClipboardHistoryPanel.menuDidClose()
    }
}

// MARK: - Always-on debug log (local diagnosis; no network)

enum HyperDebug {
    private static let path = "/tmp/hyperforge-debug.log"
    private static let lock = NSLock()

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    defer { try? h.close() }
                    _ = try? h.seekToEnd()
                    try? h.write(contentsOf: data)
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
