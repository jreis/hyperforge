// DoctorView.swift
// Setup health: Accessibility, engine, Karabiner Hyper style, F19/F20 bridges.

import SwiftUI

struct DoctorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine
    @EnvironmentObject private var karabiner: KarabinerService
    @ObservedObject private var ollama = OllamaClient.shared
    @ObservedObject private var terminal = TerminalPreference.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overallCard
                checksCard
                hyperStyleCard
                actionsCard
                tipsCard
            }
            .padding(24)
        }
        .background(GlassBackground())
        .onAppear {
            karabiner.refresh()
            appState.isAccessibilityTrusted = PermissionsService.isTrusted
            Task { await ollama.ping() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Doctor")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(HFTheme.textPrimary)
            Text("Quick health check for HyperForge setup — Accessibility, Karabiner, Hyper style.")
                .font(.system(size: 13))
                .foregroundStyle(HFTheme.textSecondary)
        }
    }

    private var overallCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: overallOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(overallOK ? HFTheme.success : HFTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(overallOK ? "Ready to Hyper" : "Needs attention")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(overallSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(HFTheme.textSecondary)
                }
                Spacer()
                Button("Re-check") {
                    karabiner.refresh()
                    appState.isAccessibilityTrusted = PermissionsService.isTrusted
                    Task { await ollama.ping() }
                }
                .controlSize(.small)
            }
        }
    }

    private var checksCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Checks")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textSecondary)

                checkRow(
                    ok: appState.isAccessibilityTrusted,
                    title: "Accessibility",
                    detail: appState.isAccessibilityTrusted
                        ? "Trusted — event tap can run"
                        : "Grant access so HyperForge can observe keys and move windows",
                    fix: appState.isAccessibilityTrusted
                        ? nil
                        : {
                            PermissionsService.requestTrust()
                            PermissionsService.openSystemSettings()
                        }
                )

                checkRow(
                    ok: engine.isRunning,
                    title: "Engine",
                    detail: engine.isRunning
                        ? engine.statusMessage
                        : "Stopped — start from the sidebar or menu bar",
                    fix: engine.isRunning
                        ? nil
                        : { engine.start() }
                )

                checkRow(
                    ok: karabiner.isInstalled,
                    title: "Karabiner-Elements",
                    detail: karabiner.isInstalled
                        ? "Config found\(karabiner.activeProfileName.map { " · profile “\($0)”" } ?? "")"
                        : "Install Karabiner-Elements to map Caps → Hyper",
                    fix: karabiner.isInstalled
                        ? nil
                        : { karabiner.openKarabinerSettings() }
                )

                checkRow(
                    ok: karabiner.ruleStatus.hasAnyCapsHyper,
                    title: "Caps → Hyper rule",
                    detail: karabiner.ruleStatus.hasAnyCapsHyper
                        ? karabiner.ruleStatus.summary
                        : "No Caps Hyper rule detected in config or assets",
                    fix: karabiner.ruleStatus.hasAnyCapsHyper
                        ? nil
                        : {
                            _ = karabiner.installRecommendedPack()
                            Banner.show("Pack written — enable in Karabiner")
                        }
                )

                checkRow(
                    ok: karabiner.ruleStatus.helpF19 || karabiner.hyperStyle == .f18,
                    title: "Help chord (Hyper + /)",
                    detail: helpDetail,
                    fix: (karabiner.ruleStatus.helpF19 || karabiner.hyperStyle == .f18)
                        ? nil
                        : {
                            _ = karabiner.installBridgeRules()
                            Banner.show("F19/F20 assets written")
                            karabiner.refresh()
                        }
                )

                checkRow(
                    ok: karabiner.ruleStatus.dashboardF20 || karabiner.hyperStyle == .f18,
                    title: "Dashboard chord (Hyper + ,)",
                    detail: dashboardDetail,
                    fix: (karabiner.ruleStatus.dashboardF20 || karabiner.hyperStyle == .f18)
                        ? nil
                        : {
                            _ = karabiner.installBridgeRules()
                            Banner.show("F19/F20 assets written")
                            karabiner.refresh()
                        }
                )

                checkRow(
                    ok: true,
                    title: "Preferred terminal",
                    detail: "\(terminal.current.name) · \(terminal.reuseMode.title)",
                    fix: nil,
                    neutral: true
                )

                checkRow(
                    ok: !ollama.enabled || ollama.isAvailable,
                    title: "Local AI (Ollama)",
                    detail: ollama.enabled
                        ? (ollama.isAvailable ? "Reachable · \(ollama.model)" : "Enabled but offline — offline router still works")
                        : "Optional — disabled",
                    fix: (ollama.enabled && !ollama.isAvailable)
                        ? { Task { await ollama.ping() } }
                        : nil,
                    neutral: !ollama.enabled
                )
            }
        }
    }

    private var hyperStyleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: karabiner.hyperStyle.symbol)
                        .foregroundStyle(HFTheme.accent)
                    Text("Detected Hyper style")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textSecondary)
                    Spacer()
                    Text(karabiner.hyperStyle.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(karabiner.hyperStyle.isHealthy ? HFTheme.success : HFTheme.warning)
                }
                Text(karabiner.hyperStyle.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(HFTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if karabiner.hyperStyle == .quadMod {
                    Text("With 4-mod Hyper, enable the F19 and F20 bridge rules so Hyper+/ and Hyper+, always work.")
                        .font(.system(size: 11))
                        .foregroundStyle(HFTheme.textTertiary)
                }
            }
        }
    }

    private var actionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fix-it actions")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textSecondary)

                HStack(spacing: 10) {
                    Button {
                        _ = karabiner.installRecommendedPack()
                        Banner.show(
                            "HyperForge pack written",
                            subtitle: "Enable under Karabiner → Complex Modifications",
                            style: .success,
                            symbol: "checkmark.seal"
                        )
                        karabiner.refresh()
                    } label: {
                        Label("Install recommended pack", systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HFTheme.accent)

                    Button("Open Karabiner") {
                        karabiner.openKarabinerSettings()
                    }

                    Button("Assets folder") {
                        karabiner.openAssetsFolder()
                    }
                }

                Button {
                    PermissionsService.requestTrust()
                    PermissionsService.openSystemSettings()
                } label: {
                    Label("Open Accessibility settings", systemImage: "hand.raised")
                }
            }
        }
    }

    private var tipsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("After installing assets")
                    .font(.system(size: 13, weight: .semibold))
                tip("Open Karabiner-Elements → Complex Modifications → Add rule")
                tip("Enable “Caps Lock to F18” (or your existing 4-mod Caps rule)")
                tip("Enable “Hyper + / help (F19)” and “Hyper + , dashboard (F20)” if using 4-mod Hyper")
                tip("Hold Caps + key for actions · tap Caps alone for Escape")
                tip("Menu bar flame → Keybindings always works without chords")
            }
        }
    }

    // MARK: - Helpers

    private var overallOK: Bool {
        appState.isAccessibilityTrusted
            && engine.isRunning
            && karabiner.isInstalled
            && karabiner.ruleStatus.hasAnyCapsHyper
    }

    private var overallSummary: String {
        if overallOK {
            if karabiner.hyperStyle == .quadMod, !karabiner.ruleStatus.helpF19 {
                return "Core is good — add F19/F20 bridges for reliable help & dashboard chords."
            }
            return "Accessibility, engine, and Caps Hyper look good."
        }
        var missing: [String] = []
        if !appState.isAccessibilityTrusted { missing.append("Accessibility") }
        if !engine.isRunning { missing.append("engine") }
        if !karabiner.isInstalled { missing.append("Karabiner") }
        else if !karabiner.ruleStatus.hasAnyCapsHyper { missing.append("Caps→Hyper rule") }
        return "Missing: " + missing.joined(separator: ", ")
    }

    private var helpDetail: String {
        if karabiner.ruleStatus.helpF19 {
            return "F19 bridge detected — Hyper+/ should open the cheat sheet"
        }
        if karabiner.hyperStyle == .f18 {
            return "F18 style — Hyper+⇧/ or Hyper+` open help; plain / can be link hints"
        }
        return "Recommended for 4-mod Hyper: install F19 bridge"
    }

    private var dashboardDetail: String {
        if karabiner.ruleStatus.dashboardF20 {
            return "F20 bridge detected — Hyper+, should open the dashboard"
        }
        if karabiner.hyperStyle == .f18 {
            return "F18 style — Hyper+, works from the engine (menu bar also works)"
        }
        return "Recommended for 4-mod Hyper: install F20 bridge"
    }

    private func checkRow(
        ok: Bool,
        title: String,
        detail: String,
        fix: (() -> Void)?,
        neutral: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: neutral ? "circle.fill" : (ok ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(neutral ? HFTheme.textTertiary : (ok ? HFTheme.success : HFTheme.danger))
                .font(.system(size: 14))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let fix, !ok {
                Button("Fix") { fix() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(HFTheme.accent)
                .padding(.top, 4)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
        }
    }
}
