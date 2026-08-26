// ClipboardHistoryPanel.swift
// Hyper+V → large floating panel. Esc closes globally (no click required).

import AppKit
import Foundation

@MainActor
enum ClipboardHistoryPanel {
    /// Rows shown; must match the digit-key map below (1–9) so every visible
    /// row is keyboard-reachable.
    private static let maxRows = 9

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var tracking = false
    private static var window: NSPanel?
    private static var localMonitor: Any?
    private static var globalMonitor: Any?
    /// Live type-to-filter buffer (substring match, case-insensitive).
    private static var filterBuffer = ""

    /// Front app when the panel opened — restore it before ⌘V so paste hits that app.
    private static var pasteTarget: NSRunningApplication?

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
            orderPanelFront()
            return
        }

        capturePasteTarget()
        _ = ClipboardService.shared.poll()
        if let cur = NSPasteboard.general.string(forType: .string), !cur.isEmpty {
            ClipboardService.shared.record(cur)
        }
        filterBuffer = ""
        let items = displayedEntries()
        let empty = items.isEmpty

        let panel = makePanel(entries: items, filter: filterBuffer)
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

        // Do not activate HyperForge. Digit keys go through the event tap
        // (`consumeEngineKey`) so the front app stays the paste target.
        orderPanelFront()
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
        filterBuffer = ""
        pasteTarget = nil
        HyperKeyEngine.shared.noteClipboardPanelVisible(false)
        HyperKeyEngine.shared.resyncHyperAfterMenu()
    }

    /// True when the event tap must swallow this key so it does not type into the front app
    /// and so sticky Hyper does not treat 1–9 as app-slot chords.
    nonisolated static func shouldConsumeKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard isShowing else { return false }
        if keyCode == KeyCode.escape { return true }
        if flags.contains(.maskCommand) { return false }
        // Swallow typing, digits, Return, and Delete. Leave media / function keys alone.
        return keyCode <= KeyCode.upArrow
    }

    /// Apply a swallowed key on the main actor (panel is @MainActor).
    static func consumeEngineKey(keyCode: CGKeyCode, flags: CGEventFlags, characters: String) {
        guard isShowing else { return }
        _ = handleEngineKey(keyCode: keyCode, flags: flags, characters: characters)
    }

    /// Restore the app that was front when the panel opened, then paste.
    static func restorePasteTargetThenPaste(_ entry: ClipboardEntry) {
        let target = pasteTarget
        hide()
        ClipboardService.shared.preparePasteboard(entry)
        let delay: TimeInterval = (target != nil && target?.isActive != true) ? 0.12 : 0.05
        if let target, !target.isTerminated, target != NSRunningApplication.current {
            target.activate(options: [.activateAllWindows])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            EventSynthesizer.postCommandKey(KeyCode.v)
            Banner.show(
                "Pasted history",
                style: .success,
                symbol: "list.clipboard"
            )
        }
    }

    private static func capturePasteTarget() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            pasteTarget = front
        } else {
            pasteTarget = NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0 != NSRunningApplication.current
                    && $0.activationPolicy == .regular
            }
        }
    }

    /// Pinned-first entries, filtered by `filterBuffer`, capped to `maxRows`
    /// (keeps every visible row reachable by digit key 1–9).
    fileprivate static func displayedEntries() -> [ClipboardEntry] {
        let source = ClipboardService.shared.pinnedFirst
        let filtered = filterBuffer.isEmpty
            ? source
            : source.filter { $0.text.localizedCaseInsensitiveContains(filterBuffer) }
        return Array(filtered.prefix(maxRows))
    }

    /// Rebuild the panel content in place after a filter or pin change
    /// (keeps the same window so position/focus don't jump).
    fileprivate static func refresh() {
        guard let panel = window else { return }
        let items = displayedEntries()
        panel.contentView = buildContent(entries: items, filter: filterBuffer, width: panel.frame.width)
        let newHeight = contentHeight(rowCount: items.count)
        guard abs(newHeight - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        let delta = newHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
    }

    /// Show the panel without making HyperForge the front app.
    private static func orderPanelFront() {
        guard let panel = window else { return }
        panel.orderFrontRegardless()
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

    /// keyCode → row index (top-row digits 1–9, matches `maxRows`).
    private static let digitRowMap: [UInt16: Int] = [
        KeyCode.one: 0, KeyCode.two: 1, KeyCode.three: 2, KeyCode.four: 3, KeyCode.five: 4,
        KeyCode.six: 5, KeyCode.seven: 6, KeyCode.eight: 7, KeyCode.nine: 8,
    ]

    @discardableResult
    private static func handleKey(_ event: NSEvent, swallow: Bool) -> NSEvent? {
        let chars = event.charactersIgnoringModifiers ?? ""
        let consumed = handleEngineKey(
            keyCode: event.keyCode,
            flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
            characters: chars
        )
        if consumed { return swallow ? nil : event }
        return event
    }

    @discardableResult
    private static func handleEngineKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        characters: String
    ) -> Bool {
        guard isShowing else { return false }
        if keyCode == KeyCode.escape {
            hide()
            return true
        }
        if keyCode == KeyCode.delete {
            if !filterBuffer.isEmpty {
                filterBuffer.removeLast()
                refresh()
            }
            return true
        }
        if keyCode == KeyCode.return {
            if let first = displayedEntries().first {
                restorePasteTargetThenPaste(first)
            }
            return true
        }
        if let idx = digitRowMap[keyCode] {
            let list = displayedEntries()
            // Once a filter is active, digits are search text, not paste shortcuts
            // (⌥+digit still pins, since Option unambiguously signals intent).
            if flags.contains(.maskAlternate) {
                if list.indices.contains(idx) {
                    ClipboardService.shared.togglePin(list[idx].id)
                    refresh()
                }
                return true
            }
            if filterBuffer.isEmpty {
                if list.indices.contains(idx) {
                    restorePasteTargetThenPaste(list[idx])
                }
                return true
            }
            // Fall through: treat the digit as filter text below.
        }
        if !flags.contains(.maskCommand),
           let ch = characters.first,
           let ascii = ch.asciiValue, ascii >= 32, ascii < 127
        {
            filterBuffer.append(ch)
            refresh()
            return true
        }
        return false
    }

    private static func contentHeight(rowCount: Int) -> CGFloat {
        let rowH: CGFloat = 36
        let headerH: CGFloat = 76
        let footerH: CGFloat = 44
        let n = max(1, rowCount)
        return headerH + CGFloat(n) * rowH + footerH
    }

    private static func makePanel(entries: [ClipboardEntry], filter: String) -> NSPanel {
        let width: CGFloat = 460
        let height = contentHeight(rowCount: entries.count)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .closable],
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
        panel.contentView = buildContent(entries: entries, filter: filter, width: width)
        return panel
    }

    private static func buildContent(entries: [ClipboardEntry], filter: String, width: CGFloat) -> NSView {
        let rowH: CGFloat = 36
        let headerH: CGFloat = 76
        let footerH: CGFloat = 44
        let height = contentHeight(rowCount: entries.count)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = NSTextField(labelWithString: "Clipboard history")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 16, y: height - 42, width: width - 40, height: 24)
        content.addSubview(title)

        let filterLabel = NSTextField(labelWithString: filter.isEmpty ? "Type to filter…" : filter)
        filterLabel.font = .systemFont(ofSize: 12, weight: .regular)
        filterLabel.textColor = filter.isEmpty ? .tertiaryLabelColor : .labelColor
        filterLabel.frame = NSRect(x: 16, y: height - 66, width: width - 40, height: 18)
        content.addSubview(filterLabel)

        if entries.isEmpty {
            let message = filter.isEmpty
                ? """
                Nothing saved yet.

                1. Copy any text (⌘C)
                2. Hold Caps (Hyper) and press V
                3. Release Caps — this window opens

                Esc closes anytime.
                """
                : "No matches for “\(filter)”."
            let empty = NSTextField(wrappingLabelWithString: message)
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 20, y: footerH, width: width - 40, height: height - headerH - footerH)
            content.addSubview(empty)
        } else {
            let pinW: CGFloat = 26
            let spacing: CGFloat = 6
            let mainBtnX: CGFloat = 12
            let mainBtnW = width - 24 - pinW - spacing
            for (i, entry) in entries.enumerated() {
                let y = height - headerH - CGFloat(i + 1) * rowH + 4

                let btn = NSButton(frame: NSRect(x: mainBtnX, y: y, width: mainBtnW, height: rowH - 6))
                btn.bezelStyle = .rounded
                btn.title = "\(i + 1).  \(preview(entry.text))"
                btn.alignment = .left
                btn.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                btn.tag = i
                btn.target = PanelTarget.shared
                btn.action = #selector(PanelTarget.paste(_:))
                btn.toolTip = entry.text
                content.addSubview(btn)

                let pinBtn = NSButton(
                    frame: NSRect(x: mainBtnX + mainBtnW + spacing, y: y, width: pinW, height: rowH - 6)
                )
                pinBtn.bezelStyle = .rounded
                pinBtn.image = NSImage(
                    systemSymbolName: entry.pinned ? "pin.fill" : "pin",
                    accessibilityDescription: entry.pinned ? "Unpin" : "Pin"
                )
                pinBtn.imagePosition = .imageOnly
                pinBtn.tag = i
                pinBtn.target = PanelTarget.shared
                pinBtn.action = #selector(PanelTarget.togglePin(_:))
                pinBtn.toolTip = (entry.pinned ? "Unpin" : "Pin") + " (⌥+\(i + 1))"
                content.addSubview(pinBtn)
            }
        }

        let hint = NSTextField(
            labelWithString: "Esc close  ·  1–9 paste  ·  ⌥+1–9 pin  ·  type to filter"
        )
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 16, y: 14, width: width - 32, height: 18)
        content.addSubview(hint)

        return content
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
        let list = ClipboardHistoryPanel.displayedEntries()
        guard list.indices.contains(sender.tag) else { return }
        ClipboardHistoryPanel.restorePasteTargetThenPaste(list[sender.tag])
    }

    @objc func togglePin(_ sender: NSButton) {
        let list = ClipboardHistoryPanel.displayedEntries()
        guard list.indices.contains(sender.tag) else { return }
        ClipboardService.shared.togglePin(list[sender.tag].id)
        ClipboardHistoryPanel.refresh()
    }
}
