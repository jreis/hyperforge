// RegionPinService.swift
// Drag a screen region → capture → stay-on-top floating pin (Snipaste-style).
// Hyper + P starts selection; Esc cancels.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class RegionPinService {
    static let shared = RegionPinService()

    private var selection: RegionSelectionSession?
    private var pins: [FloatingImagePin] = []

    private init() {
        refreshEscapeHandlers()
    }

    /// Begin interactive region selection across all displays.
    func beginSelection() {
        cancelSelection()

        // Hide dashboard quietly so it isn't under the dim overlay.
        for w in AppState.dashboardWindows() { w.orderOut(nil) }

        Banner.show(
            "Pin region",
            subtitle: "Drag to select · Esc cancels",
            style: .info,
            symbol: "crop"
        )

        let session = RegionSelectionSession { [weak self] result in
            self?.selection = nil
            self?.refreshEscapeHandlers()
            switch result {
            case .cancelled:
                Banner.show(
                    "Pin cancelled",
                    subtitle: "No capture",
                    style: .neutral,
                    symbol: "crop"
                )
            case .captured(let image, let globalRect):
                self?.presentPin(image: image, near: globalRect)
            case .failed(let message):
                Banner.show(
                    "Capture failed",
                    subtitle: message,
                    style: .warning,
                    symbol: "crop"
                )
            }
        }
        selection = session
        refreshEscapeHandlers()
        session.start()
    }

    func cancelSelection() {
        selection?.cancel()
        selection = nil
        refreshEscapeHandlers()
    }

    /// Close the most recently created pin (Esc priority).
    @discardableResult
    func closeTopPin() -> Bool {
        guard let pin = pins.last else { return false }
        pin.close()
        return true
    }

    var hasPins: Bool { !pins.isEmpty }
    var isSelecting: Bool { selection != nil }

    private func presentPin(image: NSImage, near rect: NSRect) {
        let pin = FloatingImagePin(image: image, preferredOrigin: rect.origin) { [weak self] pin in
            self?.pins.removeAll { $0 === pin }
            self?.refreshEscapeHandlers()
        }
        pins.append(pin)
        pin.show()
        refreshEscapeHandlers()
        Banner.show(
            "Region pinned",
            subtitle: "⌘C or right-click → Copy · Esc closes",
            style: .success,
            symbol: "pin.fill"
        )
    }

    /// Copy the topmost region pin image to the pasteboard (if any).
    @discardableResult
    func copyTopPinToClipboard() -> Bool {
        guard let pin = pins.last else { return false }
        return pin.copyImageToClipboard()
    }

    /// Keep Esc stack in sync when selection / pins change.
    func refreshEscapeHandlers() {
        EscapeCoordinator.shared.setHandler(.regionSelection) { [weak self] in
            guard let self, self.isSelecting else { return false }
            self.cancelSelection()
            return true
        }
        EscapeCoordinator.shared.setHandler(.floatingPin) { [weak self] in
            // Newest region pin first, then clipboard image pin.
            if self?.closeTopPin() == true { return true }
            if ClipboardImagePreview.shared.isShowing {
                ClipboardImagePreview.shared.close()
                return true
            }
            return false
        }
    }
}

// MARK: - Selection session

private enum RegionSelectionResult {
    case cancelled
    case captured(NSImage, NSRect)
    case failed(String)
}

@MainActor
private final class RegionSelectionSession {
    private let completion: (RegionSelectionResult) -> Void
    private var overlays: [RegionOverlayWindow] = []
    private var finished = false

    init(completion: @escaping (RegionSelectionResult) -> Void) {
        self.completion = completion
    }

