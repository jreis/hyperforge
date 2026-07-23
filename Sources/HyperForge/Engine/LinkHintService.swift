// LinkHintService.swift
// Vimium-style link hints via Accessibility — fallback when browser extensions are blocked.
// Hyper + / (F18 plain) toggles. Type hint letters to click; Esc to dismiss.

import AppKit
import ApplicationServices
import Foundation

struct LinkHintTarget: Identifiable {
    let id: String
    let element: AXUIElement
    let frame: CGRect  // top-left AX coordinates, screen space
    let label: String
    let role: String
}

@MainActor
final class LinkHintService: ObservableObject {
    static let shared = LinkHintService()

    @Published private(set) var isActive = false
    @Published private(set) var targets: [LinkHintTarget] = []
    @Published private(set) var typed = ""

    /// One host window per screen; labels are subviews (not 80 separate NSWindows).
    private var overlayWindows: [NSWindow] = []
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isCollecting = false
    private let alphabet = Array("asdfjklghweruionmtycvp")
    private let maxHints = 60
    private let maxWalk = 400

    private init() {}

    func toggle() {
        if isActive { dismiss() } else { activate() }
    }

    func activate() {
        if isCollecting { return }
        dismiss()
        guard PermissionsService.isTrusted else {
            Banner.show(
                "Accessibility required",
                subtitle: "Link hints need Accessibility access",
                style: .warning,
                symbol: "link.circle"
            )
            return
        }

        isCollecting = true
        Banner.show(
            "Link hints",
            subtitle: "Scanning…",
            style: .info,
            symbol: "link.circle"
        )

        // AX tree walk can be heavy — keep UI responsive, then present.
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task.detached(priority: .userInitiated) { [maxWalk] in
            let found = Self.collectTargetsOffMain(frontPID: pid, limit: maxWalk)
            await MainActor.run {
                self.isCollecting = false
                self.finishActivate(found: found)
            }
        }
    }

    private func finishActivate(found: [RawTarget]) {
        guard !found.isEmpty else {
            Banner.show(
                "No clickable elements",
                subtitle: "Focus a browser or app window first",
                style: .warning,
                symbol: "link.circle"
            )
            return
        }

        var assigned: [LinkHintTarget] = []
        assigned.reserveCapacity(min(found.count, maxHints))
        for (i, t) in found.prefix(maxHints).enumerated() {
            let hint = hintString(for: i)
            assigned.append(
                LinkHintTarget(
                    id: hint,
                    element: t.element,
                    frame: t.frame,
                    label: t.label,
                    role: t.role
                )
            )
        }
        targets = assigned
        typed = ""
        isActive = true
        showOverlays()
        installKeyMonitor()
        EscapeCoordinator.shared.setHandler(.linkHints) { [weak self] in
            guard let self, self.isActive else { return false }
            self.dismiss()
            return true
        }
        Banner.show(
            "Link hints",
            subtitle: "Type label · Esc cancels · \(assigned.count) targets",
            style: .success,
            symbol: "link.circle"
        )
        HyperLog.event("LinkHints activated count=\(assigned.count)")
    }

    func dismiss() {
        isActive = false
        typed = ""
        targets = []
        removeOverlays()
        removeKeyMonitors()
        EscapeCoordinator.shared.setHandler(.linkHints, handler: nil)
    }

    // MARK: - Collection (off main)

    private struct RawTarget: @unchecked Sendable {
        let element: AXUIElement
        let frame: CGRect
        let label: String
        let role: String
    }

    nonisolated private static func collectTargetsOffMain(frontPID: pid_t?, limit: Int)
        -> [RawTarget]
    {
        guard let pid = frontPID else { return [] }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        var focused: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused)
        let roots: [AXUIElement]
        if let win = focused {
            roots = [unsafeBitCast(win, to: AXUIElement.self)]
        } else {
            var windowsRef: AnyObject?
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            roots = (windowsRef as? [AXUIElement]) ?? [axApp]
        }

        var results: [RawTarget] = []
        var visited = 0
        for root in roots {
            walk(root, into: &results, visited: &visited, limit: limit)
        }

        var seen = Set<String>()
        return results.filter { t in
            guard t.frame.width > 2, t.frame.height > 2 else { return false }
            let key = "\(Int(t.frame.midX))_\(Int(t.frame.midY))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    nonisolated private static func walk(
        _ el: AXUIElement,
        into results: inout [RawTarget],
        visited: inout Int,
        limit: Int
    ) {
        guard visited < limit else { return }
        visited += 1
        AXUIElementSetMessagingTimeout(el, 0.2)

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        let clickableRoles: Set<String> = [
            kAXButtonRole as String,
            "AXLink",
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXMenuItemRole as String,
            kAXMenuButtonRole as String,
        ]

        var actionsRef: CFArray?
        AXUIElementCopyActionNames(el, &actionsRef)
        let actions = (actionsRef as? [String]) ?? []
        let pressable = actions.contains(kAXPressAction as String)

        // Skip broad AXStaticText unless pressable — huge trees + noisy.
        if pressable || clickableRoles.contains(role) {
            if let frame = frame(of: el) {
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
                var descRef: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
                let label =
                    (titleRef as? String)
                    ?? (descRef as? String)
                    ?? role
                results.append(RawTarget(element: el, frame: frame, label: label, role: role))
            }
        }

        var childrenRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
        if err == .success, let children = childrenRef as? [AXUIElement] {
            // Cap fan-out per node — deep Electron trees hang / OOM.
            for child in children.prefix(40) {
                walk(child, into: &results, visited: &visited, limit: limit)
            }
        }
    }

