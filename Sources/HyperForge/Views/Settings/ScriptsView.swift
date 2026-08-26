// ScriptsView.swift
// Manage JavaScript automations — add, edit, enable, run, delete.

import SwiftUI

struct ScriptsView: View {
    @ObservedObject private var store = ScriptStore.shared
    @State private var name = ""
    @State private var source = ""
    @State private var bundleID = ""
    /// When set, the form is editing this script instead of adding a new one.
    @State private var editingID: UUID?
    @AppStorage("hf.scriptEditorVimEnabled") private var vimEnabled = true
    /// Bumped whenever the *loaded document* changes (new/edit/cancel) so the editor
    /// resets its content without fighting live typing on every keystroke.
    @State private var editorReloadToken = 0
    /// Bumped on pencil / double-click so the WKWebView takes first responder.
    @State private var editorFocusToken = 0
    private let editorFormID = "script-editor-form"

    private var isEditing: Bool { editingID != nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scripts")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(HFTheme.textPrimary)
                            Text("JavaScript automations — run from Hyper + ⇧Y, Command Bar, or Quick Menu.")
                                .font(.system(size: 13))
                                .foregroundStyle(HFTheme.textSecondary)
                        }
                        Spacer()
                        Button("Run menu…") { store.showMenu() }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.accent)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(isEditing ? "Edit script" : "New script")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Toggle("Vim mode", isOn: $vimEnabled)
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 11))
                                if isEditing {
                                    Button("Cancel") { clearForm() }
                                        .controlSize(.small)
                                }
                            }
                            Text("Type HF. for completions · Ctrl-Space lists methods · HF.snap notify log clipboardGet/Set pasteText pressKey runShortcut launchApp sleep")
                                .font(.system(size: 11))
                                .foregroundStyle(HFTheme.textTertiary)
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            ScriptEditorWebView(
                                source: $source,
                                vimEnabled: vimEnabled,
                                reloadToken: editorReloadToken,
                                focusToken: editorFocusToken
                            )
                            .frame(minHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(HFTheme.stroke, lineWidth: 1)
                            }
                            TextField("Bundle ID filter (optional — empty = any app)", text: $bundleID)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Button(isEditing ? "Save Changes" : "Add Script") {
                                    saveForm()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                                .disabled(name.isEmpty || source.isEmpty)

                                if isEditing {
                                    Text("Editing existing script")
                                        .font(.system(size: 11))
                                        .foregroundStyle(HFTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .id(editorFormID)

                    ForEach(store.scripts) { script in
                        scriptRow(script)
                    }
                }
                .padding(24)
            }
            .onChange(of: editorFocusToken) { _, _ in
                // Wait one turn so the form has the new title/content before we scroll.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(editorFormID, anchor: .top)
                    }
                }
            }
        }
    }

    private func scriptRow(_ script: JSScript) -> some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: script.symbol)
                        .foregroundStyle(HFTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(script.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(script.source)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HFTheme.textTertiary)
                            .lineLimit(2)
                        if !script.bundleID.isEmpty {
                            Text(script.bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { script.isEnabled },
                            set: { v in
                                var s = script
                                s.isEnabled = v
                                store.update(s)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Enable / disable")

                    Button("Run") { store.run(script) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(HFTheme.accent)

                    Button {
                        beginEdit(script)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HFTheme.accent)
                    .help("Edit script")

                    Button(role: .destructive) {
                        if editingID == script.id { clearForm() }
                        store.delete(script)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HFTheme.danger.opacity(0.8))
                    .help("Delete")
                }
                if let error = script.lastError, !error.isEmpty {
                    Text("Last error: \(error)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HFTheme.danger)
                        .lineLimit(3)
                }
                if let output = script.lastOutput, !output.isEmpty {
                    Text("Output: \(output)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HFTheme.textSecondary)
                        .lineLimit(5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                beginEdit(script)
            }
        }
    }

    private func beginEdit(_ script: JSScript) {
        editingID = script.id
        name = script.name
        source = script.source
        bundleID = script.bundleID
        editorReloadToken += 1
        editorFocusToken += 1
    }

    private func clearForm() {
        editingID = nil
        name = ""
        source = ""
        bundleID = ""
        editorReloadToken += 1
    }

    private func saveForm() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = source
        guard !n.isEmpty, !s.isEmpty else { return }

        if let id = editingID,
           let existing = store.scripts.first(where: { $0.id == id })
        {
            var updated = existing
            updated.name = n
            updated.source = s
            updated.bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            store.update(updated)
            Banner.show("Script updated", subtitle: n, style: .success, symbol: "pencil")
        } else {
            store.add(
                JSScript(
                    name: n,
                    source: s,
                    bundleID: bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            Banner.show("Script added", subtitle: n, style: .success, symbol: "curlybraces")
        }
        clearForm()
    }
}
