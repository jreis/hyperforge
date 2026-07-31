// KarabinerService.swift
// Detect Hyper style, install HyperForge rule packs (Caps Hyper + F19/F20 bridges).
//
// Important: copying JSON into assets/complex_modifications only makes rules
// available under Karabiner → Complex Modifications → “Add predefined rule”.
// They are not active until enabled on a profile. Doctor therefore also writes
// the rules into karabiner.json so they show up and work immediately.

import AppKit
import Combine
import Foundation
import HyperForgeKit

@MainActor
final class KarabinerService: ObservableObject {
    static let shared = KarabinerService()

    @Published private(set) var isInstalled = false
    @Published private(set) var status = "Not checked"
    @Published private(set) var hyperStyle: HyperStyle = .none
    @Published private(set) var ruleStatus = KarabinerRuleStatus(
        capsToF18: false,
        capsToQuadMod: false,
        helpF19: false,
        dashboardF20: false
    )
    @Published private(set) var activeProfileName: String?
    @Published var ruleJSON: String = HyperProfile.defaultKarabiner

    private let configPath =
        NSHomeDirectory() + "/.config/karabiner/karabiner.json"
    private let assetsDir =
        NSHomeDirectory() + "/.config/karabiner/assets/complex_modifications"

    private init() {
        refresh()
    }

