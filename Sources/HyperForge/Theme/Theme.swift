// Theme.swift
// Dark-mode-first design tokens — glass, depth, accents from AppearanceStore.

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

/// Convenience colors — read active skin from UserDefaults (safe for default args).
/// Observe `AppearanceStore.shared` in views so SwiftUI refreshes on switch.
enum HFTheme {
    private static var p: ThemePalette {
        ThemePalettes.palette(for: ThemePalettes.styleFromDefaults())
    }

    static var accent: Color { p.accent }
    static var accentSecondary: Color { p.accentSecondary }
    static var success: Color { p.success }
    static var warning: Color { p.warning }
    static var danger: Color { p.danger }

    static var bgDeep: Color { p.bgDeep }
    static var bgElevated: Color { p.bgElevated }
    static var bgCard: Color { p.bgCard }
    static var stroke: Color { p.stroke }
    static var textPrimary: Color { p.textPrimary }
    static var textSecondary: Color { p.textSecondary }
    static var textTertiary: Color { p.textTertiary }

    static let radiusCard: CGFloat = 16
    static let radiusChip: CGFloat = 8
}

struct GlassBackground: View {
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        let p = appearance.palette
        ZStack {
            LinearGradient(
                colors: appearance.style == .infernal
                    ? [Color(hex: 0x050505), Color(hex: 0x0A0606), Color(hex: 0x050505)]
                    : [Color(hex: 0x0B0D12), Color(hex: 0x10141C), Color(hex: 0x0E1220)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(p.glowPrimary.opacity(appearance.style == .infernal ? 0.16 : 0.12))
                .frame(width: 420, height: 420)
                .blur(radius: appearance.style == .infernal ? 70 : 80)
                .offset(x: -180, y: -220)
            Circle()
                .fill(p.glowSecondary.opacity(appearance.style == .infernal ? 0.22 : 0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 220, y: 180)
            if appearance.style == .infernal {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xE10600).opacity(0.0),
                                Color(hex: 0xE10600).opacity(0.07),
                                Color(hex: 0xE10600).opacity(0.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 120)
                    .blur(radius: 40)
                    .rotationEffect(.degrees(-18))
                    .offset(y: 40)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: appearance.style)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ObservedObject private var appearance = AppearanceStore.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        let p = appearance.palette
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                    .fill(p.bgCard.opacity(appearance.style == .infernal ? 0.88 : 0.72))
                    .background {
                        RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: HFTheme.radiusCard, style: .continuous)
                            .strokeBorder(
                                appearance.style == .infernal
                                    ? p.accent.opacity(0.28)
                                    : p.stroke,
                                lineWidth: appearance.style == .infernal ? 1.2 : 1
                            )
                    }
            }
    }
}

struct KeyCap: View {
    let text: String
    var compact: Bool = false
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        let p = appearance.palette
        Text(text)
            .font(.system(
                size: compact ? 11 : 12,
                weight: .semibold,
                design: appearance.style == .infernal ? .default : .rounded
            ))
            .foregroundStyle(p.textPrimary)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background {
                RoundedRectangle(cornerRadius: appearance.style == .infernal ? 3 : 6, style: .continuous)
                    .fill(Color.white.opacity(appearance.style == .infernal ? 0.05 : 0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: appearance.style == .infernal ? 3 : 6, style: .continuous)
                            .strokeBorder(
                                appearance.style == .infernal
                                    ? p.accent.opacity(0.35)
                                    : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    var pulse: Bool = false
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        let p = appearance.palette
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: pulse ? 4 : 0)
            Text(title)
                .font(.system(
                    size: 11,
                    weight: appearance.style == .infernal ? .bold : .medium,
                    design: appearance.style == .infernal ? .default : .rounded
                ))
                .foregroundStyle(p.textSecondary)
                .textCase(appearance.style == .infernal ? .uppercase : nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color.white.opacity(appearance.style == .infernal ? 0.04 : 0.06))
                .overlay {
                    if appearance.style == .infernal {
                        Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1)
                    }
                }
        }
    }
}
