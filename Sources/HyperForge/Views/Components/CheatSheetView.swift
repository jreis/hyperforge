// CheatSheetView.swift
// Quick reference for every Hyper / Vim binding — open when you forget.

import SwiftUI

struct CheatSheetView: View {
    /// When true, shown in a floating NSPanel (no dimmed backdrop).
    var standalone: Bool = false

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profiles: ProfileStore

    @State private var query = ""
    @State private var categoryFilter: ActionCategory?
    @State private var modeFilter: ModeFilter = .all
    @FocusState private var searchFocused: Bool

    private enum ModeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case hyper = "Hyper"
        case vim = "Vim"
        var id: String { rawValue }
    }

    private var actions: [HyperAction] {
        var list = ActionCatalog.defaults
        let enabled = profiles.activeProfile.enabledActionIDs
        if !enabled.isEmpty {
            list = list.filter { enabled.contains($0.id) }
        }
        if let categoryFilter {
            list = list.filter { $0.category == categoryFilter }
        }
        switch modeFilter {
        case .all: break
        case .hyper: list = list.filter { $0.mode == .hyper }
        case .vim: list = list.filter { $0.mode != .hyper }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.detail.lowercased().contains(q)
                    || $0.shortcutDisplay.lowercased().contains(q)
                    || $0.keyLabel.lowercased().contains(q)
                    || $0.category.rawValue.lowercased().contains(q)
            }
        }
        return list
    }

    private var grouped: [(ActionCategory, [HyperAction])] {
        ActionCatalog.grouped(actions)
    }

    var body: some View {
        Group {
            if standalone {
                sheetCard
            } else {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { dismiss() }
                    sheetCard
                }
            }
        }
        .onAppear {
            searchFocused = true
        }
        .onExitCommand { dismiss() }
    }

    private var sheetCard: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(HFTheme.stroke)
            filters
            Divider().overlay(HFTheme.stroke)
            content
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if standalone {
                HFTheme.bgDeep
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HFTheme.bgCard.opacity(0.97))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(HFTheme.stroke, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
            }
        }
        .frame(width: standalone ? nil : 720, height: standalone ? nil : 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.title2)
                .foregroundStyle(HFTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keybinding Cheat Sheet")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Profile: \(profiles.activeProfile.name) · \(actions.count) bindings shown")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HFTheme.textTertiary)
            }

            Spacer()

            HStack(spacing: 4) {
                KeyCap(text: "Hyper", compact: true)
                Text("+")
                    .foregroundStyle(HFTheme.textTertiary)
                KeyCap(text: "/", compact: true)
                Text("or")
                    .font(.system(size: 10))
                    .foregroundStyle(HFTheme.textTertiary)
                KeyCap(text: "`", compact: true)
            }
            .font(.system(size: 11))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(HFTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(18)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HFTheme.textTertiary)
                    TextField("Search title, key, or category…", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .font(.system(size: 13))
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(HFTheme.stroke, lineWidth: 1)
                        }
                }

                Picker("", selection: $modeFilter) {
                    ForEach(ModeFilter.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: categoryFilter == nil) { categoryFilter = nil }
                    ForEach(ActionCategory.allCases) { cat in
                        chip(cat.rawValue, selected: categoryFilter == cat, color: cat.tint) {
                            categoryFilter = cat
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var content: some View {
        ScrollView {
            if grouped.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(HFTheme.textTertiary)
                    Text("No bindings match")
                        .font(.headline)
                        .foregroundStyle(HFTheme.textSecondary)
                    Text("Try another search or clear filters.")
                        .font(.caption)
                        .foregroundStyle(HFTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    legend
                    ForEach(grouped, id: \.0) { category, items in
                        section(category, items)
                    }
                }
                .padding(18)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: HFTheme.accent, title: "Hyper", detail: "Hold Caps (F18) + key")
            legendItem(color: HFTheme.danger.opacity(0.9), title: "Vim", detail: "Hold Right ⌘ + key")
            Spacer()
            if appState.liveTestMode {
                Text("Live Test on — click a row to fire")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HFTheme.warning)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
    }

    private func legendItem(color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(HFTheme.textTertiary)
            }
        }
    }

    private func section(_ category: ActionCategory, _ items: [HyperAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.tint)
                Text(category.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textSecondary)
                Text("\(items.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HFTheme.textTertiary)
            }

            // Two-column grid of binding rows
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 6
            ) {
                ForEach(items) { action in
                    bindingRow(action)
                }
            }
        }
    }

    private func bindingRow(_ action: HyperAction) -> some View {
        Button {
            if appState.liveTestMode {
                HyperKeyActions.perform(actionID: action.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(action.category.tint)
                    .frame(width: 22, height: 22)
                    .background(
                        action.category.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                        .lineLimit(1)
                    Text(action.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(HFTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                shortcutCaps(action)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(HFTheme.stroke, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.liveTestMode ? "Click to test: \(action.title)" : action.shortcutDisplay)
    }

    @ViewBuilder
    private func shortcutCaps(_ action: HyperAction) -> some View {
        HStack(spacing: 3) {
            switch action.mode {
            case .hyper:
                KeyCap(text: "Hyper", compact: true)
            case .vim:
                KeyCap(text: "Vim", compact: true)
            case .vimShift:
                KeyCap(text: "Vim", compact: true)
                KeyCap(text: "⇧", compact: true)
            case .vimCtrl:
                KeyCap(text: "Vim", compact: true)
                KeyCap(text: "⌃", compact: true)
            }
            KeyCap(text: action.keyLabel, compact: true)
        }
    }

    private var footer: some View {
        HStack {
            Text("Hold Caps for Hyper · Right ⌘ for Vim · Esc closes this sheet")
                .font(.system(size: 11))
                .foregroundStyle(HFTheme.textTertiary)
            Spacer()
            Button("Open Dashboard") {
                appState.selectedSidebar = .dashboard
                dismiss()
            }
            .controlSize(.small)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(HFTheme.accent)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(14)
        .background(HFTheme.bgElevated.opacity(0.5))
    }

    private func chip(
        _ title: String,
        selected: Bool,
        color: Color = HFTheme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(selected ? color.opacity(0.22) : Color.white.opacity(0.05))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(selected ? color.opacity(0.5) : HFTheme.stroke, lineWidth: 1)
                }
                .foregroundStyle(selected ? color : HFTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        appState.cheatSheetVisible = false
        if standalone {
            CheatSheetCommands.hide()
        }
    }
}
