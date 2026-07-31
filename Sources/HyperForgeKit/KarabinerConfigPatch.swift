// KarabinerConfigPatch.swift
// Pure JSON helpers to enable complex_modifications rules in karabiner.json.
// Asset files under assets/complex_modifications only appear under
// “Add predefined rule” — they are not active until pushed into the profile.
//
// Re-install is an *upsert*: matching HyperForge pack families are removed
// first so description renames / install.sh + Doctor don’t stack duplicates.

import Foundation

public enum KarabinerConfigPatchError: Error, Equatable, Sendable {
    case invalidJSON
    case notAnObject
    case noProfiles
    case assetMissingRules
}

public struct KarabinerEnableResult: Equatable, Sendable {
    /// Pack rules written to the profile.
    public let writtenCount: Int
    /// Prior HyperForge (or family-matching) rules removed before write.
    public let removedCount: Int
    public let jsonData: Data

    public init(writtenCount: Int, removedCount: Int, jsonData: Data) {
        self.writtenCount = writtenCount
        self.removedCount = removedCount
        self.jsonData = jsonData
    }

    /// Back-compat for older call sites / smoke tests.
    public var addedCount: Int { writtenCount }
    public var skippedCount: Int { 0 }
}

public enum KarabinerConfigPatch {
    /// Historical + current descriptions used by install.sh / Doctor / manual enables.
    public static let legacyDescriptions: Set<String> = [
        "Caps Lock to F18 (Hyper trigger)",
        "Caps Lock to F18 (Hyper trigger, alone = Escape)",
        "HyperForge: Caps Lock to F18 (Hyper trigger, alone = Escape)",
        "Hyper (⌘⌃⌥⇧) + / → F19 (HyperForge cheat sheet)",
        "Hyper (⌘⌃⌥⇧) + / or ` → F19 (cheat sheet)",
        "HyperForge: Hyper + / or ` → F19 (cheat sheet)",
        "Hyper (⌘⌃⌥⇧) + , → F20 (HyperForge dashboard)",
        "Hyper (⌘⌃⌥⇧) + , → F20 (show dashboard)",
        "HyperForge: Hyper + , → F20 (dashboard)",
    ]

    /// Pull the `rules` array from a complex_modifications *asset* file
    /// (`{ "title": "...", "rules": [ { description, manipulators } ] }`).
    public static func rulesFromAssetJSON(_ json: String) throws -> [[String: Any]] {
        guard let data = json.data(using: .utf8) else {
            throw KarabinerConfigPatchError.invalidJSON
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KarabinerConfigPatchError.notAnObject
        }
        guard let rules = root["rules"] as? [[String: Any]], !rules.isEmpty else {
            throw KarabinerConfigPatchError.assetMissingRules
        }
        return rules
    }

    /// Descriptions currently enabled on the selected profile.
    public static func enabledRuleDescriptions(inKarabinerJSON data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KarabinerConfigPatchError.notAnObject
        }
        guard let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else {
            throw KarabinerConfigPatchError.noProfiles
        }
        let selected =
            profiles.first(where: { ($0["selected"] as? Bool) == true })
            ?? profiles[0]
        let complex = selected["complex_modifications"] as? [String: Any] ?? [:]
        let rules = complex["rules"] as? [[String: Any]] ?? []
        return rules.compactMap { $0["description"] as? String }
    }

    /// Classify a rule as a HyperForge pack family (`caps_f18`, `help_f19`,
    /// `dashboard_f20`, `hyperforge_other`) or `nil` if unrelated.
    public static func ruleFamily(_ rule: [String: Any]) -> String? {
        let desc = (rule["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = desc.lowercased()
        let blob = manipulatorBlob(rule)

        if lower.contains("f18"), lower.contains("caps") {
            return "caps_f18"
        }
        if lower.contains("f19"),
           ["/", "slash", "help", "cheat", "grave", "`", "keybinding"].contains(where: {
               lower.contains($0)
           })
        {
            return "help_f19"
        }
        if lower.contains("f20"),
           [",", "comma", "dashboard"].contains(where: { lower.contains($0) })
        {
            return "dashboard_f20"
        }

        if blob.contains("caps_lock"), blob.contains("f18") {
            return "caps_f18"
        }
        if blob.contains("f19"), blob.contains("slash") || blob.contains("grave") {
            return "help_f19"
        }
        if blob.contains("f20"), blob.contains("comma") {
            return "dashboard_f20"
        }

        if legacyDescriptions.contains(desc) || lower.hasPrefix("hyperforge") {
            return "hyperforge_other"
        }
        return nil
    }

    /// Upsert pack `rules` into the selected profile: strip same-family HyperForge
    /// rules first, then prepend the new pack. Idempotent across renames.
    public static func enableRules(
        inKarabinerJSON data: Data,
        rules: [[String: Any]]
    ) throws -> KarabinerEnableResult {
        guard !rules.isEmpty else {
            return KarabinerEnableResult(writtenCount: 0, removedCount: 0, jsonData: data)
        }

        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KarabinerConfigPatchError.notAnObject
        }
        guard var profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else {
            throw KarabinerConfigPatchError.noProfiles
        }

        let selectedIndex =
            profiles.firstIndex(where: { ($0["selected"] as? Bool) == true })
            ?? profiles.startIndex

        var profile = profiles[selectedIndex]
        var complex = profile["complex_modifications"] as? [String: Any] ?? [:]
        let existing = complex["rules"] as? [[String: Any]] ?? []

        var pack: [[String: Any]] = []
        for rule in rules {
            var copy = rule
            if (copy["description"] as? String)?.isEmpty != false {
                copy["description"] = "HyperForge rule"
            }
            pack.append(copy)
        }

        var packFamilies = Set(pack.compactMap { ruleFamily($0) })
        // Always scrub unknown HyperForge leftovers when installing our pack.
        packFamilies.insert("hyperforge_other")

        var kept: [[String: Any]] = []
        var removed = 0
        for rule in existing {
            if let fam = ruleFamily(rule), packFamilies.contains(fam) {
                removed += 1
                continue
            }
            kept.append(rule)
        }

        complex["rules"] = pack + kept
        profile["complex_modifications"] = complex
        profiles[selectedIndex] = profile
        root["profiles"] = profiles

        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        return KarabinerEnableResult(
            writtenCount: pack.count,
            removedCount: removed,
            jsonData: out
        )
    }

    /// Parse one or more asset JSON strings and upsert all their rules.
    public static func enableAssetPacks(
        inKarabinerJSON data: Data,
        assetJSONStrings: [String]
    ) throws -> KarabinerEnableResult {
        var allRules: [[String: Any]] = []
        for asset in assetJSONStrings {
            allRules.append(contentsOf: try rulesFromAssetJSON(asset))
        }
        return try enableRules(inKarabinerJSON: data, rules: allRules)
    }

    // MARK: - Private

    private static func manipulatorBlob(_ rule: [String: Any]) -> String {
        guard let mans = rule["manipulators"],
              let data = try? JSONSerialization.data(withJSONObject: mans),
              let s = String(data: data, encoding: .utf8)
        else { return "" }
        return s.lowercased()
    }
}
