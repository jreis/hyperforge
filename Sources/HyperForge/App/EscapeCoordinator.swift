// EscapeCoordinator.swift
// Single Esc pipeline — innermost / most transient UI wins.
//
// Priority (first match handles Esc and stops):
//   1. Region selection (drag-to-pin)
//   2. Floating pins (region / clipboard image)
//   3. Link hints
//   4. Clipboard history
//   5. AX recipe recording
//   6. Command bar
//   7. Cheat sheet
//   8. Dashboard

import AppKit
import Foundation

@MainActor
final class EscapeCoordinator {
    static let shared = EscapeCoordinator()

    /// Lower rawValue = higher priority.
    enum Layer: Int, CaseIterable, Comparable {
        case regionSelection = 0
        case floatingPin = 1
        case linkHints = 2
        case clipboardHistory = 3
        case axRecording = 4
        case commandBar = 5
        case cheatSheet = 6
        case dashboard = 7

        static func < (lhs: Layer, rhs: Layer) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Handler returns `true` if it consumed Esc.
    private var handlers: [Layer: () -> Bool] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var started = false

    /// Set by the Scripts pane's embedded CodeMirror editor while it holds keyboard
    /// focus. Vim mode uses Esc constantly (insert -> normal mode); without this the
    /// local monitor below swallows it first and hides the whole dashboard instead.
    var webEditorHasFocus = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        // Dynamic layers that read app state (always registered).
        register(.commandBar) {
            guard AppState.shared.commandBarVisible else { return false }
            AppState.shared.commandBarVisible = false
            return true
        }
        register(.cheatSheet) {
            guard CheatSheetCommands.isVisible else { return false }
            CheatSheetCommands.hide()
            return true
        }
        register(.dashboard) {
            let windows = AppState.dashboardWindows().filter(\.isVisible)
            guard !windows.isEmpty else { return false }
            // Don't hide a background dashboard when Esc is used in another app
            // (or Caps-alone Escape while coding).
            guard NSApp.isActive || windows.contains(where: \.isKeyWindow) else {
                return false
            }
            AppState.shared.closeMainWindow() // also prepareAfterUIDismiss
            return true
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return event }
            // Hyper+Esc (lock) is handled by the event tap while Hyper is held —
            // that path never reaches here as a normal Esc for our UI stack.
            guard let self else { return event }
            var consumed = false
            // Monitors may run off main; hop safely.
            if Thread.isMainThread {
                consumed = self.handleEscape()
            } else {
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    consumed = self.handleEscape()
                    sem.signal()
                }
                _ = sem.wait(timeout: .now() + 0.05)
            }
            return consumed ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return }
            Task { @MainActor in
                _ = self?.handleEscape()
            }
        }
    }

    func register(_ layer: Layer, handler: @escaping () -> Bool) {
        handlers[layer] = handler
    }

    func unregister(_ layer: Layer) {
        // Don't remove dynamic always-on layers from outside.
        switch layer {
        case .commandBar, .cheatSheet, .dashboard:
            return
        case .regionSelection, .floatingPin, .linkHints, .clipboardHistory, .axRecording:
            handlers[layer] = nil
        }
    }

    /// Force-set a dynamic layer (pins / selection / hints).
    func setHandler(_ layer: Layer, handler: (() -> Bool)?) {
        if let handler {
            handlers[layer] = handler
        } else {
            handlers[layer] = nil
        }
    }

    @discardableResult
    func handleEscape() -> Bool {
        // Caps alone → Escape (Karabiner to_if_alone) must not dismiss dashboard /
        // cheat sheet / etc. Real Esc still works outside that short window.
        if HyperKeyEngine.shared.shouldSuppressEscapeForUI {
            HyperLog.event("Escape ignored for UI (post-Hyper / Caps-alone)")
            return false
        }
        if webEditorHasFocus {
            HyperLog.event("Escape passed through to script editor (vim mode)")
            return false
        }
        for layer in Layer.allCases.sorted() {
            if handlers[layer]?() == true {
                HyperLog.event("Escape handled by \(layer)")
                return true
            }
        }
        return false
    }
}
