// SnippetsView.swift
// Manage text expansions (hotstrings) — add, edit, enable, delete.

import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetStore.shared
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var note = ""
    /// When set, the form is editing this snippet instead of adding a new one.
    @State private var editingID: UUID?

    private var isEditing: Bool { editingID != nil }

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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date format")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Used by {{date}}. Override per snippet with {{date:MM/dd/yyyy}}.")
                            .font(.system(size: 11))
                            .foregroundStyle(HFTheme.textTertiary)

                        Picker("Preset", selection: datePresetBinding) {
                            ForEach(SnippetDateFormat.presets, id: \.id) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            TextField("Unicode format (e.g. yyyy-MM-dd)", text: $store.dateFormat)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Text(SnippetDateFormat.preview(format: store.dateFormat))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(HFTheme.accent)
                                .lineLimit(1)
                                .frame(minWidth: 120, alignment: .trailing)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isEditing ? "Edit snippet" : "New snippet")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if isEditing {
                                Button("Cancel") { clearForm() }
                                    .controlSize(.small)
                            }
                        }
                        Text("Tokens: {{date}} · {{date:MMM d, yyyy}} · {{clipboard}} · {{hostname}} · \\n for newlines")
                            .font(.system(size: 11))
                            .foregroundStyle(HFTheme.textTertiary)
                        TextField("Trigger (e.g. ,sig)", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("Expansion", text: $expansion, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)
                        TextField("Note", text: $note)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button(isEditing ? "Save Changes" : "Add Snippet") {
                                saveForm()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.accent)
                            .disabled(trigger.isEmpty || expansion.isEmpty)

                            if isEditing {
                                Text("Editing existing snippet")
                                    .font(.system(size: 11))
                                    .foregroundStyle(HFTheme.textTertiary)
                            }
                        }
                    }
                }

                ForEach(store.snippets) { snip in
                    GlassCard(padding: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    KeyCap(text: snip.trigger, compact: true)
                                    if !snip.note.isEmpty {
                                        Text(snip.note)
                                            .font(.caption)
                                            .foregroundStyle(HFTheme.textTertiary)
                                    }
                                    if editingID == snip.id {
                                        Text("Editing")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(HFTheme.accent)
                                    }
                                }
                                Text(snip.expansion.replacingOccurrences(of: "\n", with: "↵"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HFTheme.textSecondary)
                                    .lineLimit(3)
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
                            .help("Enable / disable")

                            Button {
                                beginEdit(snip)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HFTheme.accent)
                            .help("Edit snippet")

                            Button(role: .destructive) {
                                if editingID == snip.id { clearForm() }
                                store.delete(snip)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HFTheme.danger.opacity(0.8))
                            .help("Delete")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEdit(snip)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// Maps the stored format string to a preset id (or "custom").
    private var datePresetBinding: Binding<String> {
        Binding(
            get: {
                let current = store.dateFormat
                if let match = SnippetDateFormat.presets.first(where: {
                    !$0.format.isEmpty && $0.format == current
                }) {
                    return match.id
                }
                return "custom"
            },
            set: { id in
                guard let preset = SnippetDateFormat.presets.first(where: { $0.id == id }) else {
                    return
                }
                if !preset.format.isEmpty {
                    store.dateFormat = preset.format
                }
                // "Custom…" leaves the current pattern editable in the field.
            }
        )
    }

    private func beginEdit(_ snip: TextSnippet) {
        editingID = snip.id
        trigger = snip.trigger
        // Show real newlines in the editor
        expansion = snip.expansion
        note = snip.note
    }

    private func clearForm() {
        editingID = nil
        trigger = ""
        expansion = ""
        note = ""
    }

    private func saveForm() {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion
        guard !t.isEmpty, !e.isEmpty else { return }

        if let id = editingID,
           let existing = store.snippets.first(where: { $0.id == id })
        {
            var updated = existing
            updated.trigger = t
            updated.expansion = e
            updated.note = note
            store.update(updated)
            Banner.show(
                "Snippet updated",
                subtitle: t,
                style: .success,
                symbol: "pencil"
            )
        } else {
            // Avoid duplicate triggers when adding
            if store.snippets.contains(where: { $0.trigger == t }) {
                Banner.show(
                    "Trigger exists",
                    subtitle: "Edit the existing snippet, or pick another trigger",
                    style: .warning,
                    symbol: "text.badge.plus"
                )
                return
            }
            store.add(TextSnippet(trigger: t, expansion: e, note: note))
            Banner.show(
                "Snippet added",
                subtitle: t,
                style: .success,
                symbol: "text.badge.plus"
            )
        }
        clearForm()
    }
}
