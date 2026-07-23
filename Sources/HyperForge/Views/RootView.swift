// RootView.swift
// Navigation shell: sidebar + detail, onboarding overlay.

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine
    @EnvironmentObject private var profiles: ProfileStore

    var body: some View {
        ZStack {
            GlassBackground()

            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.balanced)
            .background(.clear)

            if appState.showOnboarding {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if appState.commandBarVisible {
                CommandBarView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(20)
            }

        }
        .tint(HFTheme.accent)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: appState.showOnboarding)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: appState.commandBarVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: appState.cheatSheetVisible)
        // Esc: EscapeCoordinator priority stack (pins first … dashboard last).
        .onExitCommand {
            appState.handleDashboardEscape()
        }
        .background(DashboardEscapeMonitor())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [HFTheme.accent, HFTheme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("HyperForge")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text(profiles.activeProfile.name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(HFTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Status
            HStack(spacing: 8) {
                StatusPill(
                    title: engine.isRunning ? "Live" : "Stopped",
                    color: engine.isRunning ? HFTheme.success : HFTheme.danger,
                    pulse: engine.hyperKeyActive
                )
                if engine.hyperKeyActive {
                    StatusPill(title: "Hyper", color: HFTheme.accent, pulse: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            List(SidebarItem.allCases, selection: Binding(
                get: { appState.selectedSidebar },
                set: { appState.selectedSidebar = $0 }
            )) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
                    .font(.system(size: 13, weight: .medium))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            // Quick engine toggle
            Button {
                if engine.isRunning { engine.stop() } else { engine.start() }
            } label: {
                Label(
                    engine.isRunning ? "Stop Engine" : "Start Engine",
                    systemImage: engine.isRunning ? "stop.fill" : "play.fill"
                )
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(engine.isRunning ? HFTheme.danger.opacity(0.18) : HFTheme.accent.opacity(0.18))
            }
            .foregroundStyle(engine.isRunning ? HFTheme.danger : HFTheme.accent)
            .padding(16)
        }
        .background(HFTheme.bgElevated.opacity(0.55))
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedSidebar {
        case .dashboard:
            DashboardView()
        case .doctor:
            DoctorView()
        case .checklist:
            BindingChecklistView()
        case .profiles:
            ProfilesView()
        case .workspaces:
            WorkspacesView()
        case .snippets:
            SnippetsView()
        case .recipes:
            RecipesView()
        case .triggers:
            TriggersView()
        case .overrides:
            OverridesView()
        case .karabiner:
            KarabinerView()
        case .clipboard:
            ClipboardView()
        case .demo:
            DemoExportView()
        case .settings:
            SettingsView()
        }
    }
}
