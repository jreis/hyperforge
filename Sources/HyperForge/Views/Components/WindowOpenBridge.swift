// WindowOpenBridge.swift
// Hosts SwiftUI `openWindow` for recreating the dashboard WindowGroup.
// Must live in a scene that is always mounted (MenuBarExtra), not only inside
// the main window — otherwise “Open Dashboard” dies when the window is gone.

import AppKit
import HyperForgeKit
import SwiftUI

struct WindowOpenBridge: View {
    var registerDashboard: Bool = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .hfOpenMainWindow)) { _ in
                openWindow(id: "main")
            }
            .onAppear {
                // Keep a reference so AppState can open without a live dashboard.
                WindowOpener.shared.bind(openWindow)
            }
            .background(DashboardWindowRegistrar(registerDashboard: registerDashboard))
    }
}

/// Holds the latest `openWindow` action from a live scene (menu bar or main).
@MainActor
enum WindowOpener {
    static let shared = WindowOpenerBox()
}

@MainActor
final class WindowOpenerBox {
    private var openMain: ((String) -> Void)?

    func bind(_ openWindow: OpenWindowAction) {
        openMain = { id in
            openWindow(id: id)
        }
    }

    var hasBinding: Bool { openMain != nil }

    func openMainWindow() {
        openMain?("main")
    }
}

/// Finds the hosting NSWindow and registers it as the HyperForge dashboard.
private struct DashboardWindowRegistrar: NSViewRepresentable {
    var registerDashboard: Bool

    func makeNSView(context: Context) -> DashboardHostView {
        let view = DashboardHostView()
        view.registerDashboard = registerDashboard
        return view
    }

    func updateNSView(_ nsView: DashboardHostView, context: Context) {
        nsView.registerDashboard = registerDashboard
        nsView.applyWindowPolicy()
    }
}

/// Hides a just-attached dashboard window on the same turn — before first paint.
final class DashboardHostView: NSView {
    var registerDashboard = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowPolicy()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyWindowPolicy()
    }

    func applyWindowPolicy() {
        guard let window else { return }
        if DashboardLaunchGate.hideIfNeeded(window) {
            return
        }
        guard registerDashboard else { return }
        let frame = window.frame
        guard frame.width >= 700, frame.height >= 400 else { return }
        Task { @MainActor in
            AppState.shared.registerDashboardWindow(window)
        }
    }
}
