// ClipboardHistoryPanel.swift
// Hyper+V → big floating panel (not a status-item flash). Esc closes.
// Opened after Caps release so the menu isn't killed by Hyper modifiers.

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false
    private static var window: NSPanel?
    private static var localMonitor: Any?
    private static var globalMonitor: Any?

    nonisolated static var isShowing: Bool {
        lock.lock(); defer { lock.unlock() }
        return tracking
    }

    nonisolated static func setTracking(_ value: Bool) {
        lock.lock(); tracking = value; lock.unlock()
    }

    static func show() {
        if isShowing {
            HyperDebug.log("clipboard.show ignored (already open)")
            bringToFront()
            return
        }

        HyperDebug.log("clipboard.show begin")
        EventSynthesizer.clearCapsLockIfLatched()

        _ = ClipboardService.shared.poll()
        // Always include current pasteboard text even if poll thought nothing changed.
        if let cur = NSPasteboard.general.string(forType: .string), !cur.isEmpty {
            ClipboardService.shared.record(cur)
        }
        let items = Array(ClipboardService.shared.history.prefix(15))

        let panel = buildPanel(items: items)
        window = panel
        setTracking(true)
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)

        // Center on main screen — impossible to miss (status-item menus were easy to miss).
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = panel.frame
            let x = screen.visibleFrame.midX - f.width / 2
            let y = screen.visibleFrame.midY - f.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitors()

        Banner.show(
            "Clipboard history",
            subtitle: items.isEmpty ? "Empty — copy text first · Esc closes" : "Click a row or 1–9 · Esc closes",
            style: .info,
            symbol: "list.clipboard",
            duration: 2.0
        )
        HyperDebug.log("clipboard.show finished items=\(items.count)")
    }

    static func hide() {
        guard isShowing || window != nil else { return }
        teardown()
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        HyperKeyEngine.shared.resyncHyperAfterMenu()
        HyperDebug.log("clipboard.hide")
    }

    private static func bringToFront() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func teardown() {
        setTracking(false)
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        if let mon = globalMonitor {
            NSEvent.removeMonitor(mon)
            globalMonitor = nil
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    private static func installKeyMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event, global: false)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleKey(event, global: true)
        }
    }

    @discardableResult
    private static func handleKey(_ event: NSEvent, global: Bool) -> NSEvent? {
        guard isShowing else { return event }
        if event.keyCode == KeyCode.escape {
            hide()
            return global ? event : nil
        }
        let digits: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8,
        ]
        if let idx = digits[event.keyCode],
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        {
            if ClipboardService.shared.history.indices.contains(idx) {
                hide()
                ClipboardService.shared.pasteHistoryItem(at: idx)
                return global ? event : nil
            }
        }
        return event
    }

    private static func buildPanel(items: [String]) -> NSPanel {
        let width: CGFloat = 440
        let rowH: CGFloat = 34
        let headerH: CGFloat = 48
        let footerH: CGFloat = 36
        let rows = max(1, min(items.count, 12))
        let height = headerH + CGFloat(rows) * rowH + footerH + 16

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "HyperForge Clipboard"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = NSColor.windowBackgroundColor

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.frame = NSRect(x: 16, y: height - 36, width: width - 50, height: 24)
        root.addSubview(title)

        if items.isEmpty {
            let empty = NSTextField(
                wrappingLabelWithString: "Nothing saved yet.\nCopy some text, then press Hyper+V again."
            )
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 16, y: footerH + 20, width: width - 32, height: 60)
            root.addSubview(empty)
        } else {
            for (i, text) in items.enumerated() {
                let y = height - headerH - CGFloat(i + 1) * rowH
                let btn = NSButton(frame: NSRect(x: 12, y: y, width: width - 24, height: rowH - 4))
                btn.bezelStyle = .rounded
                btn.setButtonType(.momentaryPushIn)
                btn.title = "\(i + 1).  \(preview(text))"
                btn.alignment = .left
                btn.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                btn.tag = i
                btn.target = Target.shared
                btn.action = #selector(Target.paste(_:))
                btn.toolTip = text
                root.addSubview(btn)
            }
        }

        let hint = NSTextField(labelWithString: "Esc to close  ·  1–9 to paste")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 16, y: 10, width: width - 32, height: 18)
        root.addSubview(hint)

        panel.contentView = root
        panel.standardWindowButton(.closeButton)?.target = Target.shared
        panel.standardWindowButton(.closeButton)?.action = #selector(Target.close)
        return panel
    }

    private static func preview(_ text: String) -> String {
        let one = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if one.count <= 52 { return one }
        return String(one.prefix(49)) + "…"
    }
}

@MainActor
private final class Target: NSObject {
    static let shared = Target()

    @objc func paste(_ sender: NSButton) {
        let idx = sender.tag
        ClipboardHistoryPanel.hide()
        ClipboardService.shared.pasteHistoryItem(at: idx)
    }

    @objc func close() {
        ClipboardHistoryPanel.hide()
    }

    @objc func clear(_ sender: Any?) {
        ClipboardService.shared.clearHistory()
        Banner.show("History cleared", style: .neutral, symbol: "trash")
    }
}
