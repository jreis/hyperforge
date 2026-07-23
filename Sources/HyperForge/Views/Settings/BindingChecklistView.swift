// BindingChecklistView.swift
// Manual QA for every Hyper chord — Test fires action, check marks verified.

import HyperForgeKit
import SwiftUI

struct BindingChecklistView: View {
    @ObservedObject private var store = BindingChecklistStore.shared
    @State private var filter = ""
    @State private var onlyUnverified = false

    private var specs: [HyperBindingSpec] {
        var list = HyperBindingResolver.specs
        if onlyUnverified {
            list = list.filter { !store.isVerified($0) }
        }
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.actionID.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                progressCard
                filterBar
                listCard
                notesCard
            }
            .padding(24)
        }
        .background(GlassBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Binding Checklist")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(
                "Automated tests cover routing (what Hyper+key resolves to). "
                    + "Double-click a row (or press Test) to fire the action."
            )
            .font(.system(size: 13))
            .foregroundStyle(HFTheme.textSecondary)
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(store.verifiedCount) / \(store.total) verified")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("Reset") { store.resetAll() }
                        .controlSize(.small)
                }
                ProgressView(value: store.progress)
                    .tint(HFTheme.accent)
            }
        }
    }

    private var filterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HFTheme.textTertiary)
            TextField("Filter…", text: $filter)
                .textFieldStyle(.plain)
            Toggle("Unverified only", isOn: $onlyUnverified)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }

    private var listCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(specs) { spec in
                    HStack(spacing: 10) {
                        Button {
                            store.toggle(spec)
                        } label: {
                            Image(
                                systemName: store.isVerified(spec)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                store.isVerified(spec) ? HFTheme.success : HFTheme.textTertiary
                            )
                            .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)
                        .help("Mark verified / unverified")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.title)
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 6) {
                                Text(spec.actionID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(HFTheme.textTertiary)
                                if spec.requiresExtraShift {
                                    Text("needs F18+⇧")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(HFTheme.warning)
                                }
                            }
                        }
                        Spacer()
                        Button("Test") {
                            runTest(spec)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        runTest(spec)
                    }
                    .help("Double-click row to Test")
                    if spec.id != specs.last?.id {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
    }

    private func runTest(_ spec: HyperBindingSpec) {
        HyperKeyActions.perform(actionID: spec.actionID)
        // Mark verified after intentional test; user can uncheck if it failed.
        store.markVerified(spec)
    }

    private var notesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("What automation covers")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    "• `swift run HyperForgeSmoke` — pure routing for every Hyper chord "
                        + "(including 4-mod Hyper+T → terminal, not Desktop)."
                )
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
                Text(
                    "• Side effects (window moved, app focused, clipboard written) still need a human or UI tests with Accessibility."
                )
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
                Text(
                    "• Shift variants (F18+⇧) are marked “needs F18+⇧” — they never fire on pure 4-mod Hyper."
                )
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
            }
        }
    }
}

