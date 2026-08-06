// CommandBarView.swift
// Local AI command palette — offline router + optional Ollama on localhost.

import AppKit
import HyperForgeKit
import SwiftUI

struct CommandBarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var ollama = OllamaClient.shared

    @State private var query = ""
    @State private var results: [CommandResult] = []
    @State private var aiNote: String?
    @State private var generatedPayload: String?
    /// -1 = "Ask local AI" row (only meaningful while it's visible); 0... indexes `results`.
    @State private var highlightedIndex = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { appState.commandBarVisible = false }

            VStack(spacing: 0) {
                header
                Divider().overlay(HFTheme.stroke)
                if let aiNote {
                    Text(aiNote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HFTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                resultsList
                if let generatedPayload {
                    payloadPreview(generatedPayload)
                }
            }
            .frame(width: 600)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HFTheme.bgCard.opacity(0.95))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(HFTheme.stroke, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
            }
            .offset(y: -60)
        }
        .onAppear {
            focused = true
            results = CommandRouter.suggest("")
            highlightedIndex = 0
            Task { await ollama.ping() }
        }
        .onChange(of: query) { _, new in
            results = CommandRouter.suggest(new)
            highlightedIndex = new.isEmpty ? 0 : -1
            generatedPayload = nil
            aiNote = nil
        }
        .onExitCommand {
            _ = EscapeCoordinator.shared.handleEscape()
        }
    }

    private var hasAIRow: Bool { !query.isEmpty }

    private func moveSelection(by delta: Int) {
        let lower = hasAIRow ? -1 : 0
        let upper = results.count - 1
        guard upper >= lower else { return }
        highlightedIndex = min(max(highlightedIndex + delta, lower), upper)
    }

    private func submitCommand() {
        if highlightedIndex >= 0, results.indices.contains(highlightedIndex) {
            let r = results[highlightedIndex]
            r.run()
            appState.commandBarVisible = false
        } else {
            Task { await interpretAndRun() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: ollama.isThinking ? "ellipsis.bubble" : "sparkles")
                .foregroundStyle(HFTheme.accent)
                .opacity(ollama.isThinking ? 0.7 : 1)
            TextField(
                "Ask HyperForge… half-page scroll · generate Karabiner · open terminal",
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .focused($focused)
            .onSubmit { submitCommand() }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }

            StatusPill(
                title: ollama.isAvailable ? "Ollama" : "Offline",
                color: ollama.isAvailable ? HFTheme.success : HFTheme.textTertiary
            )
            KeyCap(text: "↵", compact: true)
            KeyCap(text: "Esc", compact: true)
        }
        .padding(16)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if !query.isEmpty {
                    Button {
                        Task { await interpretAndRun() }
                    } label: {
                        row(
                            icon: "brain",
                            title: ollama.isThinking ? "Thinking locally…" : "Ask local AI / router",
                            subtitle: ollama.isAvailable
                                ? "Ollama · \(ollama.model)"
                                : "Offline intent router (always private)",
                            isSelected: highlightedIndex == -1
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(Array(results.enumerated()), id: \.element.id) { index, r in
                    Button {
                        r.run()
                        appState.commandBarVisible = false
                    } label: {
                        row(
                            icon: r.icon,
                            title: r.title,
                            subtitle: r.subtitle,
                            kindLabel: r.kind.label,
                            isSelected: index == highlightedIndex
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 300)
    }

    private func row(
        icon: String,
        title: String,
        subtitle: String,
        kindLabel: String? = nil,
        isSelected: Bool = false
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(HFTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HFTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            if let kindLabel {
                Text(kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HFTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HFTheme.stroke.opacity(0.5), in: Capsule())
            }
        }
        .padding(10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HFTheme.accent.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
    }

    private func payloadPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(HFTheme.stroke)
            HStack {
                Text("Generated")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textSecondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    Banner.show("Copied to clipboard")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HFTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @MainActor
    private func interpretAndRun() async {
        let intent = await ollama.interpret(query)
        aiNote = intent.detail

        switch intent.kind {
        case .runAction:
            if let id = intent.actionID {
                HyperKeyActions.perform(actionID: id)
                appState.commandBarVisible = false
            } else {
                Banner.show(intent.title)
            }
        case .generateKarabiner, .generateSwift:
            generatedPayload = intent.payload
            if let payload = intent.payload {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(payload, forType: .string)
            }
            Banner.show(intent.title)
        case .explain:
            generatedPayload = intent.payload
            Banner.show(intent.title)
        case .unknown:
            // Fall back to first catalog suggestion
            if let first = results.first {
                first.run()
                appState.commandBarVisible = false
            } else {
                Banner.show(intent.title)
            }
        }
    }
}

enum CommandResultKind: String {
    case action, app, snippet, recipe, shortcut

    var label: String {
        switch self {
        case .action: return "Action"
        case .app: return "App"
        case .snippet: return "Snippet"
        case .recipe: return "Recipe"
        case .shortcut: return "Shortcut"
        }
    }
}

struct CommandResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    var kind: CommandResultKind = .action
    let run: () -> Void
}

@MainActor
enum CommandRouter {
    static func suggest(_ query: String) -> [CommandResult] {
        let q = query.lowercased()
        var items: [CommandResult] = []

        func add(_ title: String, _ subtitle: String, _ icon: String, _ actionID: String) {
            if q.isEmpty
                || title.lowercased().contains(q)
                || subtitle.lowercased().contains(q)
                || actionID.contains(q.replacingOccurrences(of: " ", with: "-"))
            {
                items.append(
                    CommandResult(title: title, subtitle: subtitle, icon: icon) {
                        Task { @MainActor in
                            HyperKeyActions.perform(actionID: actionID)
                        }
                    }
                )
            }
        }

        if q.contains("half") && q.contains("scroll") {
            items.append(
                CommandResult(
                    title: "Half-page scroll down",
                    subtitle: "Vim ⌃d · pixel scroll",
                    icon: "arrow.down.doc"
                ) {
                    EventSynthesizer.postScroll(dy: -300)
                    Banner.show("Half-page down")
                }
            )
        }
        if q.contains("hint") {
            add("Link Hints", "Hyper + /", "link.circle", "sys-link-hints")
        }
        if q.contains("cheat") || q.contains("binding") || q.contains("shortcut") || q == "help"
            || q.contains("keymap")
        {
            add("Keybinding Cheat Sheet", "Hyper + ⇧/", "keyboard", "sys-cheatsheet")
        }
        if q.contains("export") || q.contains("portfolio") {
            items.append(
                CommandResult(
                    title: "Export portfolio demo pack",
                    subtitle: "Desktop folder · markdown + screenshots",
                    icon: "square.and.arrow.up"
                ) {
                    Task { @MainActor in
                        _ = DemoExportService.shared.exportPortfolioPack()
                    }
                }
            )
        }
        if q.contains("snap") && q.contains("left") {
            add("Snap Left Half", "Hyper + ←", "rectangle.lefthalf.filled", "win-left")
        }
        if q.contains("terminal") || q.contains("iterm") || q.contains("ghostty") {
            add("New Terminal Window", "Hyper + T", "terminal", "app-iterm")
        }
        if q.contains("lock") {
            add("Lock Screen", "Hold Hyper + Esc", "lock", "sys-lock")
        }

        // Broad catalog: apps, snippets, recipes, Shortcuts, and Hyper actions.
        // Curated matches above take priority on title collisions (dedup keeps first).
        items.append(contentsOf: CommandCatalog.allEntries())

        var seen = Set<String>()
        let deduped = items.filter { seen.insert($0.title).inserted }

        let ranked = FuzzyMatch.rank(deduped, query: query) { "\($0.title) \($0.subtitle)" }
        return Array(ranked.prefix(20))
    }
}
