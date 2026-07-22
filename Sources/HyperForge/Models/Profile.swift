// Profile.swift
// Switchable work modes that bundle Hyper actions, Karabiner rules, and layouts.

import Foundation

struct WorkspaceLayout: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var windows: [WindowManager.WindowSnapshot]
    var createdAt: Date = Date()
}

struct AutoTrigger: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case wifiSSID
        case appBundleID
        case timeOfDay
    }

    var id: UUID = UUID()
    var kind: Kind
    var value: String
    var profileID: UUID
    var isEnabled: Bool = true
}

struct HyperProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var accentHex: UInt
    var notes: String
    /// Action IDs that are enabled in this profile. Empty = all defaults.
    var enabledActionIDs: Set<String>
    var layouts: [WorkspaceLayout]
    var karabinerRuleJSON: String
    var isBuiltIn: Bool

    static let defaultKarabiner = """
    {
      "description": "Caps Lock to F18 (Hyper trigger)",
      "manipulators": [
        {
          "from": { "key_code": "caps_lock" },
          "to": [{ "key_code": "f18" }],
          "to_if_alone": [{ "key_code": "escape" }],
          "type": "basic"
        }
      ]
    }
    """

    static let builtIns: [HyperProfile] = [
        HyperProfile(
            name: "Coding",
            symbol: "chevron.left.forwardslash.chevron.right",
            accentHex: 0x5B8DEF,
            notes: "Full Hyper set + terminal + editors.",
            enabledActionIDs: [],
            layouts: [],
            karabinerRuleJSON: defaultKarabiner,
            isBuiltIn: true
        ),
        HyperProfile(
            name: "Browsing",
            symbol: "globe",
            accentHex: 0x34C759,
            notes: "Scroll-heavy + app launchers, lighter productivity.",
            enabledActionIDs: Set(
                ActionCatalog.defaults
                    .filter { [.scroll, .apps, .window, .vim].contains($0.category) }
                    .map(\.id)
            ),
            layouts: [],
            karabinerRuleJSON: defaultKarabiner,
            isBuiltIn: true
        ),
        HyperProfile(
            name: "Music",
            symbol: "music.note",
            accentHex: 0xBF5AF2,
            notes: "Minimal bindings; keep focus on the mix.",
            enabledActionIDs: Set(
                ActionCatalog.defaults
                    .filter { [.window, .system].contains($0.category) }
                    .map(\.id)
            ),
            layouts: [],
            karabinerRuleJSON: defaultKarabiner,
            isBuiltIn: true
        ),
        HyperProfile(
            name: "Minimal",
            symbol: "circle.grid.2x1",
            accentHex: 0x8E8E93,
            notes: "Window snaps + lock only.",
            enabledActionIDs: Set([
                "win-left", "win-right", "win-top", "win-bottom", "win-max",
                "win-center", "sys-lock", "app-toggle",
            ]),
            layouts: [],
            karabinerRuleJSON: defaultKarabiner,
            isBuiltIn: true
        ),
    ]
}
