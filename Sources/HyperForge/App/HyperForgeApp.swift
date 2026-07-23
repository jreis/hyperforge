// HyperForgeApp.swift
// Entry point — menu bar companion + main window.

import AppKit
import SwiftUI

@main
struct HyperForgeApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.engine)
                .environmentObject(appState.profiles)
                .environmentObject(appState.karabiner)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(WindowOpenBridge())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("HyperForge") {
                Button("Show Dashboard") {
                    appState.selectedSidebar = .dashboard
                    appState.openMainWindow()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Hide Dashboard") {
                    appState.closeMainWindow()
                }
                // Esc is owned by EscapeCoordinator (pins → hints → bar → sheet → dashboard).

                Button(appState.engine.isRunning ? "Stop Engine" : "Start Engine") {
                    if appState.engine.isRunning {
                        appState.engine.stop()
                    } else {
                        appState.engine.start()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Command Bar…") {
                    appState.commandBarVisible = true
                    appState.openMainWindow()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Keybinding Cheat Sheet…") {
                    CheatSheetCommands.toggle()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.engine)
                .environmentObject(appState.profiles)
                .environmentObject(appState.karabiner)
                .preferredColorScheme(.dark)
                .frame(width: 520, height: 420)
        }

        MenuBarExtra("HyperForge", systemImage: menuBarSymbol) {
            MenuBarPopover()
                .environmentObject(appState)
                .environmentObject(appState.engine)
                .environmentObject(appState.profiles)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        appState.engine.isRunning
            ? (appState.engine.hyperKeyActive ? "flame.fill" : "flame")
            : "flame"
    }
}

/// AppKit glue: single-instance, accessory policy, bootstrap.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when this process is a secondary launch and should exit.
    private var isSecondaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before engine / menu bar / event tap: hand off to the live copy if any.
        if !SingleInstance.claimPrimaryOrHandOff() {
            isSecondaryInstance = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isSecondaryInstance {
            // Hard exit so we never install a second CGEvent tap.
            exit(0)
        }

        // Menu bar first-class; dock optional later via settings.
        if UserDefaults.standard.object(forKey: "hf.menuBarOnly") as? Bool ?? true {
            NSApp.setActivationPolicy(.accessory)
        }

        SingleInstance.installPrimaryHandlers()

        Task { @MainActor in
            AppState.shared.bootstrap()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        // Dock icon / second "open" of the same process → show dashboard.
        Task { @MainActor in
            AppState.shared.openMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app: closing the dashboard must not quit.
        false
    }
}
