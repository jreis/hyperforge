// HyperBindingsHUD.swift
// Live binding overlay while Hyper is physically held (HyperKey.spoon-style).
// Compact key map — not a full cheat sheet.

import AppKit
import Foundation

enum HyperBindingsHUD {
    @MainActor private static var window: NSWindow?
    @MainActor private static var visible = false
    @MainActor private static var showWorkItem: DispatchWorkItem?

    /// Slight delay so quick Hyper taps don’t flash the overlay.
    private static let showDelay: TimeInterval = 0.28

    @MainActor
    static func setHyperHeld(_ held: Bool) {
        let enabled = UserDefaults.standard.object(forKey: "hf.showHyperBindingsHUD") as? Bool ?? true
        guard enabled else {
            cancelPending()
            hide()
            return
        }
        if held {
            scheduleShow()
        } else {
            cancelPending()
            hide()
        }
    }

    @MainActor
    private static func scheduleShow() {
        cancelPending()
        let work = DispatchWorkItem {
            show()
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    @MainActor
    private static func cancelPending() {
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    @MainActor
    static func show() {
        if visible, window != nil {
            reposition()
            return
        }
        visible = true

        let screen =
            NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let infernal =
            (UserDefaults.standard.string(forKey: AppearanceKeys.style) ?? "forge") == "infernal"
        let accent: NSColor = infernal
            ? NSColor(calibratedRed: 0.88, green: 0.024, blue: 0.0, alpha: 1)
            : NSColor(calibratedRed: 0.42, green: 0.62, blue: 1.0, alpha: 1)
        let textColor: NSColor = infernal
            ? NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.89, alpha: 1)
            : .white
        let muted = textColor.withAlphaComponent(0.55)

        let rows: [(String, String)] = [
            ("←↑↓→ · Num", "Snap halves / pad"),
            ("- = \\", "Thirds · ⇧ for ⅔ / almost"),
            ("[ ] · M", "Prev / next display"),
            ("6 · Z · C", "Tile · undo · center"),
            ("O · ⇧V · P", "OCR · history · pin"),
            ("W · A · B", "Warp · pin · min"),
            ("/ · ` · ,", "Help · sheet · dash"),
        ]

        let rowH: CGFloat = 18
        let pad: CGFloat = 14
        let titleH: CGFloat = 22
        let width: CGFloat = 268
        let height = pad * 2 + titleH + 8 + CGFloat(rows.count) * rowH + 4

        let x = screen.visibleFrame.maxX - width - 16
        let y = screen.visibleFrame.maxY - height - 16

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        win.alphaValue = 0

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        visual.layer?.borderWidth = 1
        visual.layer?.borderColor = accent.withAlphaComponent(0.5).cgColor

        let title = NSTextField(labelWithString: infernal ? "HYPER · FORGE" : "HYPER")
        title.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        title.textColor = accent
        title.frame = NSRect(x: pad, y: height - pad - titleH + 4, width: width - pad * 2, height: titleH)
        visual.addSubview(title)

        var yPos = height - pad - titleH - 6
        for (keys, action) in rows {
            yPos -= rowH
            let keyField = NSTextField(labelWithString: keys)
            keyField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            keyField.textColor = textColor
            keyField.frame = NSRect(x: pad, y: yPos, width: 108, height: rowH)
            visual.addSubview(keyField)

            let actField = NSTextField(labelWithString: action)
            actField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            actField.textColor = muted
            actField.frame = NSRect(x: pad + 110, y: yPos, width: width - pad * 2 - 110, height: rowH)
            visual.addSubview(actField)
        }

        win.contentView = visual
        win.orderFront(nil)
        window = win

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
    }

    @MainActor
    static func hide() {
        guard visible || window != nil else { return }
        visible = false
        guard let win = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        } completionHandler: {
            win.close()
        }
    }

    @MainActor
    private static func reposition() {
        guard let win = window else { return }
        let screen =
            NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let f = win.frame
        let x = screen.visibleFrame.maxX - f.width - 16
        let y = screen.visibleFrame.maxY - f.height - 16
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
