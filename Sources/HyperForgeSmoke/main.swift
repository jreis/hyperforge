// HyperForgeSmoke — Command Line Tools–friendly smoke tests (no XCTest / Xcode required).
// Run: swift run HyperForgeSmoke

import Foundation
import HyperForgeKit

@main
struct HyperForgeSmoke {
    static func main() {
        var failed = 0

        func check(_ name: String, _ ok: @autoclosure () -> Bool) {
            if ok() {
                print("  ✓ \(name)")
            } else {
                print("  ✗ \(name)")
                failed += 1
            }
        }

        print("HyperForgeKit smoke tests\n")

        print("Karabiner detection")
        let empty = KarabinerDetection.detectRules(in: "")
        check("empty blob has no caps hyper", !empty.hasAnyCapsHyper)
        check("empty style is none", KarabinerDetection.style(from: empty, blob: "") == .none)

        let f18Blob = #"""
        caps_lock "f18" Caps Lock to F18
        """#
        let f18 = KarabinerDetection.detectRules(in: f18Blob)
        check("detects Caps→F18", f18.capsToF18)
        check("F18 style", KarabinerDetection.style(from: f18, blob: f18Blob) == .f18)

        let quadBlob = #"""
        caps_lock "left_command" "left_control" "left_option" "left_shift"
        """#
        let quad = KarabinerDetection.detectRules(in: quadBlob)
        check("detects 4-mod Caps", quad.capsToQuadMod)
        check("quad style", KarabinerDetection.style(from: quad, blob: quadBlob) == .quadMod)

        let bridges = KarabinerDetection.detectRules(
            in: #"hyperforge_help "f19" slash hyperforge_dashboard "f20" comma"#
        )
        check("detects F19 help", bridges.helpF19)
        check("detects F20 dashboard", bridges.dashboardF20)

        let mixedBlob = #"caps_lock "f18" caps_lock "left_command" "left_control" "left_option" "left_shift""#
        let mixed = KarabinerDetection.detectRules(in: mixedBlob)
        check(
            "mixed styles",
            KarabinerDetection.style(from: mixed, blob: mixedBlob) == .mixed
        )

        let profileJSON = #"""
        {"profiles":[{"name":"Default","selected":false},{"name":"Work","selected":true}]}
        """#
        check(
            "active profile name",
            KarabinerDetection.parseActiveProfileName(from: profileJSON) == "Work"
        )

        print("\nHyper chord routing")
        check(
            "nil enable set allows all",
            HyperChordRouting.isAllowed(actionID: "win-left", enabledIDs: nil)
        )
        check(
            "profile gates actions",
            !HyperChordRouting.isAllowed(actionID: "prod-keepalive", enabledIDs: ["win-left"])
        )
        check(
            "F18 plain / → link hints",
            HyperChordRouting.slashAction(
                shiftDown: false,
                hyperConsumesShift: false,
                linkHintsAllowed: true
            ) == .linkHints
        )
        check(
            "F18 ⇧/ → cheat sheet",
            HyperChordRouting.slashAction(
                shiftDown: true,
                hyperConsumesShift: false,
                linkHintsAllowed: true
            ) == .cheatSheet
        )
        check(
            "4-mod / → cheat sheet",
            HyperChordRouting.slashAction(
                shiftDown: true,
                hyperConsumesShift: true,
                linkHintsAllowed: true
            ) == .cheatSheet
        )
        check(
            "hints off → cheat sheet fallback",
            HyperChordRouting.slashAction(
                shiftDown: false,
                hyperConsumesShift: false,
                linkHintsAllowed: false
            ) == .cheatSheetFallback
        )

        print("\nDashboard window policy")
        check(
            "identifier match",
            DashboardWindowPolicy.isDashboard(
                WindowTraits(
                    title: "x",
                    width: 10,
                    height: 10,
                    isBorderless: true,
                    isNormalOrFloatingLevel: false,
                    identifier: DashboardWindowPolicy.dashboardIdentifier
                )
            )
        )
        check(
            "rejects Keybindings sheet",
            !DashboardWindowPolicy.isDashboard(
                WindowTraits(
                    title: "HyperForge — Keybindings",
                    width: 740,
                    height: 580,
                    isBorderless: false,
                    isNormalOrFloatingLevel: true
                )
            )
        )
        check(
            "rejects banner toast",
            !DashboardWindowPolicy.isDashboard(
                WindowTraits(
                    title: "",
                    width: 300,
                    height: 44,
                    isBorderless: true,
                    isNormalOrFloatingLevel: true
                )
            )
        )
        check(
            "accepts main chrome",
            DashboardWindowPolicy.isDashboard(
                WindowTraits(
                    title: "HyperForge",
                    width: 1100,
                    height: 720,
                    isBorderless: false,
                    isNormalOrFloatingLevel: true
                )
            )
        )

        print("\nCatalog policy")
        let cleanIDs = Array(CatalogPolicy.requiredActionIDs)
        check(
            "clean catalog validates",
            CatalogPolicy.validate(actionIDs: cleanIDs, searchableBlob: "Snap Left").isEmpty
        )
        check(
            "flags missing IDs",
            !CatalogPolicy.validate(actionIDs: ["win-left"], searchableBlob: "x").isEmpty
        )
        check(
            "flags retired prod-azure",
            CatalogPolicy.validate(
                actionIDs: cleanIDs + ["prod-azure"],
                searchableBlob: "x"
            ).contains { $0.contains("Retired") }
        )
        check(
            "flags personal email blob",
            CatalogPolicy.validate(
                actionIDs: cleanIDs,
                searchableBlob: "jason@example.com"
            ).contains { $0.contains("Forbidden") }
        )

        print()
        if failed == 0 {
            print("All smoke tests passed.")
            exit(0)
        } else {
            print("\(failed) smoke test(s) failed.")
            exit(1)
        }
    }
}
