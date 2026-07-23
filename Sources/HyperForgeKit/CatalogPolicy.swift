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
        "sys-lock", "clip-url", "clip-plain", "clip-region-pin",
        "vim-h", "vim-j", "vim-k", "vim-l",
    ]

    /// Substrings that must never appear in default catalog text.
    /// Generic only — no real names, employers, or personal domains.
    public static let forbiddenSubstrings: [String] = [
        "TODO-PERSONAL",
        "FIXME-PII",
        // Free-mail domains in catalog text usually mean a real address leaked in.
        "@gmail.com",
        "@icloud.com",
        "@yahoo.com",
        "@hotmail.com",
        "@outlook.com",
    ]

    /// Action IDs reserved as “do not ship” placeholders (never real catalog entries).
    public static let retiredActionIDs: Set<String> = [
        "retired-personal-cloud",
        "retired-personal-vpn",
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

        let leaked = actionIDs.filter {
            $0.hasPrefix("retired-personal-") || $0.hasPrefix("prod-personal-")
        }
        if !leaked.isEmpty {
            errors.append(
                "Personal-style action IDs present: \(leaked.sorted().joined(separator: ", "))"
            )
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