    nonisolated private static func frame(of el: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
                == .success,
            AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        guard let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        let posOK = AXValueGetValue(
            unsafeBitCast(posVal, to: AXValue.self),
            .cgPoint,
            &pos
        )
        let sizeOK = AXValueGetValue(
            unsafeBitCast(sizeVal, to: AXValue.self),
            .cgSize,
            &size
        )
        guard posOK, sizeOK else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func hintString(for index: Int) -> String {
        if index < alphabet.count {
            return String(alphabet[index])
        }
        let hi = index / alphabet.count
        let lo = index % alphabet.count
        guard hi < alphabet.count else { return "z\(lo)" }
        return "\(alphabet[hi])\(alphabet[lo])"
    }

    // MARK: - Overlay UI (one window per screen)

    private func showOverlays() {
        removeOverlays()
        let filtered = filteredTargets()
        guard !filtered.isEmpty else { return }

        // Group hints by screen for a single host window each.
        var byScreen: [ObjectIdentifier: (NSScreen, [(String, NSRect)])] = [:]

        for t in filtered {
            let axMid = CGPoint(x: t.frame.midX, y: t.frame.midY)
            // AX Y is top-left space; map roughly into AppKit global space for screen hit-test.
            let primaryH = NSScreen.screens.map(\.frame.maxY).max()
                ?? (NSScreen.main?.frame.maxY ?? 0)
            let appKitProbe = CGPoint(x: axMid.x, y: primaryH - axMid.y)
            let screen =
                NSScreen.screens.first(where: { $0.frame.insetBy(dx: -40, dy: -40).contains(appKitProbe) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
            guard let screen else { continue }

            let appKitY = screen.frame.maxY - t.frame.origin.y - 22
            let labelFrame = NSRect(
                x: t.frame.origin.x - screen.frame.minX,
                y: appKitY - screen.frame.minY,
                width: 34,
                height: 22
            )
            let sid = ObjectIdentifier(screen)
            var entry = byScreen[sid] ?? (screen, [])
            entry.1.append((t.id.uppercased(), labelFrame))
            byScreen[sid] = entry
        }

        for (_, pair) in byScreen {
            let (screen, labels) = pair
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.isReleasedWhenClosed = false
            win.level = .floating
            win.isOpaque = false
            win.backgroundColor = .clear
            win.ignoresMouseEvents = true
            win.hasShadow = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.alphaValue = 1

            let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor

            for (text, frame) in labels.prefix(maxHints) {
                let label = NSTextField(labelWithString: text)
                label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                label.textColor = .white
                label.alignment = .center
                label.wantsLayer = true
                label.layer?.backgroundColor =
                    NSColor.systemOrange.withAlphaComponent(0.92).cgColor
                label.layer?.cornerRadius = 4
                label.layer?.masksToBounds = true
                label.frame = frame
                host.addSubview(label)
            }

            win.contentView = host
            win.setFrame(screen.frame, display: false)
            win.orderFrontRegardless()
            overlayWindows.append(win)
        }
    }

    private func removeOverlays() {
        let windows = overlayWindows
        overlayWindows = []
        for w in windows {
            // Avoid close() animation / transform teardown crashes.
            w.ignoresMouseEvents = true
            w.alphaValue = 0
            w.orderOut(nil)
            w.contentView = nil
            // isReleasedWhenClosed = false → ARC drops when `windows` leaves scope.
        }
    }

    private func filteredTargets() -> [LinkHintTarget] {
        if typed.isEmpty { return targets }
        return targets.filter { $0.id.hasPrefix(typed) }
    }

    private func refreshOverlays() {
        removeOverlays()
        if isActive { showOverlays() }
    }

    private func installKeyMonitor() {
        removeKeyMonitors()
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            Task { @MainActor in
                self?.handleKey(event)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isActive else { return event }
            self.handleKey(event)
            return nil
        }
    }

    private func removeKeyMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard isActive else { return }
        let code = event.keyCode
        // Esc → EscapeCoordinator (.linkHints); don't handle here (avoids double-dismiss).
        if code == KeyCode.escape {
            _ = EscapeCoordinator.shared.handleEscape()
            return
        }
        if code == KeyCode.delete {
            if !typed.isEmpty {
                typed.removeLast()
                refreshOverlays()
            }
            return
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let ch = chars.first,
              alphabet.contains(ch)
        else { return }

        typed.append(ch)
        let matches = filteredTargets()
        if let exact = matches.first(where: { $0.id == typed }) {
            click(exact)
            dismiss()
            return
        }
        if matches.isEmpty {
            Banner.show(
                "No match",
                subtitle: "“\(typed)”",
                style: .warning,
                symbol: "link.circle"
            )
            typed = ""
            refreshOverlays()
            return
        }
        refreshOverlays()
    }

    private func click(_ target: LinkHintTarget) {
        let err = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        if err != .success {
            let primaryH = NSScreen.screens.map(\.frame.maxY).max()
                ?? (NSScreen.main?.frame.height ?? 0)
            let point = CGPoint(x: target.frame.midX, y: primaryH - target.frame.midY)
            if let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
                let up = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: point,
                    mouseButton: .left
                )
            {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
        HyperLog.event("LinkHint clicked \(target.id) role=\(target.role)")
    }
}
