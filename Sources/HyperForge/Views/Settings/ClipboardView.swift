// ClipboardView.swift
// Multi-clipboard history browser — snapshots pasteboard on open / refresh only.

import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var clipboard = ClipboardService.shared
    @State private var filterText = ""

    private var filtered: [ClipboardEntry] {
        let source = clipboard.pinnedFirst
        guard !filterText.isEmpty else { return source }
        return source.filter { $0.text.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clipboard")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(HFTheme.textPrimary)
                        Text("Local plain-text history, persisted on this Mac. Hyper + ⇧V opens the quick menu. Snapshots on open / refresh — no background polling.")
                            .font(.system(size: 13))
                            .foregroundStyle(HFTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        let added = clipboard.poll()
                        if added {
                            Banner.show("History updated", style: .success, symbol: "doc.on.clipboard")
                        } else {
                            Banner.show(
                                "No new text",
                                subtitle: "Copy something, then refresh",
                                style: .info,
                                symbol: "doc.on.clipboard"
                            )
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !clipboard.entries.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(HFTheme.textTertiary)
                        TextField("Filter history", text: $filterText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(HFTheme.bgElevated, in: RoundedRectangle(cornerRadius: 8))
                }

                if clipboard.entries.isEmpty {
                    GlassCard {
                        Text("Copy text, then open this panel or tap Refresh to capture it.")
                            .foregroundStyle(HFTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if filtered.isEmpty {
                    GlassCard {
                        Text("No matches for “\(filterText)”.")
                            .foregroundStyle(HFTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                        GlassCard(padding: 12) {
                            HStack(alignment: .top) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(HFTheme.textTertiary)
                                    .frame(width: 20)
                                Text(entry.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HFTheme.textPrimary)
                                    .lineLimit(4)
                                Spacer()
                                Button {
                                    clipboard.togglePin(entry.id)
                                } label: {
                                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(entry.pinned ? HFTheme.accent : HFTheme.textTertiary)
                                .help(entry.pinned ? "Unpin" : "Pin — keeps this entry when history trims")
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.text, forType: .string)
                                    Banner.show("Copied to pasteboard")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(HFTheme.accent)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        clipboard.clearHistory()
                    } label: {
                        Label("Clear history (keeps pinned)", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    ClipboardService.shared.pasteAsPlainText()
                } label: {
                    Label("Paste as Plain Text (⌘V after strip)", systemImage: "doc.plaintext")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .onAppear {
            _ = clipboard.poll()
        }
    }
}
