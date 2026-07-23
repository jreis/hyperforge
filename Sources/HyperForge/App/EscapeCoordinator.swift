// EscapeCoordinator.swift
// Single Esc pipeline — innermost / most transient UI wins.
//
// Priority (first match handles Esc and stops):
//   1. Region selection (drag-to-pin)
//   2. Floating pins (region / clipboard image)
//   3. Link hints
//   4. Command bar
//   5. Cheat sheet
//   6. Dashboard

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
        case commandBar = 3
        case cheatSheet = 4
        case dashboard = 5

        static func < (lhs: Layer, rhs: Layer) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Handler returns `true` if it consumed Esc.
    private var handlers: [Layer: () -> Bool] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var started = false

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
            let visible = AppState.dashboardWindows().contains(where: \.isVisible)
            guard visible else { return false }
            AppState.shared.closeMainWindow()
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
        default:
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
        for layer in Layer.allCases.sorted() {
            if handlers[layer]?() == true {
                HyperLog.event("Escape handled by \(layer)")
                return true
            }
        }
        return false
    }
}