    func start() {
        // Keep accessory policy if possible — avoid full activation flash.
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let overlay = RegionOverlayWindow(screen: screen) { [weak self] rectInScreen in
                self?.finish(withScreenRect: rectInScreen, on: screen)
            } onCancel: { [weak self] in
                self?.finishCancelled()
            }
            overlays.append(overlay)
            overlay.start()
        }
    }

    func cancel() {
        finishCancelled()
    }

    private func finishCancelled() {
        guard !finished else { return }
        finished = true
        teardownOverlays()
        completion(.cancelled)
    }

    private func finish(withScreenRect rect: NSRect, on screen: NSScreen) {
        guard !finished else { return }
        finished = true
        teardownOverlays()

        // Ignore tiny drags (clicks)
        guard rect.width >= 8, rect.height >= 8 else {
            completion(.cancelled)
            return
        }

        // Global AppKit coordinates (bottom-left origin).
        let global = NSRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )

        Task {
            // Critical: wait until dim overlays are gone from the display buffer.
            // Capturing immediately often grabs pure black overlay frames.
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
            await MainActor.run {
                // Extra run-loop turn so orderOut is committed.
            }
            try? await Task.sleep(nanoseconds: 40_000_000)

            do {
                let image = try await Self.capture(globalAppKitRect: global, screen: screen)
                await MainActor.run {
                    self.completion(.captured(image, global))
                }
            } catch {
                await MainActor.run {
                    self.completion(.failed(error.localizedDescription))
                }
            }
        }
    }

    private func teardownOverlays() {
        let current = overlays
        overlays = []
        for o in current { o.teardown() }
        // Force a display refresh so capture won't see black panels.
        for screen in NSScreen.screens {
            // Touching the display is a no-op; orderOut above is the real fix.
            _ = screen.frame
        }
    }

    /// Capture a global AppKit rect (bottom-left) on `screen` at native retina resolution.
    private static func capture(globalAppKitRect: NSRect, screen: NSScreen) async throws -> NSImage {
        // Prefer full-display retina capture + crop (sharp). `sourceRect` paths often resample.
        if let img = try? await captureWithScreenCaptureKit(
            globalAppKitRect: globalAppKitRect,
            screen: screen
        ) {
            return img
        }
        return try captureWithScreencaptureCLI(
            globalAppKitRect: globalAppKitRect,
            pointSize: globalAppKitRect.size
        )
    }

    private static func captureWithScreenCaptureKit(
        globalAppKitRect: NSRect,
        screen: NSScreen
    ) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let displayID =
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let display =
            content.displays.first(where: { displayID != nil && $0.displayID == displayID })
            ?? content.displays.first

        guard let display else {
            throw NSError(
                domain: "RegionPin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display for capture"]
            )
        }

        let scale = screen.backingScaleFactor
        // Capture the *entire* display at native pixel density, then crop.
        // Partial sourceRect + mismatched width/height is a common blur source.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        config.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.scalesToFit = false

        let full = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let local = NSRect(
            x: globalAppKitRect.origin.x - screen.frame.origin.x,
            y: globalAppKitRect.origin.y - screen.frame.origin.y,
            width: globalAppKitRect.width,
            height: globalAppKitRect.height
        ).integral

        // AppKit bottom-left → CGImage top-left (pixels)
        let pixelScaleX = CGFloat(full.width) / screen.frame.width
        let pixelScaleY = CGFloat(full.height) / screen.frame.height
        let topLeftY = screen.frame.height - local.origin.y - local.height
        var crop = CGRect(
            x: local.origin.x * pixelScaleX,
            y: topLeftY * pixelScaleY,
            width: local.width * pixelScaleX,
            height: local.height * pixelScaleY
        ).integral
        crop = crop.intersection(
            CGRect(x: 0, y: 0, width: full.width, height: full.height)
        )
        guard crop.width >= 1, crop.height >= 1,
              let cropped = full.cropping(to: crop)
        else {
            throw NSError(
                domain: "RegionPin",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Crop failed"]
            )
        }

        // Point size = selection size; pixel buffer stays retina density → sharp.
        return nsImage(from: cropped, pointSize: local.size)
    }

    /// Build NSImage with correct point size + pixel dimensions (retina-aware).
    private static func nsImage(from cgImage: CGImage, pointSize: NSSize) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize  // points; pixelsWide/High stay at native capture res
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }

    /// `screencapture -R x,y,w,h` uses top-left global coordinates (retina PNG).
    private static func captureWithScreencaptureCLI(
        globalAppKitRect: NSRect,
        pointSize: NSSize
    ) throws -> NSImage {
        let primaryH = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let x = Int(globalAppKitRect.origin.x.rounded())
        let y = Int((primaryH - globalAppKitRect.origin.y - globalAppKitRect.height).rounded())
        let w = max(1, Int(globalAppKitRect.width.rounded()))
        let h = max(1, Int(globalAppKitRect.height.rounded()))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyperforge-pin-\(UUID().uuidString).png")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x silent, -r no shadow; region is captured at display pixel density
        proc.arguments = ["-x", "-R", "\(x),\(y),\(w),\(h)", url.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let cgImageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil)
        else {
            throw NSError(
                domain: "RegionPin",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "screencapture failed"]
            )
        }
        try? FileManager.default.removeItem(at: url)
        return nsImage(from: cgImage, pointSize: pointSize)
    }
}

