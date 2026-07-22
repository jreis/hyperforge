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

struct AppOverride: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    /// Actions disabled while this app is frontmost (profile still applies first).
    var disabledActionIDs: Set<String> = []
    /// Optional remaps: this key → run actionID (takes precedence over default).
    var remaps: [KeyRemap] = []
    var isEnabled: Bool = true

    var displayTitle: String {
        appName.isEmpty ? bundleID : appName
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
