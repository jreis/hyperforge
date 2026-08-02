// ClipboardHistoryPanel.swift
// Hyper+V → large floating panel. Esc closes. Never blocks on pasteboard.

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false
    private static var window: NSPanel?
    private static var localMonitor: Any?

    nonisolated static var isShowing: Bool {
        lock.lock(); defer { lock.unlock() }
        return tracking
    }

    nonisolated static func setTracking(_ value: Bool) {
        lock.lock(); tracking = value; lock.unlock()
    }

    static func show() {
        HyperDebug.log("clipboard.show 1 enter")

        if isShowing {
            HyperDebug.log("clipboard.show already open → front")
            window?.orderFrontRegardless()
            return
        }

        // In-memory history only — never block the main thread on NSPasteboard.
        let items = Array(ClipboardService.shared.history.prefix(15))
        HyperDebug.log("clipboard.show 2 items=\(items.count)")

        let panel = makePanel(items: items)
        HyperDebug.log("clipboard.show 3 panel built")

        window = panel
        setTracking(true)
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let size = panel.frame.size
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.midY - size.height / 2
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        HyperDebug.log("clipboard.show 4 positioned")

        // No NSApp.activate — can hang / steal focus badly for LSUIElement apps.
        panel.orderFrontRegardless()
        HyperDebug.log("clipboard.show 5 ordered front")

        installEscMonitor()
        HyperDebug.log("clipboard.show 6 monitors")

        Banner.show(
            "Clipboard history",
            subtitle: items.isEmpty
                ? "Empty list · copy text, then Hyper+V again · Esc closes"
                : "Pick a row · Esc closes",
            style: .success,
            symbol: "list.clipboard",
            duration: 2.5
        )
        HyperDebug.log("clipboard.show DONE items=\(items.count)")

        // Fill history off the hot path (pasteboard can block).
        DispatchQueue.global(qos: .userInitiated).async {
            let text = NSPasteboard.general.string(forType: .string)
            guard let text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                ClipboardService.shared.record(text)
            }
        }
    }

    static func hide() {
        HyperDebug.log("clipboard.hide")
        setTracking(false)
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        HyperKeyEngine.shared.resyncHyperAfterMenu()
    }

    private static func installEscMonitor() {
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isShowing else { return event }
            if event.keyCode == KeyCode.escape {
                hide()
                return nil
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
                return nil
            }
            return event
        }
    }

    private static func makePanel(items: [String]) -> NSPanel {
        let width: CGFloat = 460
        let rowH: CGFloat = 36
        let headerH: CGFloat = 52
        let footerH: CGFloat = 40
        let n = max(1, min(items.count, 12))
        let height = headerH + CGFloat(n) * rowH + footerH

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "HyperForge — Clipboard"
        panel.isFloatingPanel = true
        panel.level = .screenSaver // above almost everything
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 16, y: height - 40, width: width - 40, height: 24)
        content.addSubview(title)

        if items.isEmpty {
            let empty = NSTextField(
                wrappingLabelWithString: "No clips saved yet.\nCopy text somewhere, then press Hyper+V again.\n\n(Esc closes this window)"
            )
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 16, y: 50, width: width - 32, height: 100)
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

        let hint = NSTextField(labelWithString: "Esc to close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 16, y: 12, width: width - 32, height: 18)
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
