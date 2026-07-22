// DashboardEscapeMonitor.swift
// Ensures Esc closes the main dashboard even when SwiftUI onExitCommand is flaky
// (hidden title bar / first responder issues).

import AppKit
import SwiftUI

struct DashboardEscapeMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == KeyCode.escape {
                AppState.shared.handleDashboardEscape()
                return
            }
            super.keyDown(with: event)
        }
    }
}