// MARK: - Overlay window (per screen)

@MainActor
private final class RegionOverlayWindow: NSObject {
    private let screen: NSScreen
    private let onComplete: (NSRect) -> Void
    private let onCancel: () -> Void
    private var window: NSWindow?
    private var dimView: SelectionDimView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var dragStart: NSPoint?
    private var finished = false

    init(
        screen: NSScreen,
        onComplete: @escaping (NSRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func start() {
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.isReleasedWhenClosed = false
        // Avoid .screenSaver — can blank the display on some setups.
        win.level = .popUpMenu
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.ignoresMouseEvents = false
        win.hasShadow = false
        win.alphaValue = 1
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        win.acceptsMouseMovedEvents = true
        // Sharing-type window so captures can exclude UI chrome more reliably.
        win.sharingType = .none

        let dim = SelectionDimView(frame: NSRect(origin: .zero, size: screen.frame.size))
        dim.autoresizingMask = [.width, .height]
        win.contentView = dim
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless()

        window = win
        dimView = dim

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .rightMouseDown,
        ]) { [weak self] event in
            guard let self else { return event }
            if self.handle(event) {
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown,
        ]) { [weak self] event in
            Task { @MainActor in _ = self?.handle(event) }
        }
    }

    func teardown() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let win = window {
            win.alphaValue = 0
            win.orderOut(nil)
            win.setIsVisible(false)
            win.contentView = nil
        }
        window = nil
        dimView = nil
    }

    /// Returns true if the event was consumed.
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard !finished, let win = window else { return false }

        if event.type == .keyDown, event.keyCode == KeyCode.escape {
            finishCancel()
            return true
        }

        let global = NSEvent.mouseLocation
        // Only mouse work on the screen under the cursor (multi-monitor).
        guard screen.frame.contains(global) else { return false }

        let local = win.mouseLocationOutsideOfEventStream

        switch event.type {
        case .rightMouseDown:
            finishCancel()
            return true
        case .leftMouseDown:
            dragStart = local
            dimView?.selection = NSRect(origin: local, size: .zero)
            dimView?.needsDisplay = true
            return true
        case .leftMouseDragged:
            guard let start = dragStart else { return false }
            dimView?.selection = NSRect(
                x: min(start.x, local.x),
                y: min(start.y, local.y),
                width: abs(local.x - start.x),
                height: abs(local.y - start.y)
            )
            dimView?.needsDisplay = true
            return true
        case .leftMouseUp:
            guard let start = dragStart else { return false }
            let rect = NSRect(
                x: min(start.x, local.x),
                y: min(start.y, local.y),
                width: abs(local.x - start.x),
                height: abs(local.y - start.y)
            )
            dragStart = nil
            finish(rect)
            return true
        default:
            return false
        }
    }

    private func finish(_ rect: NSRect) {
        guard !finished else { return }
        finished = true
        teardown()
        onComplete(rect)
    }

    private func finishCancel() {
        guard !finished else { return }
        finished = true
        teardown()
        onCancel()
    }
}

