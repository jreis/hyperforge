// WindowManager.swift
// Accessibility-based window framing, snap, and undo.
// AX window geometry helpers — coordinate system is top-left origin for AX.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Last known frame per process for undo (single-window snaps).
    private var frameHistory: [pid_t: NSRect] = [:]
    /// Full layout snapshot taken before “tile all” so Hyper+Z can restore.
    private var preTileLayout: [WindowSnapshot] = []
    /// Prevent stacked tile jobs (each is expensive via Accessibility).
    private var isTiling = false

    /// Fail fast when an app’s AX server is hung (default can beach-ball for seconds).
    nonisolated private static let axTimeoutSeconds: Float = 0.22

    private init() {}

    /// True for this process / known HyperForge bundle IDs (skip tiling our own UI).
    nonisolated private static func isHyperForgeBundle(_ bid: String?) -> Bool {
        guard let bid, !bid.isEmpty else { return false }
        if bid == Bundle.main.bundleIdentifier { return true }
        return bid == "app.hyperforge.HyperForge"
    }

    func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow
        )
        guard result == .success else { return nil }
        return (focusedWindow as! AXUIElement)
    }

    func getFrame(_ window: AXUIElement) -> NSRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
                == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
                == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return NSRect(x: pos.x, y: pos.y, width: size.width, height: size.height)
    }

    func setFrame(_ window: AXUIElement, _ frame: NSRect) {
        Self.applyAXFrame(window, frame)
    }

    /// Shared AX resize (usable off the main actor).
    nonisolated private static func applyAXFrame(_ window: AXUIElement, _ frame: NSRect) {
        AXUIElementSetMessagingTimeout(window, axTimeoutSeconds)
        var pos = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size)
        else { return }
        // Size first often avoids intermediate constraint fights; keep both calls brief.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
    }

    nonisolated private static func configureAXTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, axTimeoutSeconds)
    }

    /// Visible frame in top-left AX coordinates.
    func screenFrame(for screen: NSScreen? = nil) -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let full = screen.frame
        return NSRect(
            x: visible.origin.x,
            y: full.height - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    func saveFrame() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let win = frontmostWindow(),
              let frame = getFrame(win)
        else { return }
        frameHistory[app.processIdentifier] = frame
    }

    /// Snap frontmost window using fractional screen units (0…1).
    func snap(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        guard let win = frontmostWindow() else { return }
        saveFrame()
        let sf = screenFrame()
        setFrame(
            win,
            NSRect(
                x: sf.origin.x + sf.width * x,
                y: sf.origin.y + sf.height * y,
                width: sf.width * w,
                height: sf.height * h
            )
        )
    }

    func center() {
        guard let win = frontmostWindow(), let frame = getFrame(win) else { return }
        let sf = screenFrame()
        saveFrame()
        setFrame(
            win,
            NSRect(
                x: sf.origin.x + (sf.width - frame.width) / 2,
                y: sf.origin.y + (sf.height - frame.height) / 2,
                width: frame.width,
                height: frame.height
            )
        )
    }

    func moveToNextScreen() {
        guard let win = frontmostWindow() else {
            Banner.show(
                "No front window",
                subtitle: "Focus a window first",
                style: .warning,
                symbol: "display"
            )
            return
        }
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            Banner.show(
                "Only one display",
                subtitle: "Connect another screen to move windows",
                style: .info,
                symbol: "display"
            )
            return
        }

        // Prefer the screen that currently contains the window (not always NSScreen.main).
        let currentFrame = getFrame(win)
        let current =
            screens.first(where: { screen in
                guard let f = currentFrame else { return false }
                return Self.framesIntersect(f, screenFrame(for: screen), margin: 20)
            })
            ?? NSScreen.main
            ?? screens[0]

        let idx = screens.firstIndex(of: current) ?? 0
        let next = screens[(idx + 1) % screens.count]
        let axDest = screenFrame(for: next)
        saveFrame()
        setFrame(
            win,
            NSRect(
                x: axDest.origin.x,
                y: axDest.origin.y,
                width: axDest.width,
                height: axDest.height
            )
        )

        let name = next.localizedName
        Banner.show(
            "Next display",
            subtitle: name.isEmpty ? "Moved window" : name,
            style: .success,
            symbol: "display.2",
            screen: next
        )
    }

    @discardableResult
    func undo() -> Bool {
        // Prefer restoring a full tile layout if one is pending.
        if !preTileLayout.isEmpty {
            let count = preTileLayout.count
            restoreLayout(preTileLayout)
            preTileLayout = []
            Banner.show(
                "Tile undone",
                subtitle: "Restored \(count) window\(count == 1 ? "" : "s")",
                style: .success,
                symbol: "arrow.uturn.backward"
            )
            return true
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let saved = frameHistory[app.processIdentifier],
              let win = frontmostWindow()
        else {
            Banner.show(
                "Nothing to undo",
                subtitle: "Snap or tile a window first",
                style: .warning,
                symbol: "arrow.uturn.backward"
            )
            return false
        }
        setFrame(win, saved)
        frameHistory.removeValue(forKey: app.processIdentifier)
        let name = app.localizedName ?? "Window"
        Banner.show(
            "Snap undone",
            subtitle: name,
            style: .success,
            symbol: "arrow.uturn.backward"
        )
        return true
    }

    // MARK: - Tile all visible windows

    private struct TileableWindow: @unchecked Sendable {
        let element: AXUIElement
        let pid: pid_t
        let bundleID: String
        let title: String
        let frame: NSRect
        /// Prefer AppKit for our own process (no AX round-trip).
        let useAppKit: Bool
    }

    private struct TilePlan: Sendable {
        let snapshots: [WindowSnapshot]
        let placements: [(TileableWindow, NSRect)]
        let cols: Int
        let rows: Int
    }

    /// Arrange visible windows into a grid. Heavy Accessibility work runs off the
    /// main actor so a hung app AX server cannot beach-ball the UI.
    @discardableResult
    func tileAllVisible(gap: CGFloat = 8) -> Int {
        guard !isTiling else {
            Banner.show(
                "Already tiling",
                subtitle: "Wait a moment…",
                style: .info,
                symbol: "hourglass"
            )
            return 0
        }
        let sf = screenFrame()
        guard sf.width > 0, sf.height > 0 else { return 0 }

        isTiling = true
        Banner.show(
            "Tiling…",
            subtitle: "Scanning windows",
            style: .info,
            symbol: "rectangle.split.3x3"
        )

        // NSApp is main-thread only — snapshot ourselves here.
        let ownWindows = snapshotOwnAppKitWindows(screenFrame: sf)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundle = Bundle.main.bundleIdentifier ?? "app.hyperforge.HyperForge"

        Task.detached(priority: .userInitiated) {
            let plan = Self.buildTilePlan(
                screenFrame: sf,
                gap: gap,
                ownWindows: ownWindows,
                myPID: myPID,
                myBundle: myBundle
            )
            await MainActor.run {
                self.applyTilePlan(plan)
                self.isTiling = false
            }
        }
        return 0
    }

    private func applyTilePlan(_ plan: TilePlan) {
        guard !plan.placements.isEmpty else {
            Banner.show(
                "Nothing to tile",
                subtitle: "No visible windows on this screen",
                style: .warning,
                symbol: "rectangle.dashed"
            )
            return
        }

        preTileLayout = plan.snapshots
        let n = plan.placements.count
        let myPID = ProcessInfo.processInfo.processIdentifier

        for (win, frame) in plan.placements {
            if win.useAppKit || win.pid == myPID {
                if applyOwnAppKitFrame(title: win.title, axFrame: frame) {
                    continue
                }
            }
            Self.applyAXFrame(win.element, frame)
        }

        Banner.show(
            "Tiled \(n) window\(n == 1 ? "" : "s")",
            subtitle: "\(plan.cols)×\(plan.rows) grid · Hyper+Z to undo",
            style: .success,
            symbol: "rectangle.split.3x3"
        )
    }

    /// Build plan + apply foreign-app AX frames off the main thread.
    nonisolated private static func buildTilePlan(
        screenFrame sf: NSRect,
        gap: CGFloat,
        ownWindows: [TileableWindow],
        myPID: pid_t,
        myBundle: String
    ) -> TilePlan {
        var windows = collectTileableWindowsOffMain(
            screenFrame: sf,
            myPID: myPID,
            myBundle: myBundle
        )
        if !ownWindows.isEmpty {
            windows.removeAll { $0.pid == myPID }
            windows.append(contentsOf: ownWindows)
        }

        windows.sort {
            if abs($0.frame.minY - $1.frame.minY) > 40 {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }

        let maxTiles = 16
        if windows.count > maxTiles {
            windows = Array(windows.prefix(maxTiles))
        }

        let snapshots = windows.map {
            WindowSnapshot(
                bundleID: $0.bundleID,
                title: $0.title,
                x: $0.frame.origin.x,
                y: $0.frame.origin.y,
                width: $0.frame.width,
                height: $0.frame.height
            )
        }

        let n = windows.count
        guard n > 0 else {
            return TilePlan(snapshots: [], placements: [], cols: 0, rows: 0)
        }

        let cols = Int(ceil(sqrt(Double(n))))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let cellW = (sf.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (sf.height - gap * CGFloat(rows + 1)) / CGFloat(rows)

        var placements: [(TileableWindow, NSRect)] = []
        placements.reserveCapacity(n)

        for (index, win) in windows.enumerated() {
            let col = index % cols
            let row = index / cols
            configureAXTimeout(win.element)
            AXUIElementSetAttributeValue(win.element, "AXMinimized" as CFString, kCFBooleanFalse)

            let frame = NSRect(
                x: sf.origin.x + gap + CGFloat(col) * (cellW + gap),
                y: sf.origin.y + gap + CGFloat(row) * (cellH + gap),
                width: max(120, cellW),
                height: max(80, cellH)
            )

            if !win.useAppKit {
                applyAXFrame(win.element, frame)
            }
            placements.append((win, frame))
        }

        return TilePlan(snapshots: snapshots, placements: placements, cols: cols, rows: rows)
    }

    @discardableResult
    private func applyOwnAppKitFrame(title: String, axFrame: NSRect) -> Bool {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let appKitFrame = NSRect(
            x: axFrame.origin.x,
            y: screen.frame.height - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
        let targets = NSApp.windows.filter {
            $0.isVisible && !$0.isMiniaturized && $0.frame.width >= 400 && $0.frame.height >= 300
        }
        let win =
            targets.first(where: { !$0.title.isEmpty && $0.title == title })
            ?? targets.first(where: { $0.title.localizedCaseInsensitiveContains("HyperForge") })
            ?? targets.first
        guard let win else { return false }
        win.setFrame(appKitFrame, display: true, animate: false)
        return true
    }

    private func snapshotOwnAppKitWindows(screenFrame sf: NSRect) -> [TileableWindow] {
        var extra: [TileableWindow] = []
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? "app.hyperforge.HyperForge"
        let placeholder = AXUIElementCreateApplication(myPID)

        for win in NSApp.windows where win.isVisible && !win.isMiniaturized {
            let isHUD =
                win.styleMask.contains(.borderless)
                && (win.level == .floating || win.level.rawValue > NSWindow.Level.normal.rawValue)
            if isHUD && win.frame.height < 80 { continue }
            guard win.frame.width >= 400, win.frame.height >= 300 else { continue }

            let screen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let axFrame = NSRect(
                x: win.frame.origin.x,
                y: screen.frame.height - win.frame.origin.y - win.frame.height,
                width: win.frame.width,
                height: win.frame.height
            )
            guard Self.framesIntersect(axFrame, sf, margin: 40) else { continue }

            extra.append(
                TileableWindow(
                    element: placeholder,
                    pid: myPID,
                    bundleID: bid,
                    title: win.title.isEmpty ? "HyperForge" : win.title,
                    frame: axFrame,
                    useAppKit: true
                )
            )
        }
        return extra
    }

    nonisolated private static func collectTileableWindowsOffMain(
        screenFrame sf: NSRect,
        myPID: pid_t,
        myBundle: String
    ) -> [TileableWindow] {
        var result: [TileableWindow] = []
        let skipBundles: Set<String> = [
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.dock",
            "com.apple.Spotlight",
            "com.apple.Wallpaper",
            "com.apple.WindowManager",
        ]

        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isHidden
                && $0.bundleIdentifier != nil
                && $0.processIdentifier != myPID
        }

        let deadline = Date().addingTimeInterval(1.25)
        var appsScanned = 0
        let maxApps = 24

        for app in candidates {
            if Date() > deadline || appsScanned >= maxApps { break }
            appsScanned += 1
            guard let bid = app.bundleIdentifier, !skipBundles.contains(bid) else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            configureAXTimeout(axApp)
            let windows = windowsForAppFast(axApp, bundleID: bid)

            for win in windows {
                configureAXTimeout(win)
                if isMinimizedFast(win) { continue }

                var subroleRef: AnyObject?
                if AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef)
                    == .success,
                    let sub = subroleRef as? String,
                    sub == "AXSystemDialog" || sub == "AXPictureInPictureWindow"
                {
                    continue
                }

                guard let frame = getFrameFast(win) else { continue }
                guard frame.width >= 160, frame.height >= 90 else { continue }
                guard framesIntersect(frame, sf, margin: 40) else { continue }

                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""

                result.append(
                    TileableWindow(
                        element: win,
                        pid: app.processIdentifier,
                        bundleID: bid,
                        title: title,
                        frame: frame,
                        useAppKit: false
                    )
                )
            }
        }

        _ = myBundle
        return result
    }

    nonisolated private static func windowsForAppFast(
        _ axApp: AXUIElement,
        bundleID: String
    ) -> [AXUIElement] {
        var found: [AXUIElement] = []

        func appendUnique(_ el: AXUIElement) {
            if !found.contains(where: { CFEqual($0, el) }) {
                found.append(el)
            }
        }

        configureAXTimeout(axApp)

        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            == .success,
            let windows = windowsRef as? [AXUIElement]
        {
            for win in windows.prefix(8) {
                appendUnique(win)
            }
        }

        for attr in [kAXFocusedWindowAttribute as String, kAXMainWindowAttribute as String] {
            var ref: AnyObject?
            if AXUIElementCopyAttributeValue(axApp, attr as CFString, &ref) == .success,
               let obj = ref
            {
                appendUnique(obj as! AXUIElement)
            }
        }

        if found.isEmpty {
            let picky =
                bundleID.contains("firefox")
                || bundleID.contains("mozilla")
                || bundleID.contains("chrome")
            if picky {
                var walked: [AXUIElement] = []
                var visits = 0
                collectWindowsByRoleFast(axApp, into: &walked, visits: &visits, limit: 24)
                walked.prefix(6).forEach(appendUnique)
            }
        }

        return found
    }

    nonisolated private static func collectWindowsByRoleFast(
        _ el: AXUIElement,
        into out: inout [AXUIElement],
        visits: inout Int,
        limit: Int
    ) {
        guard visits < limit else { return }
        visits += 1
        configureAXTimeout(el)

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, role == kAXWindowRole as String {
            out.append(el)
        }
        var childrenRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else { return }
        for child in children.prefix(6) {
            collectWindowsByRoleFast(child, into: &out, visits: &visits, limit: limit)
        }
    }

    nonisolated private static func isMinimizedFast(_ win: AXUIElement) -> Bool {
        var minRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(win, "AXMinimized" as CFString, &minRef) == .success
        else { return false }
        if let b = minRef as? Bool { return b }
        if let n = minRef as? NSNumber { return n.boolValue }
        return false
    }

    nonisolated private static func getFrameFast(_ window: AXUIElement) -> NSRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
                == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
                == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return NSRect(x: pos.x, y: pos.y, width: size.width, height: size.height)
    }

    nonisolated private static func framesIntersect(_ a: NSRect, _ b: NSRect, margin: CGFloat)
        -> Bool
    {
        let expanded = b.insetBy(dx: -margin, dy: -margin)
        return a.intersects(expanded)
    }

    /// Toggle float / focus-pin (AHK always-on-top).
    /// HyperForge windows use true floating level; other apps get raise + hide-others focus mode.
    func toggleAlwaysOnTop() {
        if let app = NSWorkspace.shared.frontmostApplication,
           Self.isHyperForgeBundle(app.bundleIdentifier),
           let win = NSApp.keyWindow ?? NSApp.mainWindow
        {
            let wasFloating = win.level == .floating
            win.level = wasFloating ? .normal : .floating
            if wasFloating {
                Banner.show(
                    "Always on top",
                    subtitle: "Off",
                    style: .neutral,
                    symbol: "pin.slash"
                )
            } else {
                Banner.show(
                    "Always on top",
                    subtitle: "On · this window floats",
                    style: .success,
                    symbol: "pin.fill"
                )
            }
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let win = frontmostWindow()
        else {
            Banner.show(
                "No front window",
                subtitle: "Focus a window first",
                style: .warning,
                symbol: "pin"
            )
            return
        }

        let key = "hf.aot.\(app.processIdentifier)"
        let on = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(on, forKey: key)
        let name = app.localizedName ?? "App"

        if on {
            app.activate(options: [.activateAllWindows])
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(win, "AXRaise" as CFString)
            for other in NSWorkspace.shared.runningApplications
            where other.processIdentifier != app.processIdentifier
                && other.activationPolicy == .regular
            {
                other.hide()
            }
            Banner.show(
                "Focus pin on",
                subtitle: "\(name) · other apps hidden",
                style: .success,
                symbol: "pin.fill"
            )
        } else {
            for other in NSWorkspace.shared.runningApplications
            where other.activationPolicy == .regular {
                other.unhide()
            }
            Banner.show(
                "Focus pin off",
                subtitle: name,
                style: .neutral,
                symbol: "pin.slash"
            )
        }
    }

    func minimizeFront() {
        guard let win = frontmostWindow() else {
            Banner.show(
                "No front window",
                subtitle: "Focus a window first",
                style: .warning,
                symbol: "minus.rectangle"
            )
            return
        }
        AXUIElementSetAttributeValue(win, "AXMinimized" as CFString, kCFBooleanTrue)
        Banner.show(
            "Minimized",
            subtitle: "Front window",
            style: .success,
            symbol: "minus.rectangle"
        )
    }

    // MARK: - Layout capture / restore (workspace feature)

    struct WindowSnapshot: Codable, Identifiable, Equatable {
        var id: String { "\(bundleID)-\(title)" }
        let bundleID: String
        let title: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    func captureLayout() -> [WindowSnapshot] {
        var snaps: [WindowSnapshot] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: AnyObject?
            guard
                AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
                    == .success,
                let windows = windowsRef as? [AXUIElement]
            else { continue }
            for win in windows {
                guard let frame = getFrame(win) else { continue }
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""
                snaps.append(
                    WindowSnapshot(
                        bundleID: bid,
                        title: title,
                        x: frame.origin.x,
                        y: frame.origin.y,
                        width: frame.width,
                        height: frame.height
                    )
                )
            }
        }
        return snaps
    }

    func restoreLayout(_ snapshots: [WindowSnapshot]) {
        var used = Set<ObjectIdentifier>()
        for snap in snapshots {
            guard
                let app = NSWorkspace.shared.runningApplications.first(where: {
                    $0.bundleIdentifier == snap.bundleID
                })
            else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: AnyObject?
            guard
                AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
                    == .success,
                let windows = windowsRef as? [AXUIElement]
            else { continue }

            // Prefer title match so multi-window apps restore correctly after tile.
            var target: AXUIElement?
            if !snap.title.isEmpty {
                for win in windows {
                    let oid = ObjectIdentifier(win as AnyObject)
                    if used.contains(oid) { continue }
                    var titleRef: AnyObject?
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                    if (titleRef as? String) == snap.title {
                        target = win
                        used.insert(oid)
                        break
                    }
                }
            }
            if target == nil {
                for win in windows {
                    let oid = ObjectIdentifier(win as AnyObject)
                    if used.contains(oid) { continue }
                    target = win
                    used.insert(oid)
                    break
                }
            }
            guard let win = target else { continue }
            setFrame(
                win,
                NSRect(x: snap.x, y: snap.y, width: snap.width, height: snap.height)
            )
        }
    }
}
