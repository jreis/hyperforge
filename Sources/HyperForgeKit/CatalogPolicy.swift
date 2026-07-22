// CatalogPolicy.swift
// Invariants for the Hyper action catalog (smoke-tested).

import Foundation

public enum CatalogPolicy {
    /// Core actions that must exist for a usable HyperForge build.
    public static let requiredActionIDs: Set<String> = [
        "win-left", "win-right", "win-top", "win-bottom", "win-max",
        "win-tile-all", "win-close",
        "scroll-left", "scroll-down", "scroll-right",
        "app-chrome", "app-iterm", "prod-keepalive", "prod-shell", "prod-note",
        "sys-command-bar", "sys-dashboard", "sys-cheatsheet", "sys-link-hints",
        "sys-lock", "clip-url", "clip-plain",
        "vim-h", "vim-j", "vim-k", "vim-l",
    ]

    /// Substrings that must never appear in default catalog text (PII / work-specific).
    public static let forbiddenSubstrings: [String] = [
        "jason@",
        "jasonreis",
        "OptumServe",
        "osit-azure",
        "prod-azure",
        "@gmail.com",
        "Thanks,\nJason",
    ]

    /// Actions that were personal and must not ship as default IDs.
    public static let retiredActionIDs: Set<String> = [
        "prod-azure",
    ]

    public static func validate(
        actionIDs: [String],
        searchableBlob: String
    ) -> [String] {
        var errors: [String] = []
        let idSet = Set(actionIDs)

        if actionIDs.count != idSet.count {
            errors.append("Duplicate action IDs in catalog")
        }

        let missing = requiredActionIDs.subtracting(idSet).sorted()
        if !missing.isEmpty {
            errors.append("Missing required IDs: \(missing.joined(separator: ", "))")
        }

        let retired = retiredActionIDs.intersection(idSet).sorted()
        if !retired.isEmpty {
            errors.append("Retired personal IDs still present: \(retired.joined(separator: ", "))")
        }

        let lower = searchableBlob.lowercased()
        for needle in forbiddenSubstrings {
            if lower.contains(needle.lowercased()) {
                errors.append("Forbidden personal content: \(needle)")
            }
        }

        return errors
    }
}
