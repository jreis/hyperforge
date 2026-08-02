// ClipboardHistoryPanel.swift
// Non-modal clipboard history UI for Hyper+⇧V.
//
// NSMenu.popUp is modal and routinely eats Caps→F18 keyUps, which left Hyper
// and (via our recovery key synthesis) Caps Lock stuck. This panel keeps the
// normal event stream alive so Caps release is always seen.

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    private static var window: NSPanel?
    private static var localMonitor: Any?
    /// Atomic for event-tap reads (HyperKeyEngine is not MainActor).
    private static let visibleLock = NSLock()
    nonisolated(unsafe) private static var visibleFlag = false

    /// Safe from the CGEvent tap thread.
    nonisolated static var isShowing: Bool {
        visibleLock.lock()
        defer { visibleLock.unlock() }
        return visibleFlag
    }

    private static func setVisible(_ v: Bool) {
        visibleLock.lock()
        visibleFlag = v
        visibleLock.unlock()
    }

    static func show() {
        _ = ClipboardService.shared.poll()
        // Never synthesize Caps Lock down/up — that toggles the LED and sticks Caps ON.
        HyperKeyEngine.shared.forceClearHyperHold(reason: "clipboard-panel-show", releaseHardware: true)
        HyperKeyEngine.shared.beginNonModalUISession()

        hide(clearHyper: false)

        let items = ClipboardService.shared.history
        let panel = buildPanel(items: items)
        window = panel
        setVisible(true)

        // Esc closes panel without going through Hyper+Esc lock.
        EscapeCoordinator.shared.setHandler(.clipboardHistory) {
            guard ClipboardHistoryPanel.isShowing else { return false }
            hide(clearHyper: true)
            return true
        }

        // Local monitor for 1–9 paste and Esc (EscapeCoordinator also handles Esc).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == KeyCode.escape {
                hide(clearHyper: true)
                return nil
            }
            // Digit keys 1–9 paste history items when panel is key.
            let digitMap: [UInt16: Int] = [
                0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
                0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8,
            ]
            if let idx = digitMap[event.keyCode],
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            {
                if ClipboardService.shared.history.indices.contains(idx) {
                    hide(clearHyper: true)
                    ClipboardService.shared.pasteHistoryItem(at: idx)
                    return nil
                }
            }
            return event
        }

        // Place near mouse, keep on-screen.
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - panel.frame.height - 8)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        {
            let vis = screen.visibleFrame
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Banner.show(
            "Clipboard history",
            subtitle: items.isEmpty ? "Copy text, then ⇧V again" : "1–9 paste · Esc close",
            style: .info,
            symbol: "list.clipboard",
            duration: 1.4
        )
    }

    static func hide(clearHyper: Bool = true) {
        let wasShowing = isShowing || window != nil
        guard wasShowing else {
            if clearHyper {
                HyperKeyEngine.shared.endNonModalUISession()
                HyperKeyEngine.shared.forceClearHyperHold(
                    reason: "clipboard-panel-hide",
                    releaseHardware: true
                )
            }
            return
        }
        setVisible(false)
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        EscapeCoordinator.shared.setHandler(.clipboardHistory, handler: nil)
        window?.orderOut(nil)
        window?.close()
        window = nil
        if clearHyper {
            HyperKeyEngine.shared.endNonModalUISession()
            HyperKeyEngine.shared.forceClearHyperHold(
                reason: "clipboard-panel-hide",
                releaseHardware: true
            )
        }
    }

    // MARK: - UI

    private static func buildPanel(items: [String]) -> NSPanel {
        let width: CGFloat = 380
        let rowH: CGFloat = 28
        let headerH: CGFloat = 36
        let maxRows = 12
        let rows = max(1, min(items.count, maxRows))
        let height = headerH + CGFloat(rows) * rowH + 12 + (items.isEmpty ? 0 : 8)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

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
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 14, y: height - 28, width: width - 80, height: 18)
        visual.addSubview(title)

        let closeBtn = NSButton(
            frame: NSRect(x: width - 32, y: height - 30, width: 20, height: 20)
        )
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = .tertiaryLabelColor
        closeBtn.target = ClipboardHistoryPanelTarget.shared
        closeBtn.action = #selector(ClipboardHistoryPanelTarget.closePanel)
        visual.addSubview(closeBtn)

        if items.isEmpty {
            let empty = NSTextField(labelWithString: "No history yet — copy text first")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            empty.frame = NSRect(x: 14, y: 16, width: width - 28, height: 20)
            visual.addSubview(empty)
        } else {
            for (i, text) in items.prefix(maxRows).enumerated() {
                let y = height - headerH - CGFloat(i + 1) * rowH
                let btn = NSButton(frame: NSRect(x: 8, y: y, width: width - 16, height: rowH - 2))
                btn.bezelStyle = .recessed
                btn.setButtonType(.momentaryPushIn)
                let preview = previewLine(text)
                btn.title = "\(i + 1).  \(preview)"
                btn.alignment = .left
                btn.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                btn.tag = i
                btn.target = ClipboardHistoryPanelTarget.shared
                btn.action = #selector(ClipboardHistoryPanelTarget.pasteItem(_:))
                btn.toolTip = text
                visual.addSubview(btn)
            }
        }

        panel.contentView = root
        // Close when panel resigns key (click outside-ish).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            // Slight delay so a button click still fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if window === panel, isShowing {
                    hide(clearHyper: true)
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
        if one.count <= 48 { return one }
        return String(one.prefix(45)) + "…"
    }
}

@MainActor
private final class ClipboardHistoryPanelTarget: NSObject {
    static let shared = ClipboardHistoryPanelTarget()

    @objc func closePanel() {
        ClipboardHistoryPanel.hide(clearHyper: true)
    }

    @objc func pasteItem(_ sender: NSButton) {
        let idx = sender.tag
        ClipboardHistoryPanel.hide(clearHyper: true)
        ClipboardService.shared.pasteHistoryItem(at: idx)
    }
}
