// Banner.swift
// Compact HUD toast — macOS-native glass, not a chunky dialog.

import AppKit
import Foundation

enum BannerStyle {
    case neutral
    case success
    case warning
    case danger
    case info

    var accent: NSColor {
        switch self {
        case .neutral: return NSColor.white.withAlphaComponent(0.85)
        case .success: return NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        case .warning: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 1)
        case .danger: return NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1)
        case .info: return NSColor(calibratedRed: 0.42, green: 0.62, blue: 1.0, alpha: 1)
        }
    }

    var defaultSymbol: String {
        switch self {
        case .neutral: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.circle.fill"
        case .info: return "bolt.circle.fill"
        }
    }
}

enum Banner {
    /// Simple one-line toast (back-compat) — still uses the same glass pill HUD.
    static func show(_ message: String, duration: TimeInterval = 2.0) {
        show(message, subtitle: nil, style: .neutral, symbol: nil, duration: duration, screen: nil)
    }

    /// Rich HUD: title + optional subtitle, tinted status, SF Symbol.
    /// - Parameter screen: Host display for the toast (defaults to main / key window’s screen).
    static func show(
        _ title: String,
        subtitle: String? = nil,
        style: BannerStyle = .neutral,
        symbol: String? = nil,
        duration: TimeInterval = 2.2,
        screen: NSScreen? = nil
    ) {
        DispatchQueue.main.async {
            Self.showOnMain(
                title: title,
                subtitle: subtitle,
                style: style,
                symbol: symbol ?? style.defaultSymbol,
                duration: duration,
                screen: screen
            )
        }
    }

    // Keep a single live toast so rapid toggles don't stack.
    @MainActor private static var currentWindow: NSWindow?
    @MainActor private static var dismissWork: DispatchWorkItem?

    @MainActor
    private static func showOnMain(
        title: String,
        subtitle: String?,
        style: BannerStyle,
        symbol: String,
        duration: TimeInterval,
        screen preferredScreen: NSScreen?
    ) {
        dismissWork?.cancel()
        currentWindow?.close()
        currentWindow = nil

        let screen =
            preferredScreen
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let hasSubtitle = !(subtitle?.isEmpty ?? true)
        let height: CGFloat = hasSubtitle ? 56 : 44
        let maxWidth: CGFloat = 420
        let minWidth: CGFloat = 200
        let horizontalPad: CGFloat = 16
        let iconSize: CGFloat = 22
        let gap: CGFloat = 10

        // Measure text to size the HUD tightly.
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let subFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let subWidth = (subtitle as NSString?)?.size(withAttributes: [.font: subFont]).width ?? 0
        let textWidth = max(titleWidth, subWidth)
        let contentWidth = iconSize + gap + textWidth + horizontalPad * 2
        let width = min(maxWidth, max(minWidth, contentWidth + 8))

        let x = screen.frame.midX - width / 2
        // Slightly above the dock — bottom HUD on the *target* screen.
        let y = screen.visibleFrame.minY + 28

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.alphaValue = 0

        // Vibrancy host
        let visual = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: width, height: height)
        )
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = height / 2  // pill
        visual.layer?.masksToBounds = true
        visual.layer?.borderWidth = 1
        visual.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        // Soft accent glow edge
        let accentBar = NSView(
            frame: NSRect(x: 0, y: 0, width: 3, height: height)
        )
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = style.accent.cgColor
        // Clip accent into pill via parent mask; use circular dot instead for cleaner look
        accentBar.isHidden = true

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let iconImage = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(iconConfig)
        let iconView = NSImageView(
            frame: NSRect(
                x: horizontalPad,
                y: (height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
        )
        iconView.image = iconImage
        iconView.contentTintColor = style.accent
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let textX = horizontalPad + iconSize + gap
        let textW = width - textX - horizontalPad

        let titleField = NSTextField(labelWithString: title)
        titleField.font = titleFont
        titleField.textColor = .white
        titleField.alignment = .left
        titleField.lineBreakMode = .byTruncatingTail
        titleField.backgroundColor = .clear
        titleField.isBezeled = false

        if hasSubtitle, let subtitle {
            titleField.frame = NSRect(x: textX, y: height / 2 - 2, width: textW, height: 18)
            let subField = NSTextField(labelWithString: subtitle)
            subField.font = subFont
            subField.textColor = NSColor.white.withAlphaComponent(0.55)
            subField.alignment = .left
            subField.lineBreakMode = .byTruncatingTail
            subField.frame = NSRect(x: textX, y: 10, width: textW, height: 15)
            visual.addSubview(subField)
        } else {
            titleField.frame = NSRect(x: textX, y: 0, width: textW, height: height)
        }

        visual.addSubview(iconView)
        visual.addSubview(titleField)
        visual.addSubview(accentBar)

        window.contentView = visual
        window.orderFront(nil)
        currentWindow = window

        // Rise + fade in
        let startFrame = window.frame.offsetBy(dx: 0, dy: -10)
        window.setFrame(startFrame, display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(
                startFrame.offsetBy(dx: 0, dy: 10),
                display: true
            )
        }

        let work = DispatchWorkItem {
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                    window.animator().setFrame(
                        window.frame.offsetBy(dx: 0, dy: -8),
                        display: true
                    )
                } completionHandler: {
                    Task { @MainActor in
                        if currentWindow === window {
                            window.close()
                            currentWindow = nil
                        }
                    }
                }
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
