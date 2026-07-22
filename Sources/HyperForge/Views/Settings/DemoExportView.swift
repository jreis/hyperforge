// DemoExportView.swift
// One-click portfolio demo pack (bindings, screenshots, architecture notes).

import SwiftUI

struct DemoExportView: View {
    @ObservedObject private var exporter = DemoExportService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Demo Export")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(HFTheme.textPrimary)
                Text("Export portfolio-ready assets: binding tables, profiles, Karabiner rule, architecture notes, and window screenshots.")
                    .font(.system(size: 13))
                    .foregroundStyle(HFTheme.textSecondary)

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Desktop pack", systemImage: "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text(exporter.status)
                            .font(.system(size: 12))
                            .foregroundStyle(HFTheme.textTertiary)

                        Button {
                            _ = exporter.exportPortfolioPack()
                        } label: {
                            Label("Export HyperForge Demo Pack", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [HFTheme.accent, HFTheme.accentSecondary.opacity(0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .foregroundStyle(.white)

                        if let url = exporter.lastExportURL {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .controlSize(.small)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Includes")
                            .font(.system(size: 13, weight: .semibold))
                        bullet("BINDINGS.md — full shortcut table for case studies")
                        bullet("bindings.json — machine-readable catalog")
                        bullet("PROFILES.md + auto-trigger snapshot")
                        bullet("karabiner-caps-to-f18.json — production rule")
                        bullet("ARCHITECTURE.md — module map for recruiters")
                        bullet("screenshots/ — live window + desktop captures")
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Portfolio tip")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open the dashboard, enable Live Test, arrange a dual-pane coding layout, then export. Drop screenshots into your portfolio or case study.")
                            .font(.system(size: 12))
                            .foregroundStyle(HFTheme.textSecondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HFTheme.success)
                .font(.system(size: 12))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(HFTheme.textSecondary)
        }
    }
}

import AppKit
