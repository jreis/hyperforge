// HyperForgeApp.swift
// Entry point — menu bar companion + main window.

import AppKit
import SwiftUI

@main
struct HyperForgeApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup — SwiftUI would create (and restore) a dashboard
        // window on every launch. The dashboard is an AppKit window shown
        // only from AppState.openMainWindow().

        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(appState)
                .environmentObject(appState.engine)
                .environmentObject(appState.profiles)
                .environmentObject(AppearanceStore.shared)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
        .commands {
            hyperForgeCommands
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.engine)
                .environmentObject(appState.profiles)
                .environmentObject(appState.karabiner)
                .environmentObject(AppearanceStore.shared)
                .preferredColorScheme(.dark)
                .frame(width: 520, height: 480)
        }
        .commandsRemoved()
    }

    @CommandsBuilder
    private var hyperForgeCommands: some Commands {
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

    private var menuBarSymbol: String {
        let infernal = AppearanceStore.shared.style == .infernal
        if !appState.engine.isRunning {
            return infernal ? "flame" : "flame"
        }
        // Space layer armed wins — instant “mode” feedback in the menu bar.
        if appState.engine.spaceLayerArmed {
            return "arrow.up.and.down.and.arrow.left.and.right"
        }
        if appState.engine.hyperKeyActive {
            return "flame.fill"
        }
        // Space held but not yet armed — soft cue.
        if appState.engine.spaceLayerHeld {
            return infernal ? "circle.fill" : "circle.dotted"
        }
        return infernal ? "flame.fill" : "flame"
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
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        if UserDefaults.standard.object(forKey: "hf.menuBarOnly") as? Bool ?? true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isSecondaryInstance {
            // Hard exit so we never install a second CGEvent tap.
            exit(0)
        }

        if UserDefaults.standard.object(forKey: "hf.menuBarOnly") as? Bool ?? true {
            NSApp.setActivationPolicy(.accessory)
        }

        SingleInstance.installPrimaryHandlers()

        Task { @MainActor in
            AppState.shared.bootstrap()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                URLTriggerService.handle(url)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if DashboardLaunchGate.suppressVisibleDashboard {
            return false
        }
        Task { @MainActor in
            AppState.shared.handleReopenRequest()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app: closing the dashboard must not quit.
        false
    }
}
