// ClipboardImagePreview.swift
// Manual floating preview of the pasteboard image (Hyper+⇧P / Quick Menu).
// Does not poll — region pin (Hyper+P) covers intentional on-screen capture.

import AppKit
import Foundation

@MainActor
final class ClipboardImagePreview {
    static let shared = ClipboardImagePreview()

    private var window: NSWindow?
    private var imageView: NSImageView?
    private var dragOrigin: NSPoint?
    private var windowOriginAtDrag: NSPoint?
    private var localMonitor: Any?
    private var lastImageSignature: String?
    private var lastShownChangeCount: Int

    /// Whether a clipboard image pin is currently visible (Esc stack).
    var isShowing: Bool { window != nil }

    private init() {
        lastShownChangeCount = NSPasteboard.general.changeCount
        lastImageSignature = Self.imageSignature()
    }

    private static func imageSignature() -> String? {
        guard
            let data = NSPasteboard.general.data(forType: .png)
                ?? NSPasteboard.general.data(forType: .tiff)
        else { return nil }
        let prefix = data.prefix(64)
        let suffix = data.suffix(64)
        return "\(data.count):\(prefix.base64EncodedString()):\(suffix.base64EncodedString())"
    }

    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        imageView = nil
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        lastShownChangeCount = NSPasteboard.general.changeCount
        RegionPinService.shared.refreshEscapeHandlers()
    }

    func show(image: NSImage) {
        close()

        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let maxW = sf.width * 0.8
        let maxH = sf.height * 0.8
        let scale = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        let x = sf.origin.x + (sf.width - w) / 2
        let y = sf.origin.y + (sf.height - h) / 2

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        win.contentView = iv
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.borderColor =
            NSColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1.0).cgColor
        win.contentView?.layer?.borderWidth = 2.0
        win.contentView?.layer?.cornerRadius = 8

        win.orderFront(nil)
        window = win
        imageView = iv
        RegionPinService.shared.refreshEscapeHandlers()

        // Esc → EscapeCoordinator (.floatingPin). Mouse drag / right-click local.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseUp,
        ]) { [weak self] event in
            guard let self, let win = self.window else { return event }
            let screenPoint = NSEvent.mouseLocation
            let winFrame = win.frame
            switch event.type {
            case .leftMouseDown:
                if winFrame.contains(screenPoint) {
                    self.dragOrigin = screenPoint
                    self.windowOriginAtDrag = winFrame.origin
                    return nil
                }
            case .leftMouseDragged:
                if let origin = self.dragOrigin, let winOrigin = self.windowOriginAtDrag {
                    let dx = screenPoint.x - origin.x
                    let dy = screenPoint.y - origin.y
                    win.setFrameOrigin(NSPoint(x: winOrigin.x + dx, y: winOrigin.y + dy))
                    return nil
                }
            case .leftMouseUp:
                self.dragOrigin = nil
                self.windowOriginAtDrag = nil
            case .rightMouseUp:
                if winFrame.contains(screenPoint) {
                    self.close()
                    return nil
                }
            default: break
            }
            return event
        }
    }

    func showManual() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            Banner.show(
                "No image in clipboard",
                subtitle: "Copy a screenshot first · or Hyper+P to pin a region",
                style: .warning,
                symbol: "photo"
            )
            return
        }
        show(image: image)
        lastImageSignature = Self.imageSignature()
        lastShownChangeCount = NSPasteboard.general.changeCount
        Banner.show(
            "Clipboard image",
            subtitle: "Drag to move · Esc closes",
            style: .success,
            symbol: "photo"
        )
    }
}
