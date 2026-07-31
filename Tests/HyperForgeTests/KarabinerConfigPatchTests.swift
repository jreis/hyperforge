import XCTest
@testable import HyperForgeKit

final class KarabinerConfigPatchTests: XCTestCase {
    private let emptyProfileJSON = """
    {
      "profiles": [
        {
          "name": "Default profile",
          "selected": true,
          "virtual_hid_keyboard": { "keyboard_type_v2": "ansi" }
        }
      ]
    }
    """

    private let capsAsset = """
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

    private let capsAssetLegacy = """
    {
      "title": "HyperForge — Caps Lock as Hyper",
      "rules": [
        {
          "description": "Caps Lock to F18 (Hyper trigger)",
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

    private let helpAsset = """
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
            }
          ]
        }
      ]
    }
    """

    func testRulesFromAssetJSON() throws {
        let rules = try KarabinerConfigPatch.rulesFromAssetJSON(capsAsset)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(
            rules[0]["description"] as? String,
            "Caps Lock to F18 (Hyper trigger, alone = Escape)"
        )
    }

    func testEnableRulesOnEmptyProfile() throws {
        let data = Data(emptyProfileJSON.utf8)
        let result = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: data,
            assetJSONStrings: [capsAsset, helpAsset]
        )
        XCTAssertEqual(result.writtenCount, 2)
        XCTAssertEqual(result.removedCount, 0)

        let descs = try KarabinerConfigPatch.enabledRuleDescriptions(
            inKarabinerJSON: result.jsonData
        )
        XCTAssertEqual(descs.count, 2)
        XCTAssertTrue(descs.contains("Caps Lock to F18 (Hyper trigger, alone = Escape)"))
        XCTAssertTrue(descs.contains("Hyper (⌘⌃⌥⇧) + / or ` → F19 (cheat sheet)"))

        let blob = String(data: result.jsonData, encoding: .utf8)!
        let status = KarabinerDetection.detectRules(in: blob)
        XCTAssertTrue(status.capsToF18)
        XCTAssertTrue(status.helpF19)
    }

    func testReinstallReplacesInsteadOfDuplicating() throws {
        let data = Data(emptyProfileJSON.utf8)
        let first = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: data,
            assetJSONStrings: [capsAsset]
        )
        XCTAssertEqual(first.writtenCount, 1)

        let second = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: first.jsonData,
            assetJSONStrings: [capsAsset, helpAsset]
        )
        XCTAssertEqual(second.writtenCount, 2)
        XCTAssertEqual(second.removedCount, 1)

        let descs = try KarabinerConfigPatch.enabledRuleDescriptions(
            inKarabinerJSON: second.jsonData
        )
        XCTAssertEqual(descs.count, 2)
    }

    func testLegacyDescriptionIsReplacedNotDuplicated() throws {
        let data = Data(emptyProfileJSON.utf8)
        let legacy = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: data,
            assetJSONStrings: [capsAssetLegacy]
        )
        let modern = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: legacy.jsonData,
            assetJSONStrings: [capsAsset]
        )
        XCTAssertEqual(modern.writtenCount, 1)
        XCTAssertEqual(modern.removedCount, 1)
        let descs = try KarabinerConfigPatch.enabledRuleDescriptions(
            inKarabinerJSON: modern.jsonData
        )
        XCTAssertEqual(descs, ["Caps Lock to F18 (Hyper trigger, alone = Escape)"])
    }

    func testEnablesSelectedProfileNotOthers() throws {
        let multi = """
        {
          "profiles": [
            { "name": "Other", "selected": false, "complex_modifications": { "rules": [] } },
            { "name": "Work", "selected": true }
          ]
        }
        """
        let result = try KarabinerConfigPatch.enableAssetPacks(
            inKarabinerJSON: Data(multi.utf8),
            assetJSONStrings: [capsAsset]
        )
        let root = try JSONSerialization.jsonObject(with: result.jsonData) as! [String: Any]
        let profiles = root["profiles"] as! [[String: Any]]
        let other = profiles[0]
        let work = profiles[1]
        let otherRules =
            (other["complex_modifications"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let workRules =
            (work["complex_modifications"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        XCTAssertEqual(otherRules.count, 0)
        XCTAssertEqual(workRules.count, 1)
    }

    func testMissingRulesAssetThrows() {
        let bad = #"{ "title": "Empty", "rules": [] }"#
        XCTAssertThrowsError(try KarabinerConfigPatch.rulesFromAssetJSON(bad))
    }

    func testRuleFamilyClassification() {
        let caps: [String: Any] = [
            "description": "Caps Lock to F18 (Hyper trigger)",
            "manipulators": [
                ["from": ["key_code": "caps_lock"], "to": [["key_code": "f18"]]],
            ],
        ]
        XCTAssertEqual(KarabinerConfigPatch.ruleFamily(caps), "caps_f18")
    }
}
