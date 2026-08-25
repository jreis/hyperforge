// DashboardWindowController.swift
// AppKit-hosted dashboard. Created only when shown — never at launch.

import AppKit
import HyperForgeKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    var hostedWindow: NSWindow? { window }

    func show() {
        let w = existingOrCreate()
        DashboardLaunchGate.restoreAlpha(w)
        AppState.shared.registerDashboardWindow(w)
        w.collectionBehavior.insert(.moveToActiveSpace)
        if w.isMiniaturized {
            w.deminiaturize(nil)
        }
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Traffic-light close hides; the menu-bar app keeps running.
        AppCommands.closeMainWindow()
        return false
    }

    private func existingOrCreate() -> NSWindow {
        if let window { return window }

        let appState = AppState.shared
        let root = RootView()
            .environmentObject(appState)
            .environmentObject(appState.engine)
            .environmentObject(appState.profiles)
            .environmentObject(appState.karabiner)
            .environmentObject(AppearanceStore.shared)
            .frame(minWidth: 980, minHeight: 640)
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: root)
        let frame = NSRect(x: 0, y: 0, width: 1100, height: 720)
        hosting.frame = frame

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        w.title = "HyperForge"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.minSize = NSSize(width: 980, height: 640)
        w.contentView = hosting
        w.delegate = self
        w.center()
        w.identifier = NSUserInterfaceItemIdentifier(
            DashboardWindowPolicy.dashboardIdentifier
        )
        window = w
        return w
    }
}