/// Light dim + selection hole. Must stay translucent (never opaque black).
private final class SelectionDimView: NSView {
    var selection: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Light scrim so the desktop stays visible (was too dark / looked “broken”).
        let scrim = NSColor.black.withAlphaComponent(0.28)

        guard selection.width > 1, selection.height > 1 else {
            scrim.setFill()
            bounds.fill()
            let msg = "Drag to pin a region  ·  Esc cancels" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let size = msg.size(withAttributes: attrs)
            msg.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attrs
            )
            return
        }

        let hole = selection.integral
        let path = NSBezierPath(rect: bounds)
        path.appendRect(hole)
        path.windingRule = .evenOdd
        scrim.setFill()
        path.fill()

        let border = NSBezierPath(rect: hole.insetBy(dx: 0.5, dy: 0.5))
        NSColor.systemOrange.setStroke()
        border.lineWidth = 2
        border.stroke()

        let label = "\(Int(hole.width)) × \(Int(hole.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.92),
        ]
        let size = label.size(withAttributes: attrs)
        let lp = NSPoint(
            x: hole.minX,
            y: min(hole.maxY + 4, bounds.maxY - size.height - 4)
        )
        label.draw(at: lp, withAttributes: attrs)
    }

    override var isFlipped: Bool { false }
}

// MARK: - Floating pin window

@MainActor
final class FloatingImagePin {
    private var window: NSWindow?
    private var dragOrigin: NSPoint?
    private var windowOriginAtDrag: NSPoint?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let onClose: (FloatingImagePin) -> Void
    private let image: NSImage
    private let preferredOrigin: NSPoint?
    private let menuTarget = PinMenuTarget()

    init(
        image: NSImage,
        preferredOrigin: NSPoint? = nil,
        onClose: @escaping (FloatingImagePin) -> Void
    ) {
        self.image = image
        self.preferredOrigin = preferredOrigin
        self.onClose = onClose
        menuTarget.pin = self
    }

