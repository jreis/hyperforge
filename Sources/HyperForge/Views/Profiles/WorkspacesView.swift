// WorkspacesView.swift
// Save / restore window layouts via Accessibility.

import SwiftUI

struct WorkspacesView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @State private var layoutName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Workspaces")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Capture and restore window arrangements for “\(profiles.activeProfile.name)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)

                GlassCard {
                    HStack {
                        TextField("Layout name (e.g. Dual Code)", text: $layoutName)
                            .textFieldStyle(.plain)
                        Button("Save Current Layout") {
                            guard !layoutName.isEmpty else { return }
                            profiles.saveCurrentLayout(named: layoutName)
                            layoutName = ""
                            Banner.show("Layout saved")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.accent)
                        .disabled(layoutName.isEmpty)
                    }
                }

                if profiles.activeProfile.layouts.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group")
                                .font(.largeTitle)
                                .foregroundStyle(HFTheme.textTertiary)
                            Text("No layouts yet")
                                .font(.headline)
                                .foregroundStyle(HFTheme.textSecondary)
                            Text("Arrange your windows, name the layout, then save.")
                                .font(.caption)
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    ForEach(profiles.activeProfile.layouts) { layout in
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(layout.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(HFTheme.textPrimary)
                                    Text("\(layout.windows.count) windows · \(layout.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(HFTheme.textTertiary)
                                }
                                Spacer()
                                Button("Restore") {
                                    profiles.restoreLayout(layout)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
