// HyperChordRouting.swift
// Pure Hyper key routing decisions (no AppKit / event tap side effects).

import Foundation

/// What Hyper+/ should do for a given Hyper style / shift state.
public enum SlashChordAction: String, Equatable, Sendable {
    case cheatSheet
    case linkHints
    case cheatSheetFallback
}

/// Profile / enable-set gating used by the engine.
public enum HyperChordRouting {
    /// Empty or nil enable set = all actions allowed (Coding profile default).
    public static func isAllowed(actionID: String, enabledIDs: Set<String>?) -> Bool {
        guard let enabledIDs, !enabledIDs.isEmpty else { return true }
        return enabledIDs.contains(actionID)
    }

    /// F18 Hyper + physical Shift (not 4-mod) is "extra" shift.
    public static func extraShift(shiftDown: Bool, hyperConsumesShift: Bool) -> Bool {
        shiftDown && !hyperConsumesShift
    }

    /// Resolve Hyper + /  (and related help vs link-hints behavior).
    public static func slashAction(
        shiftDown: Bool,
        hyperConsumesShift: Bool,
        linkHintsAllowed: Bool
    ) -> SlashChordAction {
        let extra = extraShift(shiftDown: shiftDown, hyperConsumesShift: hyperConsumesShift)
        if extra || hyperConsumesShift {
            return .cheatSheet
        }
        if linkHintsAllowed {
            return .linkHints
        }
        return .cheatSheetFallback
    }

    /// Whether a Hyper key should be treated as handled when the profile disables it.
    public static func shouldHandle(
        actionID: String,
        enabledIDs: Set<String>?
    ) -> Bool {
        isAllowed(actionID: actionID, enabledIDs: enabledIDs)
    }
}
