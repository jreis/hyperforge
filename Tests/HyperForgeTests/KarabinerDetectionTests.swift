import XCTest
@testable import HyperForgeKit

final class KarabinerDetectionTests: XCTestCase {
    func testEmptyBlobIsNone() {
        let rules = KarabinerDetection.detectRules(in: "")
        XCTAssertFalse(rules.hasAnyCapsHyper)
        XCTAssertEqual(KarabinerDetection.style(from: rules, blob: ""), .none)
    }

    func testCapsToF18Asset() {
        let blob = """
        {
          "title": "HyperForge — Caps Lock as Hyper",
          "rules": [{
            "description": "Caps Lock to F18 (Hyper trigger)",
            "manipulators": [{
              "from": { "key_code": "caps_lock" },
              "to": [{ "key_code": "f18" }],
              "to_if_alone": [{ "key_code": "escape" }]
            }]
          }]
        }
        """
        let rules = KarabinerDetection.detectRules(in: blob)
        XCTAssertTrue(rules.capsToF18)
        XCTAssertFalse(rules.capsToQuadMod)
        XCTAssertEqual(KarabinerDetection.style(from: rules, blob: blob), .f18)
    }

    func testQuadModCaps() {
        let blob = """
        caps_lock maps to
        "left_command" "left_control" "left_option" "left_shift"
        alone escape
        """
        let rules = KarabinerDetection.detectRules(in: blob)
        XCTAssertTrue(rules.capsToQuadMod)
        XCTAssertFalse(rules.capsToF18)
        XCTAssertEqual(KarabinerDetection.style(from: rules, blob: blob), .quadMod)
    }

    func testF19HelpAndF20Dashboard() {
        let blob = """
        Hyper + / help hyperforge_help "f19" slash
        Hyper + , dashboard hyperforge_dashboard "f20" comma
        """
        let rules = KarabinerDetection.detectRules(in: blob)
        XCTAssertTrue(rules.helpF19)
        XCTAssertTrue(rules.dashboardF20)
    }

    func testMixedStyles() {
        let blob = """
        caps_lock "f18"
        caps_lock "left_command" "left_control" "left_option" "left_shift"
        """
        let rules = KarabinerDetection.detectRules(in: blob)
        XCTAssertTrue(rules.capsToF18)
        XCTAssertTrue(rules.capsToQuadMod)
        XCTAssertEqual(KarabinerDetection.style(from: rules, blob: blob), .mixed)
    }

    func testParseActiveProfileName() {
        let blob = """
        {
          "profiles": [
            { "name": "Default", "selected": false },
            { "name": "Work", "selected": true }
          ]
        }
        """
        XCTAssertEqual(KarabinerDetection.parseActiveProfileName(from: blob), "Work")
    }

    func testRuleStatusSummary() {
        let status = KarabinerRuleStatus(
            capsToF18: true,
            capsToQuadMod: false,
            helpF19: true,
            dashboardF20: false
        )
        XCTAssertEqual(status.summary, "Caps→F18 · F19 help")
    }
}