    func show() {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        // Prefer 1:1 point mapping (native retina density). Only shrink if larger than screen.
        let hostScreen: NSScreen = {
            if let o = preferredOrigin {
                return NSScreen.screens.first(where: { $0.frame.contains(o) })
                    ?? NSScreen.main
                    ?? NSScreen.screens[0]
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }()

        let maxW = hostScreen.visibleFrame.width * 0.95
        let maxH = hostScreen.visibleFrame.height * 0.95
        let fit = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        // Whole points — fractional frames cause soft compositing on retina.
        let w = max(80, (imgSize.width * fit).rounded(.down))
        let h = max(60, (imgSize.height * fit).rounded(.down))

        var origin: NSPoint
        if let preferredOrigin {
            origin = preferredOrigin
            let vf = hostScreen.visibleFrame
            origin.x = min(max(origin.x, vf.minX), vf.maxX - w)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - h)
        } else {
            origin = NSPoint(
                x: hostScreen.visibleFrame.midX - w / 2,
                y: hostScreen.visibleFrame.midY - h / 2
            )
        }

        let win = NSWindow(
            contentRect: NSRect(x: origin.x, y: origin.y, width: w, height: h),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = true
        win.minSize = NSSize(width: 80, height: 60)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isMovableByWindowBackground = false
        win.acceptsMouseMovedEvents = true

        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        iv.image = image
        // 1:1 points when possible; proportional only if we had to shrink to fit.
        iv.imageScaling = fit < 0.999 ? .scaleProportionallyUpOrDown : .scaleNone
        iv.imageAlignment = .alignCenter
        iv.autoresizingMask = [.width, .height]
        iv.wantsLayer = true
        iv.layer?.contentsScale = hostScreen.backingScaleFactor
        iv.layer?.minificationFilter = .trilinear
        iv.layer?.magnificationFilter = .nearest
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.layer?.borderWidth = 2
        iv.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.95).cgColor
        iv.toolTip = "⌘C or right-click → Copy · Esc / menu → Close"

        win.contentView = iv
        win.makeKeyAndOrderFront(nil)
        window = win

        // Esc is handled by EscapeCoordinator (floatingPin layer).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseUp, .keyDown,
        ]) { [weak self] event in
            self?.handlePinEvent(event) ?? event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDragged, .leftMouseUp,
        ]) { [weak self] event in
            Task { @MainActor in _ = self?.handlePinEvent(event) }
        }
    }

    /// Write the pin’s image to the general pasteboard (PNG + TIFF).
    @discardableResult
    func copyImageToClipboard() -> Bool {
        guard let tiff = image.tiffRepresentation else {
            Banner.show("Copy failed", style: .warning, symbol: "doc.on.clipboard")
            return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        var wrote = false
        if let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:])
        {
            pb.setData(png, forType: .png)
            wrote = true
        }
        pb.setData(tiff, forType: .tiff)
        wrote = true
        // Also offer as file promise–friendly raw image object for some apps
        _ = pb.writeObjects([image])
        if wrote {
            Banner.show(
                "Copied pin",
                subtitle: "Image on clipboard",
                style: .success,
                symbol: "doc.on.clipboard"
            )
            HyperLog.event("Region pin copied to clipboard")
        }
        return wrote
    }

    @discardableResult
    private func handlePinEvent(_ event: NSEvent) -> NSEvent? {
        guard let win = window else { return event }
        let pt = NSEvent.mouseLocation
        let frame = win.frame

        switch event.type {
        case .leftMouseDown:
            if frame.contains(pt) {
                dragOrigin = pt
                windowOriginAtDrag = frame.origin
                win.makeKeyAndOrderFront(nil)
                return nil
            }
        case .leftMouseDragged:
            if let o = dragOrigin, let wo = windowOriginAtDrag {
                win.setFrameOrigin(
                    NSPoint(x: wo.x + (pt.x - o.x), y: wo.y + (pt.y - o.y))
                )
                return nil
            }
        case .leftMouseUp:
            dragOrigin = nil
            windowOriginAtDrag = nil
        case .rightMouseUp:
            if frame.contains(pt) {
                win.makeKeyAndOrderFront(nil)
                showContextMenu(at: pt)
                return nil
            }
        case .keyDown:
            // ⌘C copies when this pin is key (or mouse is over it)
            let overPin = frame.contains(pt)
            let isKey = win.isKeyWindow
            if (overPin || isKey),
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c"
            {
                _ = copyImageToClipboard()
                return nil
            }
        default:
            break
        }
        return event
    }

    private func showContextMenu(at screenPoint: NSPoint) {
        let menu = NSMenu(title: "Pin")
        let copyItem = NSMenuItem(
            title: "Copy Image",
            action: #selector(PinMenuTarget.copyImage(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = menuTarget
        menu.addItem(copyItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(
            title: "Close Pin",
            action: #selector(PinMenuTarget.closePin(_:)),
            keyEquivalent: ""
        )
        closeItem.target = menuTarget
        menu.addItem(closeItem)
        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        onClose(self)
    }
}

/// NSMenu needs an NSObject target.
@MainActor
private final class PinMenuTarget: NSObject {
    weak var pin: FloatingImagePin?

    @objc func copyImage(_ sender: Any?) {
        _ = pin?.copyImageToClipboard()
    }

    @objc func closePin(_ sender: Any?) {
        pin?.close()
    }
}
