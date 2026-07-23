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
            "flags retired personal IDs",
            CatalogPolicy.validate(
                actionIDs: cleanIDs + ["retired-personal-cloud"],
                searchableBlob: "x"
            ).contains { $0.contains("Retired") || $0.contains("Personal-style") }
        )
        check(
            "flags free-mail address in catalog blob",
            CatalogPolicy.validate(
                actionIDs: cleanIDs,
                searchableBlob: "user@gmail.com"
            ).contains { $0.contains("Forbidden") }
        )

        print("\nModel fitness (Ollama vs RAM)")
        let fourGB: UInt64 = 4 * 1_073_741_824
        let qwen = [
            OllamaModelInfo(name: "qwen3:1.7b", sizeBytes: 1_200_000_000, parameterSize: "1.7B"),
        ]
        let tinyFit = ModelFitness.assess(
            modelName: "qwen3:1.7b",
            installed: qwen,
            physicalMemoryBytes: fourGB
        )
        check("1.7B model OK on 4 GB", tinyFit.level == .ok)
        let bigFit = ModelFitness.assess(
            modelName: "llama3.1:8b",
            installed: [
                OllamaModelInfo(name: "llama3.1:8b", sizeBytes: 4_700_000_000, parameterSize: "8B"),
            ],
            physicalMemoryBytes: fourGB
        )
        check(
            "8B model warned on 4 GB",
            bigFit.level == .tooLarge || bigFit.level == .tight
        )
        check(
            "default llama3.2 flagged on 4 GB without install list",
            ModelFitness.assess(
                modelName: "llama3.2",
                installed: [],
                physicalMemoryBytes: fourGB
            ).level == .tooLarge
        )
        check(
            "parameter hint from tag",
            ModelFitness.parameterHint(from: "qwen3:1.7b") == "1.7B"
        )

        print("\nHyper binding resolver (all chords)")
        var routeFails = 0
        for spec in HyperBindingResolver.specs {
            let route = HyperBindingResolver.resolve(
                keyCode: spec.keyCode,
                shiftDown: spec.requiresExtraShift,
                hyperConsumesShift: false,
                enabledIDs: nil
            )
            let ok: Bool
            if case .action(let id) = route, id == spec.actionID {
                ok = true
            } else {
                ok = false
                routeFails += 1
                print("  ✗ \(spec.title) → \(route) expected \(spec.actionID)")
            }
            if ok { print("  ✓ \(spec.title)") }
        }
        failed += routeFails

        // 4-mod: Shift is always held, but Hyper+T must NOT be "terminal here"
        let quadT = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.t,
            shiftDown: true,
            hyperConsumesShift: true,
            enabledIDs: nil
        )
        check("4-mod Hyper+T → app-iterm (not Finder folder)", {
            if case .action("app-iterm") = quadT { return true }
            return false
        }())

        let quadReturn = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.return,
            shiftDown: true,
            hyperConsumesShift: true,
            enabledIDs: nil
        )
        check("4-mod Hyper+Return → win-max (not tile)", {
            if case .action("win-max") = quadReturn { return true }
            return false
        }())

        let gated = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.leftArrow,
            enabledIDs: ["win-right"]
        )
        check("profile gate blocks win-left", {
            if case .unhandled = gated { return true }
            return false
        }())

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