    // MARK: - Refresh / detect

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: configPath)
        guard isInstalled else {
            status = "Karabiner-Elements not detected"
            hyperStyle = .none
            ruleStatus = KarabinerRuleStatus(
                capsToF18: false,
                capsToQuadMod: false,
                helpF19: false,
                dashboardF20: false
            )
            activeProfileName = nil
            return
        }

        // Only scan the live config — asset files are not enabled until
        // pushed into a profile (or added via “Add predefined rule”).
        let blob = loadConfigBlob()
        let rules = KarabinerDetection.detectRules(in: blob)
        ruleStatus = rules
        hyperStyle = KarabinerDetection.style(from: rules, blob: blob)
        activeProfileName = KarabinerDetection.parseActiveProfileName(from: blob)
        status = "\(rules.summary) · style: \(hyperStyle.rawValue)"
    }

    private func loadConfigBlob() -> String {
        (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
    }

    // MARK: - Install packs

    @discardableResult
    func installCapsToF18Rule() -> Bool {
        installAndEnable(
            assets: [("hyperforge_caps_to_f18.json", Self.capsToF18AssetJSON)]
        )
    }

    @discardableResult
    func installBridgeRules() -> Bool {
        installAndEnable(
            assets: [
                ("hyperforge_help_f19.json", Self.helpF19AssetJSON),
                ("hyperforge_dashboard_f20.json", Self.dashboardF20AssetJSON),
            ]
        )
    }

    @discardableResult
    func installRecommendedPack() -> Bool {
        installAndEnable(
            assets: [
                ("hyperforge_caps_to_f18.json", Self.capsToF18AssetJSON),
                ("hyperforge_help_f19.json", Self.helpF19AssetJSON),
                ("hyperforge_dashboard_f20.json", Self.dashboardF20AssetJSON),
            ]
        )
    }

    @discardableResult
    func installCustomRuleAsset() -> Bool {
        let asset = """
        {
          "title": "HyperForge — Custom rule",
          "rules": [
            \(ruleJSON)
          ]
        }
        """
        return installAndEnable(
            assets: [("hyperforge_custom_rule.json", asset)]
        )
    }

    /// Write asset files *and* enable their rules on the selected Karabiner profile.
    @discardableResult
    private func installAndEnable(assets: [(filename: String, contents: String)]) -> Bool {
        guard FileManager.default.fileExists(atPath: configPath) else {
            // Still drop assets so a later Karabiner install can pick them up.
            var wroteAny = false
            for (name, json) in assets {
                if writeAsset(filename: name, contents: json) { wroteAny = true }
            }
            status = wroteAny
                ? "Wrote assets — install Karabiner-Elements, then re-run this"
                : "Karabiner not found and asset write failed"
            refresh()
            return false
        }

        var assetOK = true
        for (name, json) in assets {
            if !writeAsset(filename: name, contents: json) { assetOK = false }
        }

        do {
            let original = try Data(contentsOf: URL(fileURLWithPath: configPath))
            try backupConfigIfNeeded(original)

            let result = try KarabinerConfigPatch.enableAssetPacks(
                inKarabinerJSON: original,
                assetJSONStrings: assets.map(\.contents)
            )

            // Always write: upsert may replace in place even when counts match.
            try result.jsonData.write(
                to: URL(fileURLWithPath: configPath),
                options: .atomic
            )

            refresh()

            if result.writtenCount > 0 {
                if result.removedCount > 0 {
                    status =
                        "Updated \(result.writtenCount) Karabiner rule(s)"
                        + " (replaced \(result.removedCount) old/duplicate)"
                } else {
                    status = "Enabled \(result.writtenCount) rule(s) in Karabiner"
                }
                if !assetOK { status += " · some asset copies failed" }
            } else {
                status = "No rules to enable"
            }
            return assetOK
        } catch {
            status = "Assets written, but enabling failed: \(error.localizedDescription)"
            refresh()
            return false
        }
    }

    /// One-time sibling backup so a bad write is recoverable.
    private func backupConfigIfNeeded(_ data: Data) throws {
        let backupPath = configPath + ".hyperforge-backup"
        if !FileManager.default.fileExists(atPath: backupPath) {
            try data.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
        }
    }

    @discardableResult
    private func writeAsset(filename: String, contents: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                atPath: assetsDir,
                withIntermediateDirectories: true
            )
            let path = assetsDir + "/" + filename
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            status = "Failed writing asset: \(error.localizedDescription)"
            return false
        }
    }

    func openKarabinerSettings() {
        let candidates = [
            "/Applications/Karabiner-Elements.app",
            "/Applications/Karabiner-EventViewer.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        if let url = URL(string: "https://karabiner-elements.pqrs.org") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAssetsFolder() {
        let url = URL(fileURLWithPath: assetsDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pack JSON (mirrors Config/)

    static let capsToF18AssetJSON = """
    {
      "title": "HyperForge — Caps Lock as Hyper (F18)",
      "rules": [
        {
          "description": "Caps Lock to F18 (Hyper trigger, alone = Escape)",
          "manipulators": [
            {
              "type": "basic",
              "from": { "key_code": "caps_lock" },
              "to": [{ "key_code": "f18" }],
              "to_if_alone": [{ "key_code": "escape" }]
            }
          ]
        }
      ]
    }
    """

    static let helpF19AssetJSON = """
    {
      "title": "HyperForge — Hyper + / help (F19)",
      "rules": [
        {
          "description": "Hyper (⌘⌃⌥⇧) + / or ` → F19 (cheat sheet)",
          "manipulators": [
            {
              "type": "basic",
              "from": {
                "key_code": "slash",
                "modifiers": {
                  "mandatory": ["command", "control", "option", "shift"]
                }
              },
              "to": [{ "key_code": "f19" }]
            },
            {
              "type": "basic",
              "from": {
                "key_code": "slash",
                "modifiers": {
                  "mandatory": [
                    "left_command", "left_control", "left_option", "left_shift"
                  ]
                }
              },
              "to": [{ "key_code": "f19" }]
            },
            {
              "type": "basic",
              "from": {
                "key_code": "grave_accent_and_tilde",
                "modifiers": {
                  "mandatory": ["command", "control", "option", "shift"]
                }
              },
              "to": [{ "key_code": "f19" }]
            }
          ]
        }
      ]
    }
    """

    static let dashboardF20AssetJSON = """
    {
      "title": "HyperForge — Hyper + , dashboard (F20)",
      "rules": [
        {
          "description": "Hyper (⌘⌃⌥⇧) + , → F20 (show dashboard)",
          "manipulators": [
            {
              "type": "basic",
              "from": {
                "key_code": "comma",
                "modifiers": {
                  "mandatory": ["command", "control", "option", "shift"]
                }
              },
              "to": [{ "key_code": "f20" }]
            },
            {
              "type": "basic",
              "from": {
                "key_code": "comma",
                "modifiers": {
                  "mandatory": [
                    "left_command", "left_control", "left_option", "left_shift"
                  ]
                }
              },
              "to": [{ "key_code": "f20" }]
            }
          ]
        }
      ]
    }
    """
}
