// SettingsView.swift
// Tabbed settings for engine, privacy, and appearance.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine

    @ObservedObject private var ollama = OllamaClient.shared
    @ObservedObject private var terminal = TerminalPreference.shared

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
                    .onSubmit { ollama.persistSettings() }
                TextField("Model", text: $ollama.model)
                    .onSubmit { ollama.persistSettings() }
                HStack {
                    Image(systemName: ollama.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ollama.isAvailable ? HFTheme.success : HFTheme.danger)
                    Text(ollama.isAvailable ? "Reachable" : "Offline — router still works")
                    Spacer()
                    Button("Ping") {
                        Task { await ollama.ping() }
                    }
                }
                if let err = ollama.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(HFTheme.textTertiary)
                }
            }
            Section("Tips") {
                Text("Install Ollama and pull a model (`ollama pull llama3.2`). HyperForge never sends prompts off-machine. Without Ollama, the offline intent router still handles phrases like “snap left” and “half-page scroll”.")
                    .font(.system(size: 12))
                    .foregroundStyle(HFTheme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var engineTab: some View {
        Form {
            Section("Startup") {
                Toggle("Start engine on launch", isOn: $appState.launchEngineOnStart)
                Toggle("Auto keep-alive", isOn: $appState.autoKeepAlive)
                Toggle("Menu bar only (no Dock icon)", isOn: $appState.menuBarOnly)
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
            Section("Logs") {
                LabeledContent("Event log", value: HyperLog.path)
                Toggle("Write event log", isOn: Binding(
                    get: { HyperLog.enabled },
                    set: { HyperLog.enabled = $0 }
                ))
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
