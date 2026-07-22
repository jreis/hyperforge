// LinkHintService.swift
// Vimium-style link hints via Accessibility — fallback when browser extensions are blocked.
// Hyper + / toggles. Type hint letters to click; Esc or / again to dismiss.

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

    private var overlayWindows: [NSWindow] = []
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let alphabet = Array("asdfjklghweruionmtycvp")

    private init() {}

    func toggle() {
        if isActive { dismiss() } else { activate() }
    }

    func activate() {
        dismiss()
        guard PermissionsService.isTrusted else {
            Banner.show("Accessibility required for link hints")
            return
        }

        let found = collectTargets()
        guard !found.isEmpty else {
            Banner.show("No clickable elements found")
            return
        }

        // Assign short hints
        var assigned: [LinkHintTarget] = []
        for (i, t) in found.prefix(alphabet.count * alphabet.count).enumerated() {
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
        Banner.show("Link hints · type label · Esc to cancel")
        HyperLog.event("LinkHints activated count=\(assigned.count)")
    }

    func dismiss() {
        isActive = false
        typed = ""
        targets = []
        removeOverlays()
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    // MARK: - Collection

    private struct RawTarget {
        let element: AXUIElement
        let frame: CGRect
        let label: String
        let role: String
    }

    private func collectTargets() -> [RawTarget] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused)
        let roots: [AXUIElement]
        if let win = focused {
            roots = [win as! AXUIElement]
        } else {
            var windowsRef: AnyObject?
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            roots = (windowsRef as? [AXUIElement]) ?? [axApp]
        }

        var results: [RawTarget] = []
        var visited = 0
        for root in roots {
            walk(root, into: &results, visited: &visited, limit: 800)
        }

        // Prefer on-screen, de-dupe by frame center
        var seen = Set<String>()
        return results.filter { t in
            guard t.frame.width > 2, t.frame.height > 2 else { return false }
            let key = "\(Int(t.frame.midX))_\(Int(t.frame.midY))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func walk(
        _ el: AXUIElement,
        into results: inout [RawTarget],
        visited: inout Int,
        limit: Int
    ) {
        guard visited < limit else { return }
        visited += 1

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        let clickableRoles: Set<String> = [
            kAXButtonRole as String,
            "AXLink",
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXTabGroupRole as String,
            kAXMenuItemRole as String,
            kAXMenuButtonRole as String,
            "AXStaticText",  // many web views expose links poorly; include text that is pressable
        ]

        var actionsRef: CFArray?
        AXUIElementCopyActionNames(el, &actionsRef)
        let actions = (actionsRef as? [String]) ?? []
        let pressable = actions.contains(kAXPressAction as String)

        if pressable || clickableRoles.contains(role) {
            if let frame = frame(of: el) {
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
                var descRef: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
                var valueRef: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
                let label =
                    (titleRef as? String)
                    ?? (descRef as? String)
                    ?? (valueRef as? String)
                    ?? role
                results.append(RawTarget(element: el, frame: frame, label: label, role: role))
            }
        }

        var childrenRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
        if err == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                walk(child, into: &results, visited: &visited, limit: limit)
            }
        }
    }

    private func frame(of el: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private func hintString(for index: Int) -> String {
        if index < alphabet.count {
            return String(alphabet[index])
        }
        let a = alphabet[index / alphabet.count]
        let b = alphabet[index % alphabet.count]
        return "\(a)\(b)"
    }

    // MARK: - Overlay UI

    private func showOverlays() {
        removeOverlays()
        let filtered = filteredTargets()
        for t in filtered.prefix(80) {
            // Convert AX top-left coords to AppKit bottom-left for the screen
            guard let screen = NSScreen.screens.first(where: {
                $0.frame.contains(CGPoint(x: t.frame.midX, y: $0.frame.maxY - t.frame.midY))
            }) ?? NSScreen.main else { continue }

            let axY = t.frame.origin.y
            let appKitY = screen.frame.maxY - axY - 22
            let x = t.frame.origin.x

            let win = NSWindow(
                contentRect: NSRect(x: x, y: appKitY, width: 34, height: 22),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            win.level = .screenSaver
            win.isOpaque = false
            win.backgroundColor = .clear
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary]
            win.hasShadow = true

            let label = NSTextField(labelWithString: t.id.uppercased())
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.wantsLayer = true
            label.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.92).cgColor
            label.layer?.cornerRadius = 4
            label.frame = NSRect(x: 0, y: 0, width: 34, height: 22)
            win.contentView = label
            win.orderFront(nil)
            overlayWindows.append(win)
        }
    }

    private func removeOverlays() {
        for w in overlayWindows { w.close() }
        overlayWindows = []
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
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKey(event)
            }
        }
        // Local monitor for when HyperForge is focused; swallow keys while hints are active.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            self.handleKey(event)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard isActive else { return }
        let code = event.keyCode
        if code == KeyCode.escape {
            dismiss()
            return
        }
        // Backspace
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
            Banner.show("No hint “\(typed)”")
            typed = ""
            refreshOverlays()
            return
        }
        refreshOverlays()
    }

    private func click(_ target: LinkHintTarget) {
        let err = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        if err != .success {
            // Fallback: click center via CGEvent
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let x = target.frame.midX
            let y = screen.frame.height - target.frame.midY
            let point = CGPoint(x: x, y: y)
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
