// ClipboardHistoryPanel.swift
// Non-modal clipboard history for Hyper+V / Hyper+⇧V.
//
// Must work for LSUIElement (menu-bar-only) apps: use orderFrontRegardless.
// Avoid NSMenu.popUp (modal) and avoid force-clearing Hyper on open (that
// desynced Caps and left blockHyperUntilKeyUp stuck).

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    private static var window: NSPanel?
    private static var localMonitor: Any?
    private static var globalMonitor: Any?
    private static var resignObserver: NSObjectProtocol?

    nonisolated private static let visibleLock = NSLock()
    nonisolated(unsafe) private static var visibleFlag = false

    nonisolated static var isShowing: Bool {
        visibleLock.lock()
        defer { visibleLock.unlock() }
        return visibleFlag
    }

    nonisolated private static func setVisible(_ v: Bool) {
        visibleLock.lock()
        visibleFlag = v
        visibleLock.unlock()
    }

    static func show() {
        // Always tear down any prior panel cleanly (fixes leaked sessions).
        teardownUIOnly()
        HyperKeyEngine.shared.noteClipboardPanelVisible(true)

        _ = ClipboardService.shared.poll()
        let items = Array(ClipboardService.shared.history.prefix(12))

        let panel = buildPanel(items: items)
        window = panel
        setVisible(true)

        EscapeCoordinator.shared.setHandler(.clipboardHistory) {
            guard isShowing else { return false }
            hide()
            return true
        }

        // Local: when HyperForge is active. Global: when focus stayed in another app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handlePanelKey(event)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Global monitors cannot swallow; still close / paste.
            _ = handlePanelKey(event, global: true)
        }

        // Place near mouse.
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        {
            let vis = screen.visibleFrame
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)

        // LSUIElement apps often never show windows with plain orderFront.
        panel.orderFrontRegardless()
        // Optional: take key so local Esc works; recovery path still force-clears.
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Banner.show(
            "Clipboard history",
            subtitle: items.isEmpty ? "Empty — copy text first" : "Click or 1–9 · Esc closes",
            style: .info,
            symbol: "list.clipboard",
            duration: 1.6
        )
        HyperLog.event("clipboard panel shown items=\(items.count)")
    }

    static func hide() {
        guard isShowing || window != nil else {
            HyperKeyEngine.shared.noteClipboardPanelVisible(false)
            return
        }
        teardownUIOnly()
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        // Soft clear only — do not block the next Caps press.
        HyperKeyEngine.shared.softClearHyperHold(reason: "clipboard-panel-hide")
        HyperLog.event("clipboard panel hidden")
    }

    /// UI teardown without Hyper side effects (safe to call before re-show).
    private static func teardownUIOnly() {
        setVisible(false)
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        if let mon = globalMonitor {
            NSEvent.removeMonitor(mon)
            globalMonitor = nil
        }
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        EscapeCoordinator.shared.setHandler(.clipboardHistory, handler: nil)
        if let win = window {
            win.orderOut(nil)
            win.close()
        }
        window = nil
    }

    @discardableResult
    private static func handlePanelKey(_ event: NSEvent, global: Bool = false) -> NSEvent? {
        guard isShowing else { return event }

        if event.keyCode == KeyCode.escape {
            hide()
            return global ? event : nil
        }

        let digitMap: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8,
        ]
        if let idx = digitMap[event.keyCode],
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        {
            if ClipboardService.shared.history.indices.contains(idx) {
                hide()
                ClipboardService.shared.pasteHistoryItem(at: idx)
                return global ? event : nil
            }
        }
        return event
    }

    // MARK: - UI

    private static func buildPanel(items: [String]) -> NSPanel {
        let width: CGFloat = 400
        let rowH: CGFloat = 30
        let headerH: CGFloat = 40
        let maxRows = 12
        let rows = max(1, min(items.count, maxRows))
        let footerH: CGFloat = 28
        let height = headerH + CGFloat(rows) * rowH + footerH

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let visual = NSVisualEffectView(frame: root.bounds)
        visual.autoresizingMask = [.width, .height]
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        root.addSubview(visual)

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: height - 32, width: width - 50, height: 20)
        visual.addSubview(title)

        let closeBtn = NSButton(frame: NSRect(x: width - 34, y: height - 34, width: 22, height: 22))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.target = ClipboardHistoryPanelTarget.shared
        closeBtn.action = #selector(ClipboardHistoryPanelTarget.closePanel)
        visual.addSubview(closeBtn)

        if items.isEmpty {
            let empty = NSTextField(labelWithString: "No history yet — copy some text, then try again")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 14, y: footerH + 8, width: width - 28, height: 40)
            empty.maximumNumberOfLines = 2
            visual.addSubview(empty)
        } else {
            for (i, text) in items.enumerated() {
                let y = height - headerH - CGFloat(i + 1) * rowH
                let btn = NSButton(frame: NSRect(x: 10, y: y, width: width - 20, height: rowH - 4))
                btn.bezelStyle = .recessed
                btn.setButtonType(.momentaryPushIn)
                btn.title = "\(i + 1).  \(previewLine(text))"
                btn.alignment = .left
                btn.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                btn.tag = i
                btn.target = ClipboardHistoryPanelTarget.shared
                btn.action = #selector(ClipboardHistoryPanelTarget.pasteItem(_:))
                btn.toolTip = text
                visual.addSubview(btn)
            }
        }

        let hint = NSTextField(labelWithString: "Esc to close")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 14, y: 6, width: width - 28, height: 16)
        visual.addSubview(hint)

        panel.contentView = root
        panel.standardWindowButton(.closeButton)?.target = ClipboardHistoryPanelTarget.shared
        panel.standardWindowButton(.closeButton)?.action = #selector(ClipboardHistoryPanelTarget.closePanel)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Only auto-close if still the same panel and not interacting.
                if window === panel, isShowing {
                    // Don't auto-hide on resign — was killing the panel before user saw it
                    // when focus bounced. User closes with Esc / X / click item.
                }
            }
        }

        return panel
    }

    private static func previewLine(_ text: String) -> String {
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
private final class ClipboardHistoryPanelTarget: NSObject {
    static let shared = ClipboardHistoryPanelTarget()

    @objc func closePanel() {
        ClipboardHistoryPanel.hide()
    }

    @objc func pasteItem(_ sender: NSButton) {
        let idx = sender.tag
        ClipboardHistoryPanel.hide()
        ClipboardService.shared.pasteHistoryItem(at: idx)
    }
}
