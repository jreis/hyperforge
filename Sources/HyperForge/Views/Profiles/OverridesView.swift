// OverridesView.swift
// Per-app Hyper binding disables and remaps.

import AppKit
import CoreGraphics
import SwiftUI

struct OverridesView: View {
    @ObservedObject private var store = AppOverrideStore.shared
    @State private var selectedID: UUID?
    @State private var manualBundle = ""
    @State private var manualName = ""
    @State private var remapKey = ""
    @State private var remapActionID = "win-left"

    private var selected: AppOverride? {
        store.overrides.first { $0.id == selectedID } ?? store.overrides.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .frame(minWidth: 280, idealWidth: 320)
            Divider().overlay(HFTheme.stroke)
            detailPane
                .frame(maxWidth: .infinity)
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App Overrides")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(HFTheme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Text("When an app is frontmost, disable or remap Hyper actions.")
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
                .padding(.horizontal, 20)

            HStack {
                Button {
                    if let app = NSWorkspace.shared.frontmostApplication {
                        store.add(for: app)
                    }
                } label: {
                    Label("Add frontmost", systemImage: "plus.app")
                }
                .buttonStyle(.borderedProminent)
                .tint(HFTheme.accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)

            List(selection: $selectedID) {
                ForEach(store.overrides) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HFTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !item.isEnabled {
                            Text("Off")
                                .font(.caption2)
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                    }
                    .tag(Optional(item.id))
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.delete(item)
                            if selectedID == item.id { selectedID = nil }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            GlassCard(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manual add")
                        .font(.caption.weight(.semibold))
                    TextField("Bundle ID", text: $manualBundle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    TextField("Name", text: $manualName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        store.addManual(bundleID: manualBundle, appName: manualName)
                        manualBundle = ""
                        manualName = ""
                    }
                    .controlSize(.small)
                    .disabled(manualBundle.isEmpty)
                }
            }
            .padding(16)
        }
        .background(HFTheme.bgElevated.opacity(0.35))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let current = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.displayTitle)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text(current.bundleID)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(
                            get: { current.isEnabled },
                            set: { v in
                                var item = current
                                item.isEnabled = v
                                store.update(item)
                                selectedID = item.id
                            }
                        ))
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Disabled actions")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Checked = blocked in this app.")
                                .font(.caption)
                                .foregroundStyle(HFTheme.textTertiary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 180), spacing: 6)],
                                spacing: 6
                            ) {
                                ForEach(ActionCatalog.defaults.filter { $0.mode == .hyper }) { action in
                                    Toggle(isOn: Binding(
                                        get: { current.disabledActionIDs.contains(action.id) },
                                        set: { disabled in
                                            var item = current
                                            if disabled {
                                                item.disabledActionIDs.insert(action.id)
                                            } else {
                                                item.disabledActionIDs.remove(action.id)
                                            }
                                            store.update(item)
                                            selectedID = item.id
                                        }
                                    )) {
                                        Text(action.title)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Remaps")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Hyper + key runs a different action while this app is frontmost.")
                                .font(.caption)
                                .foregroundStyle(HFTheme.textTertiary)

                            ForEach(current.remaps) { remap in
                                HStack {
                                    KeyCap(text: KeyCode.displayName(CGKeyCode(remap.keyCode)))
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(HFTheme.textTertiary)
                                    Text(
                                        ActionCatalog.defaults.first { $0.id == remap.actionID }?
                                            .title ?? remap.actionID
                                    )
                                    .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Button(role: .destructive) {
                                        var item = current
                                        item.remaps.removeAll { $0.id == remap.id }
                                        store.update(item)
                                        selectedID = item.id
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(HFTheme.danger.opacity(0.8))
                                }
                            }

                            HStack {
                                TextField("Key (e.g. j, 1, return)", text: $remapKey)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                Picker("Action", selection: $remapActionID) {
                                    ForEach(ActionCatalog.defaults.filter { $0.mode == .hyper }) { a in
                                        Text(a.title).tag(a.id)
                                    }
                                }
                                Button("Add Remap") {
                                    guard let code = Self.parseKey(remapKey) else {
                                        Banner.show("Unknown key")
                                        return
                                    }
                                    var item = current
                                    item.remaps.append(
                                        KeyRemap(keyCode: code, actionID: remapActionID)
                                    )
                                    store.update(item)
                                    selectedID = item.id
                                    remapKey = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(HFTheme.accent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .onAppear { selectedID = current.id }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "app.badge.checkmark")
                    .font(.largeTitle)
                    .foregroundStyle(HFTheme.textTertiary)
                Text("No overrides")
                    .font(.headline)
                    .foregroundStyle(HFTheme.textSecondary)
                Text("Add the frontmost app to customize its Hyper behavior.")
                    .font(.caption)
                    .foregroundStyle(HFTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Parse a simple key label into a key code.
    private static func parseKey(_ raw: String) -> UInt16? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: CGKeyCode] = [
            "a": KeyCode.a, "b": KeyCode.b, "c": KeyCode.c, "d": KeyCode.d,
            "e": KeyCode.e, "f": KeyCode.f, "g": KeyCode.g, "h": KeyCode.h,
            "i": KeyCode.i, "j": KeyCode.j, "k": KeyCode.k, "l": KeyCode.l,
            "m": KeyCode.m, "n": KeyCode.n, "o": KeyCode.o, "p": KeyCode.p,
            "q": KeyCode.q, "r": KeyCode.r, "s": KeyCode.s, "t": KeyCode.t,
            "u": KeyCode.u, "v": KeyCode.v, "w": KeyCode.w, "x": KeyCode.x,
            "y": KeyCode.y, "z": KeyCode.z,
            "1": KeyCode.one, "2": KeyCode.two, "3": KeyCode.three,
            "4": KeyCode.four, "5": KeyCode.five, "0": KeyCode.zero,
            "return": KeyCode.return, "enter": KeyCode.return,
            "tab": KeyCode.tab, "space": KeyCode.space, "esc": KeyCode.escape,
            "escape": KeyCode.escape, "/": KeyCode.slash, ".": KeyCode.period,
            ";": KeyCode.semicolon,
            "left": KeyCode.leftArrow, "right": KeyCode.rightArrow,
            "up": KeyCode.upArrow, "down": KeyCode.downArrow,
        ]
        return map[s].map { UInt16($0) }
    }
}
