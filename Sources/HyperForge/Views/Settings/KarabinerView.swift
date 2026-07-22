// KarabinerView.swift
// Manage Caps→Hyper rules, F19/F20 bridges, and complex_modifications JSON.

import SwiftUI

struct KarabinerView: View {
    @EnvironmentObject private var karabiner: KarabinerService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Karabiner")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("HyperForge supports two Caps Hyper styles. Pick one, then add F19/F20 bridges if you use 4-mod Hyper.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)

                GlassCard {
                    HStack {
                        Image(systemName: karabiner.isInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(karabiner.isInstalled ? HFTheme.success : HFTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(karabiner.isInstalled ? "Karabiner config detected" : "Karabiner-Elements not found")
                                .font(.system(size: 14, weight: .semibold))
                            Text(karabiner.status)
                                .font(.system(size: 11))
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                        Spacer()
                        Button("Refresh") { karabiner.refresh() }
                            .controlSize(.small)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hyper styles")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textSecondary)

                        styleRow(
                            title: "F18 (recommended for HyperForge)",
                            body: "Caps → F18, alone = Escape. Engine listens for F18. Help: Hyper+⇧/ or Hyper+`. Link hints: plain Hyper+/."
                        )
                        styleRow(
                            title: "4-mod (⌘⌃⌥⇧)",
                            body: "Caps → all four modifiers, alone = Escape. Common community rule. Shift is always held, so install F19 (help) and F20 (dashboard) bridges."
                        )

                        HStack(spacing: 8) {
                            Image(systemName: karabiner.hyperStyle.symbol)
                                .foregroundStyle(HFTheme.accent)
                            Text("Detected: \(karabiner.hyperStyle.rawValue)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(karabiner.hyperStyle.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(HFTheme.textTertiary)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Install packs")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textSecondary)

                        Text("Writes JSON assets under ~/.config/karabiner/assets/complex_modifications/. Enable them in Karabiner → Complex Modifications.")
                            .font(.system(size: 11))
                            .foregroundStyle(HFTheme.textTertiary)

                        HStack {
                            Button {
                                _ = karabiner.installRecommendedPack()
                                Banner.show(
                                    "Recommended pack written",
                                    subtitle: "Caps→F18 + F19 help + F20 dashboard",
                                    style: .success
                                )
                            } label: {
                                Label("Install recommended pack", systemImage: "square.and.arrow.down.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.accent)

                            Button {
                                _ = karabiner.installCapsToF18Rule()
                                Banner.show("Caps→F18 asset written")
                            } label: {
                                Label("Caps→F18 only", systemImage: "f.circle")
                            }

                            Button {
                                _ = karabiner.installBridgeRules()
                                Banner.show("F19 + F20 bridge assets written")
                            } label: {
                                Label("F19/F20 bridges", systemImage: "arrow.triangle.branch")
                            }
                        }

                        HStack {
                            Button("Open Karabiner") {
                                karabiner.openKarabinerSettings()
                            }
                            Button("Open assets folder") {
                                karabiner.openAssetsFolder()
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom rule editor")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textSecondary)
                        TextEditor(text: $karabiner.ruleJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

                        Button {
                            _ = karabiner.installCustomRuleAsset()
                            Banner.show("Custom rule asset written")
                        } label: {
                            Label("Install editor JSON as asset", systemImage: "square.and.arrow.down")
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup checklist")
                            .font(.system(size: 13, weight: .semibold))
                        checklist("Install Karabiner-Elements")
                        checklist("Enable one Caps Hyper rule (F18 or 4-mod) under Complex Modifications")
                        checklist("If using 4-mod: enable Hyper+/ → F19 and Hyper+, → F20")
                        checklist("Grant Accessibility to HyperForge (Doctor sidebar)")
                        checklist("Hold Caps + key → Hyper action; tap Caps alone → Escape")
                    }
                }
            }
            .padding(24)
        }
        .onAppear { karabiner.refresh() }
    }

    private func styleRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(HFTheme.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func checklist(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(HFTheme.accent)
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
        }
    }
}
