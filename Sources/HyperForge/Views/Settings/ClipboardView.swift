// ClipboardView.swift
// Multi-clipboard history browser.

import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var clipboard = ClipboardService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Clipboard")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Local history of recent plain-text copies. Nothing leaves this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)

                if clipboard.history.isEmpty {
                    GlassCard {
                        Text("Copy something to start building history.")
                            .foregroundStyle(HFTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(Array(clipboard.history.enumerated()), id: \.offset) { index, item in
                        GlassCard(padding: 12) {
                            HStack(alignment: .top) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(HFTheme.textTertiary)
                                    .frame(width: 20)
                                Text(item)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HFTheme.textPrimary)
                                    .lineLimit(4)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item, forType: .string)
                                    Banner.show("Copied to pasteboard")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(HFTheme.accent)
                            }
                        }
                    }
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
    }
}

import AppKit
