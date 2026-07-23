// SettingsView.swift
// Tabbed settings for engine, privacy, and appearance.

import HyperForgeKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine

    @ObservedObject private var ollama = OllamaClient.shared
    @ObservedObject private var terminal = TerminalPreference.shared

    @ObservedObject private var spaceNav = SpaceNavStore.shared
    @State private var manualBlockBundle = ""
    @State private var manualBlockName = ""

    var body: some View {
        TabView {
            engineTab
                .tabItem { Label("Engine", systemImage: "flame") }
            appsTab
                .tabItem { Label("Apps", systemImage: "app.badge") }
            aiTab
                .tabItem { Label("Local AI", systemImage: "brain") }
            privacyTab
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassBackground())
    }

    private var appsTab: some View {
        Form {
            Section("Preferred terminal") {
                Picker("Terminal", selection: $terminal.bundleID) {
                    ForEach(terminal.installedOptions) { opt in
                        Label(opt.name, systemImage: opt.symbol)
                            .tag(opt.bundleID)
                    }
                }
                Text("Used by Hyper+T, Hyper+⇧T (folder), notes → nvim, and clipboard → editor.")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)

                Picker("If already running, Hyper+T", selection: $terminal.reuseMode) {
                    ForEach(TerminalReuseMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(terminal.reuseMode.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)

                HStack {
                    Text("Current: \(terminal.current.name)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Test tab") {
                        terminal.openNewTab()
                    }
                    .controlSize(.small)
                    Button("Test window") {
                        terminal.openNewWindow(force: true)
                    }
                    .controlSize(.small)
                    Button("Detect") {
                        terminal.bundleID = TerminalPreference.detectDefault().bundleID
                    }
                    .controlSize(.small)
                }
            }
            Section("Installed") {
                ForEach(TerminalAppOption.presets.filter { terminal.isInstalled($0.bundleID) }) { opt in
                    Label(opt.name, systemImage: opt.symbol)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aiTab: some View {
        Form {
            Section("Ollama (localhost only)") {
                Toggle("Enable Ollama for command bar", isOn: $ollama.enabled)
                    .onChange(of: ollama.enabled) { _, _ in ollama.persistSettings() }
                TextField("Base URL", text: $ollama.baseURLString)
                    .onSubmit {
                        ollama.persistSettings()
                        Task { await ollama.ping() }
                    }
                TextField("Model", text: $ollama.model)
                    .onSubmit {
                        ollama.persistSettings()
                        Task { await ollama.ping() }
                    }
                    .onChange(of: ollama.model) { _, _ in
                        ollama.refreshModelFit()
                    }
                if !ollama.installedModels.isEmpty {
                    Picker("Installed", selection: $ollama.model) {
                        ForEach(ollama.installedModels, id: \.name) { m in
                            Text(m.name).tag(m.name)
                        }
                    }
                    .onChange(of: ollama.model) { _, _ in
                        ollama.persistSettings()
                        ollama.refreshModelFit()
                    }
                }
                HStack {
                    Image(systemName: ollama.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ollama.isAvailable ? HFTheme.success : HFTheme.danger)
                    Text(ollama.isAvailable ? "Reachable" : "Offline — router still works")
                    Spacer()
                    Button("Ping") {
                        Task { await ollama.ping() }
                    }
                }
                modelFitRow
                if let err = ollama.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(HFTheme.textTertiary)
                }
            }
            Section("Tips") {
                Text(aiTip)
                    .font(.system(size: 12))
                    .foregroundStyle(HFTheme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task {
            if ollama.enabled {
                await ollama.ping()
            }
        }
    }

    @ViewBuilder
    private var modelFitRow: some View {
        let fit = ollama.modelFit
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: modelFitSymbol(fit.level))
                    .foregroundStyle(modelFitColor(fit.level))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fit.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text(fit.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HFTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: "This Mac · ~%.0f GB RAM", ollama.physicalMemoryGB))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HFTheme.textTertiary)
                }
            }
            if fit.isWarning, let suggestion = fit.suggestion, suggestion != ollama.model {
                Button("Use suggested \(suggestion)") {
                    ollama.model = suggestion
                    ollama.persistSettings()
                    Task { await ollama.ping() }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var aiTip: String {
        let suggested = ModelFitness.suggestedModel(forRAMGB: ollama.physicalMemoryGB)
        return "Install Ollama and pull a model that fits this Mac (`ollama pull \(suggested)`). HyperForge never sends prompts off-machine. Without Ollama, the offline intent router still handles phrases like “snap left” and “half-page scroll”."
    }

    private func modelFitSymbol(_ level: ModelFitLevel) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .tooLarge: return "xmark.octagon.fill"
        case .notInstalled: return "questionmark.circle.fill"
        case .unknown: return "info.circle"
        }
    }

    private func modelFitColor(_ level: ModelFitLevel) -> Color {
        switch level {
        case .ok: return HFTheme.success
        case .tight: return HFTheme.warning
        case .tooLarge: return HFTheme.danger
        case .notInstalled: return HFTheme.warning
        case .unknown: return HFTheme.textTertiary
        }
    }

    private var engineTab: some View {
        Form {
            Section("Startup") {
                Toggle("Start engine on launch", isOn: $appState.launchEngineOnStart)
                Toggle("Show dashboard on startup", isOn: $appState.showDashboardOnStartup)
                Text("When off, HyperForge stays in the menu bar until you open the dashboard (Hyper + , or menu).")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
                Toggle("Auto keep-alive", isOn: $appState.autoKeepAlive)
                Toggle("Menu bar only (no Dock icon)", isOn: $appState.menuBarOnly)
            }
            Section("Space navigation") {
                Toggle("Space-layer nav (TouchCursor-style)", isOn: $spaceNav.isEnabled)
                Text("Hold Space + H/J/K/L for arrows and other motions. Tap Space alone still types a space. Hyper+Space is still the command bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hold before layer")
                        Spacer()
                        Text(spaceNav.holdMilliseconds == 0
                             ? "Immediate (power)"
                             : "\(spaceNav.holdMilliseconds) ms")
                            .foregroundStyle(HFTheme.textTertiary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(spaceNav.holdMilliseconds) },
                            set: { spaceNav.holdMilliseconds = Int($0) }
                        ),
                        in: 0...300,
                        step: 10
                    )
                    HStack(spacing: 8) {
                        Button("Typing-safe 160") { spaceNav.holdMilliseconds = 160 }
                            .controlSize(.mini)
                        Button("Relaxed 200") { spaceNav.holdMilliseconds = 200 }
                            .controlSize(.mini)
                        Button("Instant 0") { spaceNav.holdMilliseconds = 0 }
                            .controlSize(.mini)
                    }
                    Text("Space must be held this long before HJKL (etc.) act as navigation. Keys pressed sooner type a normal space + letter — better for fast typists. Instant (0) arms the layer on key-down (old behavior).")
                        .font(.system(size: 11))
                        .foregroundStyle(HFTheme.textTertiary)
                }

                Text("Disabled in apps")
                    .font(.system(size: 12, weight: .semibold))
                Text("Space types normally in these apps (terminals, Vim, …). Also settable per App Override.")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)

                ForEach(spaceNav.blockedApps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.displayTitle)
                                .font(.system(size: 12, weight: .medium))
                            Text(app.bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HFTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            spaceNav.remove(app)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(HFTheme.danger.opacity(0.85))
                    }
                }

                HStack {
                    Button {
                        spaceNav.addFrontmost()
                    } label: {
                        Label("Block frontmost", systemImage: "plus.app")
                    }
                    .controlSize(.small)
                    Button("Restore defaults") {
                        spaceNav.restoreDefaultBlockedApps()
                    }
                    .controlSize(.small)
                }

                HStack {
                    TextField("Bundle ID", text: $manualBlockBundle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    TextField("Name", text: $manualBlockName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                    Button("Add") {
                        spaceNav.add(bundleID: manualBlockBundle, appName: manualBlockName)
                        manualBlockBundle = ""
                        manualBlockName = ""
                    }
                    .controlSize(.small)
                    .disabled(manualBlockBundle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Permissions") {
                HStack {
                    Image(systemName: appState.isAccessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.isAccessibilityTrusted ? HFTheme.success : HFTheme.danger)
                    Text(appState.isAccessibilityTrusted ? "Accessibility granted" : "Accessibility missing")
                    Spacer()
                    Button("Request…") { PermissionsService.requestTrust() }
                    Button("System Settings") { PermissionsService.openSystemSettings() }
                }
                Button {
                    appState.selectedSidebar = .doctor
                } label: {
                    Label("Open Doctor for full setup check", systemImage: "stethoscope")
                }
            }
            Section("Engine") {
                LabeledContent("Status", value: engine.statusMessage)
                LabeledContent("Running", value: engine.isRunning ? "Yes" : "No")
                Button(engine.isRunning ? "Stop" : "Start") {
                    if engine.isRunning { engine.stop() } else { engine.start() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            Section {
                Text("HyperForge is local-first. Key events never leave your machine. AI command bar (when enabled) talks only to local Ollama/MLX.")
                    .font(.system(size: 12))
                    .foregroundStyle(HFTheme.textSecondary)
            }
            Section("Backup") {
                Text("Export a single JSON pack: profiles, snippets, app overrides, Space nav, terminal, Ollama prefs, and checklist. Import replaces those on this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
                HStack {
                    Button {
                        _ = ConfigBackupService.exportWithSavePanel()
                    } label: {
                        Label("Export config…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        _ = ConfigBackupService.importWithOpenPanel()
                    } label: {
                        Label("Import config…", systemImage: "square.and.arrow.down")
                    }
                }
            }
            Section("Logs") {
                LabeledContent("Event log", value: HyperLog.path)
                Toggle("Write event log", isOn: Binding(
                    get: { HyperLog.enabled },
                    set: { HyperLog.enabled = $0 }
                ))
                Text("Off by default. Enabling logs every Hyper event to disk — can slow typing if left on.")
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.largeTitle)
                    .foregroundStyle(HFTheme.accent)
                VStack(alignment: .leading) {
                    Text("HyperForge")
                        .font(.title2.bold())
                    Text("v0.3.0 · Local-first automation forge")
                        .foregroundStyle(HFTheme.textSecondary)
                }
            }
            Text("Built for restricted environments where Hammerspoon and browser extensions are blocked — without giving up power-user flow.")
                .font(.system(size: 13))
                .foregroundStyle(HFTheme.textSecondary)
            Text("Hyper+Space command bar · Hyper+/ help (F19) · profiles · Doctor · F18 or 4-mod Hyper")
                .font(.system(size: 11))
                .foregroundStyle(HFTheme.textTertiary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
