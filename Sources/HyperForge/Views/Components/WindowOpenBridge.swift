// WindowOpenBridge.swift
// Lets AppKit / Hyper key code request the SwiftUI WindowGroup to appear,
// and tags the dashboard window for reliable re-find after hide/close.

import AppKit
import SwiftUI

struct WindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .hfOpenMainWindow)) { _ in
                openWindow(id: "main")
            }
            .background(DashboardWindowRegistrar())
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
        Task { @MainActor in
            AppState.shared.registerDashboardWindow(window)
        }
    }
}
