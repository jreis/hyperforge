// WindowManager.swift
// Accessibility-based window framing, snap, and undo.
// Ported from hyperkey.swift — coordinate system is top-left origin for AX.

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

    private init() {}

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
        var pos = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size)
        else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
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
        guard let win = frontmostWindow() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1, let current = NSScreen.main else { return }
        let idx = screens.firstIndex(of: current) ?? 0
        let next = screens[(idx + 1) % screens.count]
        let vis = next.visibleFrame
        let full = next.frame
        let topLeft = NSRect(
            x: vis.origin.x,
            y: full.height - vis.origin.y - vis.height,
            width: vis.width,
            height: vis.height
        )
        setFrame(win, topLeft)
    }

    @discardableResult
    func undo() -> Bool {
        // Prefer restoring a full tile layout if one is pending.
        if !preTileLayout.isEmpty {
            restoreLayout(preTileLayout)
            preTileLayout = []
            Banner.show(
                "Tile undone",
                subtitle: "Previous layout restored",
                style: .info,
                symbol: "arrow.uturn.backward"
            )
            return true
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let saved = frameHistory[app.processIdentifier],
              let win = frontmostWindow()
        else { return false }
        setFrame(win, saved)
        frameHistory.removeValue(forKey: app.processIdentifier)
        return true
    }

    // MARK: - Tile all visible windows

    private struct TileableWindow {
        let element: AXUIElement
        let pid: pid_t
        let bundleID: String
        let title: String
        let frame: NSRect
    }

    /// Arrange every visible, non-minimized standard window on the main screen
    /// into a grid that fills the screen (with small gaps).
    @discardableResult
    func tileAllVisible(gap: CGFloat = 8) -> Int {
        let sf = screenFrame()
        guard sf.width > 0, sf.height > 0 else { return 0 }

        var windows = collectTileableWindows(screenFrame: sf)
        guard !windows.isEmpty else {
            Banner.show(
                "Nothing to tile",
                subtitle: "No visible windows on this screen",
                style: .warning,
                symbol: "rectangle.dashed"
            )
            return 0
        }

        // Stable order: left-to-right, top-to-bottom of current positions.
        windows.sort {
            if abs($0.frame.minY - $1.frame.minY) > 40 {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }

        // Snapshot for undo
        preTileLayout = windows.map {
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
        let cols = Int(ceil(sqrt(Double(n))))
        let rows = Int(ceil(Double(n) / Double(cols)))

        let cellW = (sf.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (sf.height - gap * CGFloat(rows + 1)) / CGFloat(rows)

        let myPID = ProcessInfo.processInfo.processIdentifier

        for (index, win) in windows.enumerated() {
            let col = index % cols
            let row = index / cols
            // Un-minimize if needed
            AXUIElementSetAttributeValue(win.element, "AXMinimized" as CFString, kCFBooleanFalse)

            let frame = NSRect(
                x: sf.origin.x + gap + CGFloat(col) * (cellW + gap),
                y: sf.origin.y + gap + CGFloat(row) * (cellH + gap),
                width: max(120, cellW),
                height: max(80, cellH)
            )

            // Own process: prefer AppKit (AX is flaky for accessory / swift-run builds)
            if win.pid == myPID, applyOwnAppKitFrame(title: win.title, axFrame: frame) {
                continue
            }
            setFrame(win.element, frame)
        }

        Banner.show(
            "Tiled \(n) window\(n == 1 ? "" : "s")",
            subtitle: "\(cols)×\(rows) grid · Hyper+Z to undo",
            style: .success,
            symbol: "rectangle.split.3x3"
        )
        return n
    }

    /// Resize/move one of our NSWindows. `axFrame` is top-left AX coords.
    @discardableResult
    private func applyOwnAppKitFrame(title: String, axFrame: NSRect) -> Bool {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // AX top-left → AppKit bottom-left
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
        win.setFrame(appKitFrame, display: true, animate: true)
        return true
    }

    private func collectTileableWindows(screenFrame sf: NSRect) -> [TileableWindow] {
        var result: [TileableWindow] = []
        // System UI only — include HyperForge, Firefox, accessory apps (menu bar hosts).
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

        // .regular (normal apps) + .accessory (menu bar apps like HyperForge under LSUIElement)
        let candidates = NSWorkspace.shared.runningApplications.filter {
            ($0.activationPolicy == .regular || $0.activationPolicy == .accessory)
                && !$0.isHidden
                && $0.bundleIdentifier != nil
        }

        for app in candidates {
            guard let bid = app.bundleIdentifier, !skipBundles.contains(bid) else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let windows = windowsForApp(axApp, pid: app.processIdentifier, bundleID: bid)

            for win in windows {
                if isMinimized(win) { continue }

                // Skip pure system/sheet chrome when subrole is explicit
                var subroleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef)
                if let sub = subroleRef as? String {
                    if sub == "AXSystemDialog" || sub == "AXPictureInPictureWindow" { continue }
                }

                guard let frame = getFrame(win) else {
                    HyperLog.event("tile skip \(bid): no frame")
                    continue
                }
                // Ignore tooltips / status chips; keep normal browser & app windows
                guard frame.width >= 160, frame.height >= 90 else {
                    HyperLog.event(
                        "tile skip \(bid): tiny \(Int(frame.width))x\(Int(frame.height))"
                    )
                    continue
                }

                // Intersect screen (not just center) — Firefox/multi-monitor edge cases
                guard framesIntersect(frame, sf, margin: 40) else {
                    HyperLog.event("tile skip \(bid): off-screen frame=\(frame) sf=\(sf)")
                    continue
                }

                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""

                result.append(
                    TileableWindow(
                        element: win,
                        pid: app.processIdentifier,
                        bundleID: bid,
                        title: title,
                        frame: frame
                    )
                )
                HyperLog.event("tile include \(bid) “\(title.prefix(40))” \(Int(frame.width))x\(Int(frame.height))")
            }
        }

        // HyperForge under swift run / accessory: AX sometimes misses our NSWindows.
        // Fall back to AppKit windows for this process.
        result.append(contentsOf: collectOwnAppKitWindows(screenFrame: sf, existing: result))

        return result
    }

    /// AX window list — Firefox is picky; combine windows list + focus/main + role walk.
    private func windowsForApp(
        _ axApp: AXUIElement,
        pid: pid_t,
        bundleID: String
    ) -> [AXUIElement] {
        var found: [AXUIElement] = []

        func appendUnique(_ el: AXUIElement) {
            if !found.contains(where: { CFEqual($0, el) }) {
                found.append(el)
            }
        }

        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            == .success,
            let windows = windowsRef as? [AXUIElement]
        {
            windows.forEach(appendUnique)
        }

        // Seed with focused / main (helps Firefox & Chrome)
        for attr in [kAXFocusedWindowAttribute as String, kAXMainWindowAttribute as String] {
            var ref: AnyObject?
            if AXUIElementCopyAttributeValue(axApp, attr as CFString, &ref) == .success,
               let obj = ref
            {
                appendUnique(obj as! AXUIElement)
            }
        }

        // Role walk: some builds bury windows under children instead of AXWindows
        if found.isEmpty || bundleID.contains("firefox") || bundleID.contains("mozilla") {
            var walked: [AXUIElement] = []
            var visits = 0
            collectWindowsByRole(axApp, into: &walked, visits: &visits, limit: 80)
            walked.forEach(appendUnique)
        }

        if found.isEmpty {
            HyperLog.event("tile: no AX windows for \(bundleID) pid=\(pid)")
        } else {
            HyperLog.event("tile: \(found.count) AX window(s) for \(bundleID)")
        }
        return found
    }

    private func collectWindowsByRole(
        _ el: AXUIElement,
        into out: inout [AXUIElement],
        visits: inout Int,
        limit: Int
    ) {
        guard visits < limit else { return }
        visits += 1

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
        for child in children {
            collectWindowsByRole(child, into: &out, visits: &visits, limit: limit)
        }
    }

    private func isMinimized(_ win: AXUIElement) -> Bool {
        var minRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(win, "AXMinimized" as CFString, &minRef) == .success
        else { return false }
        if let b = minRef as? Bool { return b }
        // Some apps return NSNumber
        if let n = minRef as? NSNumber { return n.boolValue }
        return false
    }

    private func framesIntersect(_ a: NSRect, _ b: NSRect, margin: CGFloat) -> Bool {
        let expanded = b.insetBy(dx: -margin, dy: -margin)
        return a.intersects(expanded)
    }

    /// Own process windows via AppKit when AX omits them (menu bar / swift run).
    private func collectOwnAppKitWindows(
        screenFrame sf: NSRect,
        existing: [TileableWindow]
    ) -> [TileableWindow] {
        var extra: [TileableWindow] = []
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? "app.hyperforge.HyperForge"

        // Already have our windows from AX?
        if existing.contains(where: { $0.pid == myPID }) { return [] }

        for win in NSApp.windows where win.isVisible && !win.isMiniaturized {
            // Skip borderless toasts / HUDs
            let isHUD =
                win.styleMask.contains(.borderless)
                && (win.level == .floating || win.level.rawValue > NSWindow.Level.normal.rawValue)
            if isHUD && win.frame.height < 80 { continue }
            // Only real content windows (dashboard etc.)
            guard win.frame.width >= 400, win.frame.height >= 300 else { continue }

            // Convert AppKit bottom-left frame → AX top-left
            let screen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let axFrame = NSRect(
                x: win.frame.origin.x,
                y: screen.frame.height - win.frame.origin.y - win.frame.height,
                width: win.frame.width,
                height: win.frame.height
            )
            guard framesIntersect(axFrame, sf, margin: 40) else { continue }

            // Use AX focused/main for the element so setFrame works
            let axApp = AXUIElementCreateApplication(myPID)
            var el: AXUIElement?
            var focusedRef: AnyObject?
            if AXUIElementCopyAttributeValue(
                axApp, kAXFocusedWindowAttribute as CFString, &focusedRef
            ) == .success {
                el = (focusedRef as! AXUIElement)
            } else {
                var windowsRef: AnyObject?
                if AXUIElementCopyAttributeValue(
                    axApp, kAXWindowsAttribute as CFString, &windowsRef
                ) == .success,
                    let windows = windowsRef as? [AXUIElement],
                    let first = windows.first
                {
                    el = first
                }
            }

            if let el {
                extra.append(
                    TileableWindow(
                        element: el,
                        pid: myPID,
                        bundleID: bid,
                        title: win.title,
                        frame: axFrame
                    )
                )
            } else {
                // Direct AppKit resize as last resort (own process only)
                let visible = screen.visibleFrame
                // Will be laid out in tileAllVisible via AppKit path — store a placeholder
                // by applying setFrameOrigin/setContentSize after grid is computed.
                // Handled below in tileAllVisible for own windows without AX.
                _ = visible
                HyperLog.event("tile: HyperForge window “\(win.title)” has no AX element; will AppKit-tile")
                // Encode using a dummy system-wide element — tileAllVisible special-cases pid
                extra.append(
                    TileableWindow(
                        element: AXUIElementCreateApplication(myPID),
                        pid: myPID,
                        bundleID: bid,
                        title: win.title.isEmpty ? "HyperForge" : win.title,
                        frame: axFrame
                    )
                )
            }
        }
        return extra
    }

    /// Toggle float / focus-pin (AHK always-on-top).
    /// HyperForge windows use true floating level; other apps get raise + hide-others focus mode.
    func toggleAlwaysOnTop() {
        if let app = NSWorkspace.shared.frontmostApplication,
           (app.bundleIdentifier == Bundle.main.bundleIdentifier
               || app.bundleIdentifier == "app.hyperforge.HyperForge"
               || app.bundleIdentifier == "dev.jasonreis.HyperForge"),
           let win = NSApp.keyWindow ?? NSApp.mainWindow
        {
            let wasFloating = win.level == .floating
            win.level = wasFloating ? .normal : .floating
            Banner.show(wasFloating ? "Always on top OFF" : "Always on top ON")
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let win = frontmostWindow()
        else {
            Banner.show("No front window")
            return
        }

        let key = "hf.aot.\(app.processIdentifier)"
        let on = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(on, forKey: key)

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
            Banner.show("Focus pin ON (others hidden)")
        } else {
            for other in NSWorkspace.shared.runningApplications
            where other.activationPolicy == .regular {
                other.unhide()
            }
            Banner.show("Focus pin OFF")
        }
    }

    func minimizeFront() {
        guard let win = frontmostWindow() else {
            Banner.show("No front window")
            return
        }
        // kAXMinimizeButton or set AXMinimized
        AXUIElementSetAttributeValue(win, "AXMinimized" as CFString, kCFBooleanTrue)
        Banner.show("Minimized")
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
