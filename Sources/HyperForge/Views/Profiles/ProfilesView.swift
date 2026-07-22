// ProfilesView.swift
// Create / switch work profiles that bundle Hyper action sets.

import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @State private var newName = ""
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(profiles.profiles) { profile in
                        ProfileCard(
                            profile: profile,
                            isActive: profile.id == profiles.activeProfileID
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                profiles.select(profile)
                            }
                            Banner.show("Profile: \(profile.name)")
                        } onDelete: {
                            profiles.delete(profile)
                        }
                    }
                }

                if showNew {
                    GlassCard {
                        HStack {
                            TextField("Profile name", text: $newName)
                                .textFieldStyle(.plain)
                            Button("Create") {
                                guard !newName.isEmpty else { return }
                                let p = HyperProfile(
                                    name: newName,
                                    symbol: "sparkles",
                                    accentHex: 0x64D2FF,
                                    notes: "Custom profile",
                                    enabledActionIDs: [],
                                    layouts: [],
                                    karabinerRuleJSON: HyperProfile.defaultKarabiner,
                                    isBuiltIn: false
                                )
                                profiles.add(p)
                                profiles.select(p)
                                newName = ""
                                showNew = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.accent)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Bundle Hyper actions, layouts, and Karabiner rules.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)
            }
            Spacer()
            Button {
                showNew.toggle()
            } label: {
                Label("New Profile", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(HFTheme.accent)
        }
    }
}

struct ProfileCard: View {
    let profile: HyperProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: profile.symbol)
                            .font(.title2)
                            .foregroundStyle(Color(hex: profile.accentHex))
                        Spacer()
                        if isActive {
                            StatusPill(title: "Active", color: HFTheme.success, pulse: true)
                        }
                    }
                    Text(profile.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text(profile.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(HFTheme.textSecondary)
                        .lineLimit(2)
                    HStack {
                        let count =
                            profile.enabledActionIDs.isEmpty
                            ? ActionCatalog.defaults.count
                            : profile.enabledActionIDs.count
                        Label("\(count) actions", systemImage: "keyboard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HFTheme.textTertiary)
                        Spacer()
                        if !profile.isBuiltIn {
                            Button(role: .destructive, action: onDelete) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HFTheme.danger.opacity(0.8))
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                    .strokeBorder(
                        isActive ? Color(hex: profile.accentHex).opacity(0.55) : .clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
