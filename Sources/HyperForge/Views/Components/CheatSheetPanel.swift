// CheatSheetPanel.swift
// Pure AppKit presenter — no @MainActor isolation (avoids MenuBarExtra /
// Swift 6 MainActor.assumeIsolated crashes on button click).

import AppKit
import SwiftUI

extension Notification.Name {
    static let hfToggleCheatSheet = Notification.Name("hfToggleCheatSheet")
    static let hfShowCheatSheet = Notification.Name("hfShowCheatSheet")
    static let hfHideCheatSheet = Notification.Name("hfHideCheatSheet")
    /// Posted after the cheatsheet window is ordered front and should take search focus.
    static let hfCheatSheetBecameKey = Notification.Name("hfCheatSheetBecameKey")
}

/// Thread-safe entry points. Always hop to the main queue for UI.
enum CheatSheetCommands {
    /// Safe from buttons, event taps, menus, any thread.
    static func toggle() {
        DispatchQueue.main.async {
            CheatSheetPanelController.shared.toggle()
        }
    }

    static func show() {
        DispatchQueue.main.async {
            // Always force show (never no-op if a half-dead window exists)
            CheatSheetPanelController.shared.hide()
            CheatSheetPanelController.shared.show()
        }
    }

    static func hide() {
        DispatchQueue.main.async {
            CheatSheetPanelController.shared.hide()
        }
    }

    static var isVisible: Bool {
        if Thread.isMainThread {
            return CheatSheetPanelController.shared.isVisible
        }
        var result = false
        DispatchQueue.main.sync {
            result = CheatSheetPanelController.shared.isVisible
        }
        return result
    }
}

/// Compatibility alias used around the codebase.
enum CheatSheetPanel {
    static var isVisible: Bool { CheatSheetCommands.isVisible }
    static func show() { CheatSheetCommands.show() }
    static func hide() { CheatSheetCommands.hide() }
    static func toggle() { CheatSheetCommands.toggle() }
}

// MARK: - Controller (main-queue only)

final class CheatSheetPanelController: NSObject {
    static let shared = CheatSheetPanelController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    var isVisible: Bool {
        window?.isVisible == true
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .hfToggleCheatSheet,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggle()
        }
        NotificationCenter.default.addObserver(
            forName: .hfShowCheatSheet,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.show()
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        assert(Thread.isMainThread)
        HyperLog.event("CheatSheetPanelController.show begin")

        if let window, window.isVisible {
            forceFront(window)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Standalone view — no EnvironmentObject / @MainActor stores (crash-safe).
        let hosting = NSHostingController(rootView: StandaloneCheatSheetView())
        hosting.view.frame = NSRect(x: 0, y: 0, width: 740, height: 580)

        // Subclass guarantees canBecomeKey/Main even at .floating level (LSUIElement apps).
        let win = KeyableFloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "HyperForge — Keybindings"
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        // Note: canJoinAllSpaces and moveToActiveSpace are mutually exclusive on modern macOS.
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.contentViewController = hosting
        win.setContentSize(NSSize(width: 740, height: 580))
        win.center()
        win.level = .floating
        win.isOpaque = true
        win.acceptsMouseMovedEvents = true

        self.window = win
        forceFront(win)

        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
            self?.restoreAccessoryIfNeeded()
        }

        HyperLog.event(
            "CheatSheetPanelController shown isVisible=\(win.isVisible) frame=\(NSStringFromRect(win.frame))"
        )
        // No Banner toast — a competing floating window can steal key focus from the search field.
    }

    func hide() {
        assert(Thread.isMainThread)
        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
            closeObserver = nil
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
        restoreAccessoryIfNeeded()
    }

    private func forceFront(_ win: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.level = .floating
        win.orderFrontRegardless()
        win.makeKeyAndOrderFront(nil)
        win.makeMain()
        // Retries: SwiftUI hosts the NSTextField a beat after layout; LSUIElement
        // activation is also racy right after Hyper chord release.
        let delays: [TimeInterval] = [0, 0.05, 0.12, 0.25, 0.45]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.window === win, win.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
                Self.focusSearchField(in: win)
                NotificationCenter.default.post(name: .hfCheatSheetBecameKey, object: win)
            }
        }
    }

    /// Walk the hosting hierarchy and put the search NSTextField first responder.
    @discardableResult
    static func focusSearchField(in win: NSWindow) -> Bool {
        guard let root = win.contentView else { return false }
        if let field = firstEditableTextField(in: root) {
            win.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
            return win.firstResponder === field || win.firstResponder === field.currentEditor()
        }
        return false
    }

    private static func firstEditableTextField(in view: NSView) -> NSTextField? {
        var tagged: NSTextField?
        var any: NSTextField?
        func walk(_ v: NSView) {
            if let tf = v as? NSTextField, tf.isEditable, !tf.isHidden, tf.alphaValue > 0.01 {
                if tf.identifier?.rawValue == "hf.cheatsheet.search" {
                    tagged = tf
                } else if any == nil {
                    any = tf
                }
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(view)
        return tagged ?? any
    }

    private func restoreAccessoryIfNeeded() {
        if UserDefaults.standard.object(forKey: "hf.menuBarOnly") as? Bool ?? true {
            // Delay so close animation finishes; never steal focus from a visible dashboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if !AppState.dashboardWindows().filter(\.isVisible).isEmpty { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Keyable window

/// Floating windows in accessory/menu-bar apps sometimes refuse key status;
/// force canBecomeKey/Main so typing lands in the search field.
private final class KeyableFloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
