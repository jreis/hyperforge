// ClipboardHistoryPanel.swift
// Hyper+V → large floating panel. Esc closes globally (no click required).

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
        HyperDebug.log("clipboard.show enter")

        if isShowing {
            activatePanel()
            return
        }

        _ = ClipboardService.shared.poll()
        if let cur = NSPasteboard.general.string(forType: .string), !cur.isEmpty {
            ClipboardService.shared.record(cur)
        }
        let items = Array(ClipboardService.shared.history.prefix(15))
        let empty = items.isEmpty

        let panel = makePanel(items: items)
        window = panel
        setTracking(true)
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let size = panel.frame.size
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.midY - size.height / 2
            panel.setFrame(
                NSRect(x: x, y: y, width: size.width, height: size.height),
                display: true
            )
        }

        activatePanel()
        installKeyMonitors()

        if empty {
            Banner.show(
                "Clipboard history",
                subtitle: "Nothing saved yet — copy text, then Hyper+V again",
                style: .info,
                symbol: "list.clipboard",
                duration: 2.2
            )
        }

        HyperDebug.log("clipboard.show DONE items=\(items.count)")
    }

    static func hide() {
        HyperDebug.log("clipboard.hide")
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
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        HyperKeyEngine.shared.resyncHyperAfterMenu()
    }

    /// Make the panel key so local Esc/digits work; event tap also closes on Esc.
    private static func activatePanel() {
        guard let panel = window else { return }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        // Safe activation for menu-bar apps so the panel becomes first responder.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(panel.contentView)
    }

    private static func installKeyMonitors() {
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        if let mon = globalMonitor {
            NSEvent.removeMonitor(mon)
            globalMonitor = nil
        }

        // Local: when panel/app is key.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event, swallow: true)
        }
        // Global: Esc still works if focus stayed in another app (tap also handles Esc).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == KeyCode.escape, isShowing {
                DispatchQueue.main.async { hide() }
            }
        }
    }

    @discardableResult
    private static func handleKey(_ event: NSEvent, swallow: Bool) -> NSEvent? {
        guard isShowing else { return event }
        if event.keyCode == KeyCode.escape {
            hide()
            return swallow ? nil : event
        }
        let map: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8,
        ]
        if let idx = map[event.keyCode],
           ClipboardService.shared.history.indices.contains(idx)
        {
            hide()
            ClipboardService.shared.pasteHistoryItem(at: idx)
            return swallow ? nil : event
        }
        return event
    }

    private static func makePanel(items: [String]) -> NSPanel {
        let width: CGFloat = 460
        let rowH: CGFloat = 36
        let headerH: CGFloat = 56
        let footerH: CGFloat = 44
        let n = max(1, min(max(items.count, 1), 12))
        let height = headerH + CGFloat(n) * rowH + footerH

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "HyperForge — Clipboard"
        panel.isFloatingPanel = true
        panel.level = .floating
        // canJoinAllSpaces + moveToActiveSpace are mutually exclusive; combining them
        // triggers NSWindow._validateCollectionBehavior: → SIGABRT (Hyper+V crash).
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 16, y: height - 42, width: width - 40, height: 24)
        content.addSubview(title)

        if items.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: """
            Nothing saved yet.

            1. Copy any text (⌘C)
            2. Hold Caps (Hyper) and press V
            3. Release Caps — this window opens

            Esc closes anytime.
            """)
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 20, y: footerH, width: width - 40, height: height - headerH - footerH)
            content.addSubview(empty)
        } else {
            for (i, text) in items.enumerated() {
                let y = height - headerH - CGFloat(i + 1) * rowH + 4
                let btn = NSButton(
                    frame: NSRect(x: 12, y: y, width: width - 24, height: rowH - 6)
                )
                btn.bezelStyle = .rounded
                btn.title = "\(i + 1).  \(preview(text))"
                btn.alignment = .left
                btn.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                btn.tag = i
                btn.target = PanelTarget.shared
                btn.action = #selector(PanelTarget.paste(_:))
                btn.toolTip = text
                content.addSubview(btn)
            }
        }

        let hint = NSTextField(labelWithString: "Esc to close  ·  1–9 to paste")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 16, y: 14, width: width - 32, height: 18)
        content.addSubview(hint)

        panel.contentView = content
        return panel
    }

    private static func preview(_ text: String) -> String {
        let one = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if one.count <= 54 { return one }
        return String(one.prefix(51)) + "…"
    }
}

@MainActor
private final class PanelTarget: NSObject {
    static let shared = PanelTarget()

    @objc func paste(_ sender: NSButton) {
        let idx = sender.tag
        ClipboardHistoryPanel.hide()
        ClipboardService.shared.pasteHistoryItem(at: idx)
    }
}
