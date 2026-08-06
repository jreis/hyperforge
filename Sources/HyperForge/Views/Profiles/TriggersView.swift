// TriggersView.swift
// Auto-switch profiles by Wi‑Fi, frontmost app, or time window.

import SwiftUI

struct TriggersView: View {
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var service = AutoTriggerService.shared
    @ObservedObject private var recipes = AXRecipeStore.shared

    @State private var kind: AutoTrigger.Kind = .wifiSSID
    @State private var value = ""
    @State private var profileID: UUID?
    @State private var action: AutoTrigger.Action = .switchProfile
    @State private var recipeID: UUID?
    @State private var layoutID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                newTriggerCard
                list
            }
            .padding(24)
        }
        .onAppear {
            profileID = profiles.activeProfileID
            service.evaluate()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Triggers")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Switch profiles when context changes — fully local.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $service.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Live context", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HFTheme.accent)
                    Spacer()
                    Button("Re-evaluate") { service.evaluate() }
                        .controlSize(.small)
                }
                LabeledContent("Wi‑Fi") {
                    Text(service.currentSSID ?? "—")
                        .foregroundStyle(HFTheme.textSecondary)
                }
                LabeledContent("Frontmost app") {
                    Text(service.frontmostBundleID ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HFTheme.textSecondary)
                        .lineLimit(1)
                }
                if let match = service.lastMatchDescription {
                    Text(match)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HFTheme.success)
                }
            }
        }
    }

    /// Which profile's `layouts` to draw the restore-layout picker from.
    private var pickerProfileID: UUID { profileID ?? profiles.activeProfileID }

    private var newTriggerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("New trigger")
                    .font(.system(size: 13, weight: .semibold))
                Picker("When", selection: $kind) {
                    ForEach(AutoTrigger.Kind.allCases, id: \.self) { k in
                        Label(k.title, systemImage: k.symbol).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                TextField(kind.placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)

                Picker("Then", selection: $action) {
                    ForEach(AutoTrigger.Action.allCases, id: \.self) { a in
                        Label(a.title, systemImage: a.symbol).tag(a)
                    }
                }
                .pickerStyle(.segmented)

                switch action {
                case .switchProfile:
                    Picker("Activate profile", selection: Binding(
                        get: { pickerProfileID },
                        set: { profileID = $0 }
                    )) {
                        ForEach(profiles.profiles) { p in
                            Text(p.name).tag(p.id as UUID?)
                        }
                    }
                case .runRecipe:
                    Picker("Recipe", selection: $recipeID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(recipes.recipes) { r in
                            Text(r.name).tag(r.id as UUID?)
                        }
                    }
                case .restoreLayout:
                    Picker("Profile", selection: Binding(
                        get: { pickerProfileID },
                        set: {
                            profileID = $0
                            layoutID = nil
                        }
                    )) {
                        ForEach(profiles.profiles) { p in
                            Text(p.name).tag(p.id as UUID?)
                        }
                    }
                    let targetLayouts = profiles.profiles.first { $0.id == pickerProfileID }?.layouts ?? []
                    Picker("Layout", selection: $layoutID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(targetLayouts) { l in
                            Text(l.name).tag(l.id as UUID?)
                        }
                    }
                    .disabled(targetLayouts.isEmpty)
                }

                HStack {
                    if kind == .wifiSSID, let ssid = service.currentSSID {
                        Button("Use current Wi‑Fi") { value = ssid }
                            .controlSize(.small)
                    }
                    if kind == .appBundleID, let bid = service.frontmostBundleID {
                        Button("Use frontmost app") { value = bid }
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Add Trigger") {
                        guard !value.isEmpty else { return }
                        switch action {
                        case .switchProfile:
                            profiles.addTrigger(
                                AutoTrigger(kind: kind, value: value, profileID: pickerProfileID, action: .switchProfile)
                            )
                        case .runRecipe:
                            guard let recipeID else { return }
                            profiles.addTrigger(
                                AutoTrigger(
                                    kind: kind, value: value, profileID: profiles.activeProfileID,
                                    action: .runRecipe, recipeID: recipeID
                                )
                            )
                        case .restoreLayout:
                            guard let layoutID else { return }
                            profiles.addTrigger(
                                AutoTrigger(
                                    kind: kind, value: value, profileID: pickerProfileID,
                                    action: .restoreLayout, layoutID: layoutID
                                )
                            )
                        }
                        value = ""
                        recipeID = nil
                        layoutID = nil
                        Banner.show("Trigger added")
                        service.evaluate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HFTheme.accent)
                    .disabled(
                        value.isEmpty
                            || (action == .runRecipe && recipeID == nil)
                            || (action == .restoreLayout && layoutID == nil)
                    )
                }
            }
        }
    }

    private func actionSubtitle(for trigger: AutoTrigger) -> String {
        switch trigger.action {
        case .switchProfile:
            return "→ \(profiles.profiles.first { $0.id == trigger.profileID }?.name ?? "?")"
        case .runRecipe:
            let name = trigger.recipeID.flatMap { id in
                recipes.recipes.first { $0.id == id }?.name
            } ?? "?"
            return "→ Run recipe: \(name)"
        case .restoreLayout:
            let profile = profiles.profiles.first { $0.id == trigger.profileID }
            let name = trigger.layoutID.flatMap { id in
                profile?.layouts.first { $0.id == id }?.name
            } ?? "?"
            return "→ Restore: \(name)"
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            if profiles.autoTriggers.isEmpty {
                GlassCard {
                    Text("No triggers yet. Example: Wi‑Fi “Office” → Coding profile.")
                        .foregroundStyle(HFTheme.textTertiary)
                }
            } else {
                ForEach(profiles.autoTriggers) { trigger in
                    GlassCard(padding: 12) {
                        HStack {
                            Image(systemName: trigger.kind.symbol)
                                .foregroundStyle(HFTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(trigger.kind.title): \(trigger.value)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(actionSubtitle(for: trigger))
                                    .font(.system(size: 11))
                                    .foregroundStyle(HFTheme.textTertiary)
                            }
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { trigger.isEnabled },
                                    set: { newVal in
                                        var t = trigger
                                        t.isEnabled = newVal
                                        profiles.updateTrigger(t)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Button(role: .destructive) {
                                profiles.deleteTrigger(trigger)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HFTheme.danger.opacity(0.8))
                        }
                    }
                }
            }
        }
    }
}
