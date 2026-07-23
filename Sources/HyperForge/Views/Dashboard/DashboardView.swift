// DashboardView.swift
// Hyper Key Central — catalog, search, live test, engine status.

import AppKit
import HyperForgeKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var engine: HyperKeyEngine
    @EnvironmentObject private var profiles: ProfileStore

    @State private var categoryFilter: ActionCategory?
    @State private var selectedAction: HyperAction?
    @State private var flashID: String?
    @FocusState private var searchFocused: Bool

    private var actions: [HyperAction] {
        var list = ActionCatalog.defaults
        let enabled = profiles.activeProfile.enabledActionIDs
        if !enabled.isEmpty {
            list = list.filter { enabled.contains($0.id) }
        }
        if let categoryFilter {
            list = list.filter { $0.category == categoryFilter }
        }
        let q = appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            Divider().overlay(HFTheme.stroke)
            HStack(spacing: 0) {
                actionList
                Divider().overlay(HFTheme.stroke)
                detailPanel
                    .frame(width: 300)
            }
        }
        .onAppear { focusSearchSoon() }
        // Window re-shown after Esc hide / Hyper+, — onAppear may not re-fire.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            note in
            guard let win = note.object as? NSWindow, isDashboardWindow(win) else { return }
            focusSearchSoon()
        }
    }

    private func focusSearchSoon() {
        // Immediate + delayed: NSWindow key status often lags SwiftUI appear.
        searchFocused = true
        DispatchQueue.main.async { searchFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
    }

    private func isDashboardWindow(_ win: NSWindow) -> Bool {
        if win.identifier?.rawValue == DashboardWindowPolicy.dashboardIdentifier {
            return true
        }
        return AppState.dashboardWindows().contains { $0 === win }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hyper Key Central")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text(engine.statusMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(HFTheme.textSecondary)
                }
                Spacer()
                Button {
                    CheatSheetCommands.toggle()
                } label: {
                    Label("Cheat Sheet", systemImage: "keyboard")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Hyper + ⇧ + / — searchable keybinding reference")

                Toggle(isOn: $appState.liveTestMode) {
                    Label("Live Test", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Click any action to fire it immediately")
            }

            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HFTheme.textTertiary)
                    TextField("Search bindings…", text: $appState.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                        .onSubmit { searchFocused = true }
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

                Button {
                    appState.commandBarVisible = true
                } label: {
                    Label("Command", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(HFTheme.accent.opacity(0.18))
                }
                .foregroundStyle(HFTheme.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "All", selected: categoryFilter == nil) {
                        categoryFilter = nil
                    }
                    ForEach(ActionCategory.allCases) { cat in
                        filterChip(
                            title: cat.rawValue,
                            selected: categoryFilter == cat,
                            color: cat.tint
                        ) {
                            categoryFilter = cat
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func filterChip(
        title: String,
        selected: Bool,
        color: Color = HFTheme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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

    // MARK: - List

    private var actionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !appState.isAccessibilityTrusted {
                    permissionBanner
                }

                statsRow

                ForEach(grouped, id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.tint)
                            Text(category.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(HFTheme.textSecondary)
                            Text("\(items.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(HFTheme.textTertiary)
                        }
                        .padding(.horizontal, 4)

                        if category == .vim {
                            ForEach(SpaceNavGroup.grouped(items), id: \.0) { group, sub in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: group.symbol)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(HFTheme.danger.opacity(0.85))
                                        Text(group.rawValue)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(HFTheme.textTertiary)
                                    }
                                    .padding(.leading, 8)
                                    .padding(.top, 4)

                                    ForEach(sub) { action in
                                        actionRow(action)
                                    }
                                }
                            }
                        } else {
                            ForEach(items) { action in
                                actionRow(action)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func actionRow(_ action: HyperAction) -> some View {
        ActionRow(
            action: action,
            isSelected: selectedAction?.id == action.id,
            isFlashing: flashID == action.id,
            liveTest: appState.liveTestMode
        ) {
            selectedAction = action
            if appState.liveTestMode {
                flashID = action.id
                HyperKeyActions.perform(actionID: action.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if flashID == action.id { flashID = nil }
                }
            }
        }
    }

    private var permissionBanner: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(HFTheme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility required")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Grant HyperForge access so the Hyper Key engine can listen for F18.")
                        .font(.system(size: 12))
                        .foregroundStyle(HFTheme.textSecondary)
                }
                Spacer()
                Button("Open Settings") {
                    PermissionsService.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(HFTheme.warning)
                .controlSize(.small)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Bindings",
                value: "\(actions.count)",
                icon: "keyboard",
                color: HFTheme.accent
            )
            statCard(
                title: "Profile",
                value: profiles.activeProfile.name,
                icon: profiles.activeProfile.symbol,
                color: Color(hex: profiles.activeProfile.accentHex)
            )
            statCard(
                title: "Hyper",
                value: engine.hyperKeyActive ? "HELD" : "Ready",
                icon: "flame.fill",
                color: engine.hyperKeyActive ? HFTheme.accentSecondary : HFTheme.success
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        GlassCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(HFTheme.textTertiary)
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let action = selectedAction {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 28))
                        .foregroundStyle(action.category.tint)
                        .frame(width: 52, height: 52)
                        .background(
                            action.category.tint.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )

                    Text(action.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)

                    Text(action.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(HFTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        KeyCap(text: action.mode == .hyper ? "Hyper" : "Space")
                        Text("+")
                            .foregroundStyle(HFTheme.textTertiary)
                        KeyCap(text: action.keyLabel)
                    }

                    Label(action.category.rawValue, systemImage: action.category.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(action.category.tint)

                    Spacer()

                    Button {
                        HyperKeyActions.perform(actionID: action.id)
                    } label: {
                        Label("Test Action", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [HFTheme.accent, HFTheme.accentSecondary.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 32))
                        .foregroundStyle(HFTheme.textTertiary)
                    Text("Select a binding")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HFTheme.textSecondary)
                    Text("Hold Caps (F18) + key for Hyper. Hold Space + H/J/K/L for arrows (TouchCursor-style).")
                        .font(.system(size: 12))
                        .foregroundStyle(HFTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .background(HFTheme.bgElevated.opacity(0.4))
    }
}

struct ActionRow: View {
    let action: HyperAction
    let isSelected: Bool
    let isFlashing: Bool
    let liveTest: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(action.category.tint)
                    .frame(width: 30, height: 30)
                    .background(
                        action.category.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text(action.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HFTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    if action.mode != .hyper {
                        KeyCap(text: action.mode == .vimShift ? "⇧" : (action.mode == .vimCtrl ? "⌃" : "Space"), compact: true)
                    } else {
                        KeyCap(text: "Hyper", compact: true)
                    }
                    KeyCap(text: action.keyLabel, compact: true)
                }

                if liveTest {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HFTheme.warning)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isFlashing
                            ? action.category.tint.opacity(0.25)
                            : (isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? action.category.tint.opacity(0.45) : HFTheme.stroke,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isFlashing)
    }
}
