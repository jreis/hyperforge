// FirstRunChallengeView.swift
// Live 3-chord proof: Hyper · Space+HJKL · window snap.

import SwiftUI

struct FirstRunChallengeView: View {
    @ObservedObject private var challenge = FirstRunChallengeStore.shared
    var compact: Bool = false
    var onFinished: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact ? "First chords" : "Prove it works")
                        .font(.system(size: compact ? 14 : 16, weight: .bold, design: .rounded))
                        .foregroundStyle(HFTheme.textPrimary)
                    Text("Do these three for real — HyperForge listens.")
                        .font(.system(size: 11))
                        .foregroundStyle(HFTheme.textTertiary)
                }
                Spacer()
                Text(challenge.progressLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(challenge.allProved ? HFTheme.success : HFTheme.accent)
                    .monospacedDigit()
            }

            challengeRow(
                done: challenge.hyperDone,
                symbol: "capslock.fill",
                title: "Hold Caps (Hyper)",
                detail: "Hold Caps Lock — flame fills when Hyper is live"
            )
            challengeRow(
                done: challenge.spaceDone,
                symbol: "arrow.up.and.down.and.arrow.left.and.right",
                title: "Hold Space + H / J / K / L",
                detail: "Hold Space ~120–200ms, then move — look for the NAV / VOID pill"
            )
            challengeRow(
                done: challenge.snapDone,
                symbol: "rectangle.split.2x1",
                title: "Hyper + ← or →",
                detail: "Snap the front window half-left or half-right"
            )

            if challenge.allProved {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(HFTheme.success)
                    Text("All three landed. You’re set.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HFTheme.success)
                    Spacer()
                    if let onFinished {
                        Button("Continue") { onFinished() }
                            .buttonStyle(.borderedProminent)
                            .tint(HFTheme.accent)
                            .controlSize(.small)
                    }
                }
            } else {
                HStack {
                    if compact {
                        Button("Skip") { challenge.skip() }
                            .controlSize(.small)
                    }
                    Spacer()
                    Text("Engine must be Live · Accessibility on")
                        .font(.system(size: 10))
                        .foregroundStyle(HFTheme.textTertiary)
                }
            }
        }
        .padding(compact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HFTheme.stroke, lineWidth: 1)
                )
        )
    }

    private func challengeRow(done: Bool, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(done ? HFTheme.success : HFTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(done ? HFTheme.textSecondary : HFTheme.textPrimary)
                    .strikethrough(done, color: HFTheme.textTertiary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HFTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
