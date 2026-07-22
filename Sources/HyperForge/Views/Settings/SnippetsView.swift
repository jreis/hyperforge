// SnippetsView.swift
// Manage text expansions (hotstrings).

import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetStore.shared
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Snippets")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textPrimary)
                        Text("Type a trigger anywhere — expands locally (AHK hotstring style).")
                            .font(.system(size: 13))
                            .foregroundStyle(HFTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: $store.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tokens: {{date}} · {{clipboard}} · {{hostname}} · use \\n for newlines")
                            .font(.system(size: 11))
                            .foregroundStyle(HFTheme.textTertiary)
                        TextField("Trigger (e.g. ,sig)", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("Expansion", text: $expansion, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        TextField("Note", text: $note)
                            .textFieldStyle(.roundedBorder)
                        Button("Add Snippet") {
                            guard !trigger.isEmpty, !expansion.isEmpty else { return }
                            store.add(TextSnippet(trigger: trigger, expansion: expansion, note: note))
                            trigger = ""
                            expansion = ""
                            note = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.accent)
                        .disabled(trigger.isEmpty || expansion.isEmpty)
                    }
                }

                ForEach(store.snippets) { snip in
                    GlassCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    KeyCap(text: snip.trigger, compact: true)
                                    if !snip.note.isEmpty {
                                        Text(snip.note)
                                            .font(.caption)
                                            .foregroundStyle(HFTheme.textTertiary)
                                    }
                                }
                                Text(snip.expansion.replacingOccurrences(of: "\n", with: "↵"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HFTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { snip.isEnabled },
                                    set: { v in
                                        var s = snip
                                        s.isEnabled = v
                                        store.update(s)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Button(role: .destructive) {
                                store.delete(snip)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HFTheme.danger.opacity(0.8))
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
