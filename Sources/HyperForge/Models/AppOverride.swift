// AppOverride.swift
// Per-app Hyper binding overrides — disable or remap actions when a bundle is frontmost.

import Foundation

struct KeyRemap: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// Physical key code that triggers the remap while this app is frontmost.
    var keyCode: UInt16
    /// Catalog action id to run instead of the default Hyper binding for that key.
    var actionID: String
    var note: String = ""
}

struct AppOverride: Identifiable, Equatable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    /// Actions disabled while this app is frontmost (profile still applies first).
    var disabledActionIDs: Set<String> = []
    /// Optional remaps: this key → run actionID (takes precedence over default).
    var remaps: [KeyRemap] = []
    var isEnabled: Bool = true
    /// When true, Space-layer (TouchCursor) nav is off while this app is frontmost.
    var disableSpaceNav: Bool = false

    var displayTitle: String {
        appName.isEmpty ? bundleID : appName
    }
}

extension AppOverride: Codable {
    enum CodingKeys: String, CodingKey {
        case id, bundleID, appName, disabledActionIDs, remaps, isEnabled, disableSpaceNav
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try c.decode(String.self, forKey: .bundleID)
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? bundleID
        disabledActionIDs = try c.decodeIfPresent(Set<String>.self, forKey: .disabledActionIDs) ?? []
        remaps = try c.decodeIfPresent([KeyRemap].self, forKey: .remaps) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        disableSpaceNav = try c.decodeIfPresent(Bool.self, forKey: .disableSpaceNav) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(appName, forKey: .appName)
        try c.encode(disabledActionIDs, forKey: .disabledActionIDs)
        try c.encode(remaps, forKey: .remaps)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(disableSpaceNav, forKey: .disableSpaceNav)
    }
}

extension AutoTrigger.Kind {
    var title: String {
        switch self {
        case .wifiSSID: return "Wi‑Fi network"
        case .appBundleID: return "Frontmost app"
        case .timeOfDay: return "Time of day"
        }
    }

    var symbol: String {
        switch self {
        case .wifiSSID: return "wifi"
        case .appBundleID: return "app.badge"
        case .timeOfDay: return "clock"
        }
    }

    var placeholder: String {
        switch self {
        case .wifiSSID: return "e.g. Office-Guest"
        case .appBundleID: return "e.g. com.apple.Safari"
        case .timeOfDay: return "HH:mm-HH:mm (e.g. 09:00-17:00)"
        }
    }
}
