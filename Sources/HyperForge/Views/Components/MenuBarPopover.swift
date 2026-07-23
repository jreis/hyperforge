// MenuBarPopover.swift
// Compact menu bar surface for quick status and actions.

import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine
    @EnvironmentObject private var profiles: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(HFTheme.accent)
                Text("HyperForge")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                StatusPill(
                    title: engine.isRunning ? "Live" : "Off",
                    color: engine.isRunning ? HFTheme.success : HFTheme.danger,
                    pulse: engine.hyperKeyActive
                )
            }

            Text(engine.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(HFTheme.textTertiary)

            Divider()

            Menu("Profile: \(profiles.activeProfile.name)") {
                ForEach(profiles.profiles) { p in
                    Button(p.name) {
                        DispatchQueue.main.async { ProfileStore.shared.select(p) }
                    }
                }
            }

            Button {
                DispatchQueue.main.async {
                    if HyperKeyEngine.shared.isRunning {
                        HyperKeyEngine.shared.stop()
                    } else {
                        HyperKeyEngine.shared.start()
                    }
                }
            } label: {
                Label(
                    engine.isRunning ? "Stop Engine" : "Start Engine",
                    systemImage: engine.isRunning ? "stop.fill" : "play.fill"
                )
            }

            Button {
                DispatchQueue.main.async { KeepAliveService.shared.toggle() }
            } label: {
                Label(
                    KeepAliveService.shared.isActive ? "Keep-Alive On" : "Keep-Alive Off",
                    systemImage: "bolt.heart"
                )
            }

            Button {
                // MenuBarExtra is always mounted — openWindow works even when the
                // dashboard WindowGroup was closed (WindowOpenBridge inside it is dead).
                DispatchQueue.main.async {
                    WindowOpener.shared.bind(openWindow)
                    openWindow(id: "main")
                    AppState.shared.openMainWindow()
                }
            } label: {
                Label("Open Dashboard", systemImage: "rectangle.center.inset.filled")
            }

            // MenuBarExtra button actions on macOS 26 / Swift 6 can crash if they
            // synchronously touch @MainActor state (MainActor.assumeIsolated).
            // Always hop via DispatchQueue / nonisolated helpers.
            Button {
                CheatSheetCommands.toggle()
            } label: {
                Label("Keybindings…", systemImage: "keyboard")
            }

            Button {
                DispatchQueue.main.async { QuickMenuService.show() }
            } label: {
                Label("Quick Menu", systemImage: "list.bullet.rectangle")
            }

            Button {
                DispatchQueue.main.async { PasteTransformService.showMenu() }
            } label: {
                Label("Paste Transforms…", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                DispatchQueue.main.async {
                    WindowOpener.shared.bind(openWindow)
                    openWindow(id: "main")
                    AppState.shared.selectedSidebar = .dashboard
                    AppState.shared.commandBarVisible = true
                    AppState.shared.openMainWindow()
                }
            } label: {
                Label("Command Bar", systemImage: "sparkles")
            }

            Button {
                DispatchQueue.main.async { LinkHintService.shared.toggle() }
            } label: {
                Label("Link Hints", systemImage: "link.circle")
            }

            Button {
                DispatchQueue.main.async {
                    _ = DemoExportService.shared.exportPortfolioPack()
                }
            } label: {
                Label("Export Demo Pack", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button("Quit HyperForge") {
                NSApp.terminate(nil)
            }
            .foregroundStyle(HFTheme.danger)
        }
        .padding(14)
        .frame(width: 280)
        .background(HFTheme.bgElevated)
        // Keep openWindow wired for Hyper+, / F20 even if main window is gone.
        .background(WindowOpenBridge())
        .onAppear {
            WindowOpener.shared.bind(openWindow)
        }
    }
}
