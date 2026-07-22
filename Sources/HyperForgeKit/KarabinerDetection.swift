// KarabinerDetection.swift
// Pure heuristics for Hyper style + rule presence (no file I/O, no AppKit).

import Foundation

/// How Caps Lock (or equivalent) is wired into HyperForge.
public enum HyperStyle: String, CaseIterable, Sendable, Identifiable {
    case f18 = "F18"
    case quadMod = "4-mod (⌘⌃⌥⇧)"
    case mixed = "Mixed / unknown"
    case none = "Not detected"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
        case .f18:
            return "Caps → F18 (alone = Escape). HyperForge listens for F18. Slash + Shift opens help; plain / can run link hints."
        case .quadMod:
            return "Caps → ⌘⌃⌥⇧ (alone = Escape). Shift is always “on” while Hyper is held, so help/dashboard need Karabiner F19/F20 bridges."
        case .mixed:
            return "Config mentions more than one Hyper style. Prefer enabling one Caps rule at a time."
        case .none:
            return "No Caps→Hyper rule found in Karabiner yet. Install the HyperForge pack below."
        }
    }

    public var symbol: String {
        switch self {
        case .f18: return "f.circle"
        case .quadMod: return "command"
        case .mixed: return "questionmark.circle"
        case .none: return "exclamationmark.triangle"
        }
    }

    public var isHealthy: Bool {
        self == .f18 || self == .quadMod
    }
}

public struct KarabinerRuleStatus: Equatable, Sendable {
    public var capsToF18: Bool
    public var capsToQuadMod: Bool
    public var helpF19: Bool
    public var dashboardF20: Bool

    public init(
        capsToF18: Bool,
        capsToQuadMod: Bool,
        helpF19: Bool,
        dashboardF20: Bool
    ) {
        self.capsToF18 = capsToF18
        self.capsToQuadMod = capsToQuadMod
        self.helpF19 = helpF19
        self.dashboardF20 = dashboardF20
    }

    public var hasAnyCapsHyper: Bool { capsToF18 || capsToQuadMod }

    public var summary: String {
        var parts: [String] = []
        if capsToF18 { parts.append("Caps→F18") }
        if capsToQuadMod { parts.append("Caps→⌘⌃⌥⇧") }
        if helpF19 { parts.append("F19 help") }
        if dashboardF20 { parts.append("F20 dashboard") }
        return parts.isEmpty ? "No HyperForge rules detected" : parts.joined(separator: " · ")
    }
}

/// Pure config-blob analysis for Doctor / KarabinerService.
public enum KarabinerDetection {
    public static func detectRules(in blob: String) -> KarabinerRuleStatus {
        let lower = blob.lowercased()

        let capsToF18 =
            (lower.contains("caps_lock") && lower.contains("\"f18\""))
            || lower.contains("caps lock to f18")
            || lower.contains("hyperforge_caps_to_f18")
            || lower.contains("caps lock as hyper")

        // Operator precedence: `&&` binds tighter than `||` — match service logic.
        let capsToQuadMod =
            lower.contains("\"left_command\"") && lower.contains("\"left_control\"")
            && lower.contains("\"left_option\"") && lower.contains("\"left_shift\"")
            && lower.contains("caps_lock")
            || lower.contains("hyper + q to control+option+command+shift")
            || lower.contains("change caps_lock to command+control+option+shift")

        let helpF19 =
            (lower.contains("\"f19\"") && (lower.contains("slash") || lower.contains("grave")))
            || lower.contains("hyperforge_help")
            || lower.contains("hyper + /") && lower.contains("f19")

        let dashboardF20 =
            (lower.contains("\"f20\"") && lower.contains("comma"))
            || lower.contains("hyperforge_dashboard")
            || lower.contains("hyper + ,") && lower.contains("f20")

        return KarabinerRuleStatus(
            capsToF18: capsToF18,
            capsToQuadMod: capsToQuadMod,
            helpF19: helpF19,
            dashboardF20: dashboardF20
        )
    }

    public static func style(from rules: KarabinerRuleStatus, blob: String) -> HyperStyle {
        switch (rules.capsToF18, rules.capsToQuadMod) {
        case (true, true): return .mixed
        case (true, false): return .f18
        case (false, true): return .quadMod
        default:
            let lower = blob.lowercased()
            if lower.contains("\"f18\"") { return .f18 }
            return .none
        }
    }

    public static func parseActiveProfileName(from blob: String) -> String? {
        guard let data = blob.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["profiles"] as? [[String: Any]]
        else { return nil }
        if let selected = profiles.first(where: { ($0["selected"] as? Bool) == true }) {
            return selected["name"] as? String
        }
        return profiles.first?["name"] as? String
    }
}
