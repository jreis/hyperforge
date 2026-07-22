// KarabinerService.swift
// Detect Hyper style, install HyperForge rule packs (Caps Hyper + F19/F20 bridges).

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

        let blob = loadConfigBlob()
        let rules = KarabinerDetection.detectRules(in: blob)
        ruleStatus = rules
        hyperStyle = KarabinerDetection.style(from: rules, blob: blob)
        activeProfileName = KarabinerDetection.parseActiveProfileName(from: blob)
        status = "\(rules.summary) · style: \(hyperStyle.rawValue)"
    }

    private func loadConfigBlob() -> String {
        var pieces: [String] = []
        if let main = try? String(contentsOfFile: configPath, encoding: .utf8) {
            pieces.append(main)
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: assetsDir) {
            for name in files where name.hasSuffix(".json") {
                if let s = try? String(
                    contentsOfFile: assetsDir + "/" + name,
                    encoding: .utf8
                ) {
                    pieces.append(s)
                }
            }
        }
        return pieces.joined(separator: "\n")
    }

    // MARK: - Install packs

    @discardableResult
    func installCapsToF18Rule() -> Bool {
        writeAsset(filename: "hyperforge_caps_to_f18.json", contents: Self.capsToF18AssetJSON)
    }

    @discardableResult
    func installBridgeRules() -> Bool {
        let a = writeAsset(filename: "hyperforge_help_f19.json", contents: Self.helpF19AssetJSON)
        let b = writeAsset(
            filename: "hyperforge_dashboard_f20.json",
            contents: Self.dashboardF20AssetJSON
        )
        return a && b
    }

    @discardableResult
    func installRecommendedPack() -> Bool {
        let caps = installCapsToF18Rule()
        let bridges = installBridgeRules()
        refresh()
        if caps && bridges {
            status =
                "Wrote HyperForge pack to assets — enable rules in Karabiner → Complex Modifications"
            return true
        }
        status = "Partial install — check \(assetsDir)"
        return false
    }

    @discardableResult
    func installCustomRuleAsset() -> Bool {
        do {
            try FileManager.default.createDirectory(
                atPath: assetsDir,
                withIntermediateDirectories: true
            )
            let assetPath = assetsDir + "/hyperforge_custom_rule.json"
            let asset = """
            {
              "title": "HyperForge — Custom rule",
              "rules": [
                \(ruleJSON)
              ]
            }
            """
            try asset.write(toFile: assetPath, atomically: true, encoding: .utf8)
            status = "Wrote \(assetPath) — enable in Karabiner → Complex Modifications"
            refresh()
            return true
        } catch {
            status = "Failed: \(error.localizedDescription)"
            return false
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
            status = "Wrote \(path)"
            return true
        } catch {
            status = "Failed: \(error.localizedDescription)"
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
