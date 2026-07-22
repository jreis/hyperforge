// DashboardWindowPolicy.swift
// Pure rules for recognizing the main HyperForge dashboard among NSWindows.

import Foundation

/// Snapshot of window traits used to identify the dashboard without AppKit types.
public struct WindowTraits: Equatable, Sendable {
    public var title: String
    public var width: CGFloat
    public var height: CGFloat
    public var isBorderless: Bool
    public var isNormalOrFloatingLevel: Bool
    public var identifier: String?

    public init(
        title: String,
        width: CGFloat,
        height: CGFloat,
        isBorderless: Bool,
        isNormalOrFloatingLevel: Bool,
        identifier: String? = nil
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.isBorderless = isBorderless
        self.isNormalOrFloatingLevel = isNormalOrFloatingLevel
        self.identifier = identifier
    }
}

public enum DashboardWindowPolicy {
    /// Stable NSWindow.identifier / accessibility marker for the main UI.
    public static let dashboardIdentifier = "hyperforge.main.dashboard"
    public static let dashboardTitlePrefix = "HyperForge"
    public static let minWidth: CGFloat = 700
    public static let minHeight: CGFloat = 400

    public static func isDashboard(_ w: WindowTraits) -> Bool {
        if let id = w.identifier, id == dashboardIdentifier {
            return true
        }
        guard w.isNormalOrFloatingLevel else { return false }
        // Cheat sheet is titled explicitly
        if w.title.contains("Keybindings") { return false }
        // HUD / banner toasts are small borderless
        if w.isBorderless, w.height < 100 { return false }
        // Prefer titled main chrome when present
        if w.title.hasPrefix(dashboardTitlePrefix), !w.title.contains("Keybindings") {
            return w.width >= minWidth && w.height >= minHeight
        }
        return w.width >= minWidth && w.height >= minHeight
    }
}
