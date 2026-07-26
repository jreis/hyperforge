// AppearanceStore.swift
// Visual identity packs — Forge (default neon) vs Infernal (industrial / gothic edge).

import Combine
import SwiftUI

/// User-selectable skin. Infernal leans industrial-gothic (black, blood, bone)
/// without copying any artist’s trademarks.
enum AppearanceStyle: String, CaseIterable, Identifiable, Codable {
    case forge
    case infernal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forge: return "Forge"
        case .infernal: return "Infernal"
        }
    }

    var detail: String {
        switch self {
        case .forge:
            return "Cool neon · glass · portfolio-polished"
        case .infernal:
            return "Void black · blood crimson · bone · industrial edge"
        }
    }

    var symbol: String {
        switch self {
        case .forge: return "flame"
        case .infernal: return "flame.fill"
        }
    }
}

struct ThemePalette: Sendable {
    let accent: Color
    let accentSecondary: Color
    let success: Color
    let warning: Color
    let danger: Color
    let bgDeep: Color
    let bgElevated: Color
    let bgCard: Color
    let stroke: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let glowPrimary: Color
    let glowSecondary: Color
}

enum ThemePalettes {
    static func palette(for style: AppearanceStyle) -> ThemePalette {
        switch style {
        case .forge:
            return ThemePalette(
                accent: Color(hex: 0x6C9EFF),
                accentSecondary: Color(hex: 0xBF5AF2),
                success: Color(hex: 0x30D158),
                warning: Color(hex: 0xFFD60A),
                danger: Color(hex: 0xFF453A),
                bgDeep: Color(hex: 0x0B0D12),
                bgElevated: Color(hex: 0x141820),
                bgCard: Color(hex: 0x1A1F2A),
                stroke: Color.white.opacity(0.08),
                textPrimary: Color.white.opacity(0.92),
                textSecondary: Color.white.opacity(0.55),
                textTertiary: Color.white.opacity(0.35),
                glowPrimary: Color(hex: 0x6C9EFF),
                glowSecondary: Color(hex: 0xBF5AF2)
            )
        case .infernal:
            // Industrial gothic: pure void, arterial red, ash, bone type.
            return ThemePalette(
                accent: Color(hex: 0xE10600),
                accentSecondary: Color(hex: 0x8B0000),
                success: Color(hex: 0xC4A35A),
                warning: Color(hex: 0xE8D5A3),
                danger: Color(hex: 0xFF2A1F),
                bgDeep: Color(hex: 0x050505),
                bgElevated: Color(hex: 0x0C0C0C),
                bgCard: Color(hex: 0x121212),
                stroke: Color(hex: 0xE10600).opacity(0.22),
                textPrimary: Color(hex: 0xF2EDE4),
                textSecondary: Color(hex: 0xA39E94),
                textTertiary: Color(hex: 0x6B6660),
                glowPrimary: Color(hex: 0xE10600),
                glowSecondary: Color(hex: 0x3D0A0A)
            )
        }
    }

    static func styleFromDefaults() -> AppearanceStyle {
        if let raw = UserDefaults.standard.string(forKey: AppearanceKeys.style),
           let s = AppearanceStyle(rawValue: raw)
        {
            return s
        }
        return .forge
    }
}

/// UserDefaults key (nonisolated so theme palette can read it off the main actor).
enum AppearanceKeys {
    static let style = "hf.appearanceStyle"
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    static var styleKey: String { AppearanceKeys.style }

    @Published var style: AppearanceStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: AppearanceKeys.style)
        }
    }

    private init() {
        style = ThemePalettes.styleFromDefaults()
    }

    var palette: ThemePalette { ThemePalettes.palette(for: style) }

    var brandTagline: String {
        switch style {
        case .forge: return "Local-first Hyper automation"
        case .infernal: return "Built for the beautiful and the damned"
        }
    }
}
