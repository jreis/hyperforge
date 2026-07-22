// Theme.swift
// Dark-mode-first design tokens — glass, depth, restrained neon accents.

import SwiftUI

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum HFTheme {
    static let accent = Color(hex: 0x6C9EFF)
    static let accentSecondary = Color(hex: 0xBF5AF2)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFFD60A)
    static let danger = Color(hex: 0xFF453A)

    static let bgDeep = Color(hex: 0x0B0D12)
    static let bgElevated = Color(hex: 0x141820)
    static let bgCard = Color(hex: 0x1A1F2A)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static let radiusCard: CGFloat = 16
    static let radiusChip: CGFloat = 8
}

struct GlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x0B0D12),
                    Color(hex: 0x10141C),
                    Color(hex: 0x0E1220),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Soft aurora blobs
            Circle()
                .fill(HFTheme.accent.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: -180, y: -220)
            Circle()
                .fill(HFTheme.accentSecondary.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 220, y: 180)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                    .fill(HFTheme.bgCard.opacity(0.72))
                    .background {
                        RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                            .strokeBorder(HFTheme.stroke, lineWidth: 1)
                    }
            }
    }
}

struct KeyCap: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(HFTheme.textPrimary)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    var pulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: pulse ? 4 : 0)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(HFTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(Color.white.opacity(0.06))
        }
    }
}
