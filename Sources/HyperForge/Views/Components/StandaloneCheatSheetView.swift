// StandaloneCheatSheetView.swift
// Self-contained cheat sheet UI with no EnvironmentObject / MainActor stores.
// Safe to host from MenuBarExtra and CGEvent-tap paths.

import AppKit
import SwiftUI

struct StandaloneCheatSheetView: View {
    @State private var query = ""
    @State private var categoryFilter: ActionCategory?
    @FocusState private var searchFocused: Bool

    private var actions: [HyperAction] {
        var list = ActionCatalog.defaults
        if let categoryFilter {
            list = list.filter { $0.category == categoryFilter }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.detail.lowercased().contains(q)
                    || $0.shortcutDisplay.lowercased().contains(q)
                    || $0.keyLabel.lowercased().contains(q)
            }
        }
        return list
    }

    private var grouped: [(ActionCategory, [HyperAction])] {
        ActionCatalog.grouped(actions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            searchBar
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(grouped, id: \.0) { cat, items in
                        section(cat, items)
                    }
                }
                .padding(16)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear { focusSearchSoon() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            note in
            guard let win = note.object as? NSWindow,
                  win.title.contains("Keybindings")
            else { return }
            focusSearchSoon()
        }
    }

    private func focusSearchSoon() {
        searchFocused = true
        DispatchQueue.main.async { searchFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
    }

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("HyperForge Keybindings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(actions.count) bindings · search or filter below")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                keyCap("Hyper")
                Text("+").foregroundStyle(.secondary)
                keyCap("/")
                Text("or").font(.caption).foregroundStyle(.secondary)
                keyCap("`")
            }
            Button {
                CheatSheetCommands.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip("All", selected: categoryFilter == nil) { categoryFilter = nil }
                    ForEach(ActionCategory.allCases) { cat in
                        filterChip(cat.rawValue, selected: categoryFilter == cat) {
                            categoryFilter = cat
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func section(_ cat: ActionCategory, _ items: [HyperAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(cat.rawValue, systemImage: cat.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(cat.tint)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(items) { action in
                    HStack(spacing: 8) {
                        Image(systemName: action.symbol)
                            .foregroundStyle(cat.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(action.shortcutDisplay)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Hold Caps (Hyper) + key · Esc closes this window")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { CheatSheetCommands.hide() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(12)
    }

    private func keyCap(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.blue.opacity(0.25) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
