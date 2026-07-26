// SpaceLayerHUD.swift
// Sticky glass pill while the Space navigation layer is armed.
// Separate from Banner (ephemeral toasts) so NAV state never steals action feedback.

import AppKit
import Foundation

enum SpaceLayerHUD {
    @MainActor private static var window: NSWindow?
    @MainActor private static var visible = false

    /// Show or hide the armed indicator. Safe to call frequently (edge-deduped).
    @MainActor
    static func setArmed(_ armed: Bool) {
        if armed {
            show()
        } else {
            hide()
        }
    }

    @MainActor
    static func show() {
        if visible, window != nil {
            // Keep on the active screen if the user moved.
            reposition()
            return
        }
        visible = true

        let screen =
            NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let width: CGFloat = 108
        let height: CGFloat = 36
        let x = screen.frame.midX - width / 2
        // Near the top of the visible frame — out of the way of most editors.
        let y = screen.visibleFrame.maxY - height - 12

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
        visual.layer?.cornerRadius = height / 2
        visual.layer?.masksToBounds = true
        let infernal =
            (UserDefaults.standard.string(forKey: AppearanceKeys.style) ?? "forge") == "infernal"
        let accent: NSColor = infernal
            ? NSColor(calibratedRed: 0.88, green: 0.024, blue: 0.0, alpha: 1)
            : NSColor(calibratedRed: 0.42, green: 0.62, blue: 1.0, alpha: 1)

        visual.layer?.borderWidth = 1
        visual.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let icon = NSImageView(
            frame: NSRect(x: 12, y: (height - 18) / 2, width: 18, height: 18)
        )
        icon.image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "Space nav"
        )?.withSymbolConfiguration(iconConfig)
        icon.contentTintColor = accent
        icon.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: infernal ? "VOID" : "NAV")
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = infernal
            ? NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.89, alpha: 1)
            : .white
        label.frame = NSRect(x: 34, y: 0, width: width - 42, height: height)
        label.alignment = .left

        visual.addSubview(icon)
        visual.addSubview(label)
        win.contentView = visual
        win.orderFront(nil)
        window = win

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
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
            ctx.duration = 0.14
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
        let x = screen.frame.midX - f.width / 2
        let y = screen.visibleFrame.maxY - f.height - 12
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
