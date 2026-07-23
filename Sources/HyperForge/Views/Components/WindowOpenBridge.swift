// WindowOpenBridge.swift
// Hosts SwiftUI `openWindow` for recreating the dashboard WindowGroup.
// Must live in a scene that is always mounted (MenuBarExtra), not only inside
// the main window — otherwise “Open Dashboard” dies when the window is gone.

import AppKit
import HyperForgeKit
import SwiftUI

struct WindowOpenBridge: View {
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
            .background(DashboardWindowRegistrar())
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

    func openMainWindow() {
        openMain?("main")
    }
}

/// Finds the hosting NSWindow and registers it as the HyperForge dashboard.
private struct DashboardWindowRegistrar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.register(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.register(from: nsView)
        }
    }

    private static func register(from view: NSView) {
        guard let window = view.window else { return }
        // Only tag real dashboard hosts (not the menu bar popover panel).
        let frame = window.frame
        guard frame.width >= 700, frame.height >= 400 else { return }
        Task { @MainActor in
            AppState.shared.registerDashboardWindow(window)
        }
    }
}
