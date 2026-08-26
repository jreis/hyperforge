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

        print("\nKarabiner config patch")
        let emptyProfile = #"""
        {"profiles":[{"name":"Default profile","selected":true}]}
        """#
        let capsAsset = #"""
        {"title":"T","rules":[{"description":"Caps Lock to F18 (Hyper trigger, alone = Escape)","manipulators":[{"type":"basic","from":{"key_code":"caps_lock"},"to":[{"key_code":"f18"}]}]}]}
        """#
        let capsAssetLegacy = #"""
        {"title":"T","rules":[{"description":"Caps Lock to F18 (Hyper trigger)","manipulators":[{"type":"basic","from":{"key_code":"caps_lock"},"to":[{"key_code":"f18"}],"to_if_alone":[{"key_code":"escape"}]}]}]}
        """#
        do {
            let enabled = try KarabinerConfigPatch.enableAssetPacks(
                inKarabinerJSON: Data(emptyProfile.utf8),
                assetJSONStrings: [capsAsset]
            )
            check("enable writes 1 rule", enabled.writtenCount == 1)
            let descs = try KarabinerConfigPatch.enabledRuleDescriptions(
                inKarabinerJSON: enabled.jsonData
            )
            check("enabled description present", descs.count == 1)
            let again = try KarabinerConfigPatch.enableAssetPacks(
                inKarabinerJSON: enabled.jsonData,
                assetJSONStrings: [capsAsset]
            )
            check(
                "re-enable replaces same family",
                again.writtenCount == 1 && again.removedCount == 1
            )
            let renamed = try KarabinerConfigPatch.enableAssetPacks(
                inKarabinerJSON: again.jsonData,
                assetJSONStrings: [capsAssetLegacy]
            )
            let afterRename = try KarabinerConfigPatch.enabledRuleDescriptions(
                inKarabinerJSON: renamed.jsonData
            )
            check(
                "legacy description upsert is single rule",
                renamed.writtenCount == 1 && renamed.removedCount == 1 && afterRename.count == 1
            )
            let status = KarabinerDetection.detectRules(
                in: String(data: enabled.jsonData, encoding: .utf8) ?? ""
            )
            check("enabled config detects Caps→F18", status.capsToF18)
        } catch {
            check("config patch threw: \(error)", false)
        }

        print("\nHyper binding resolver (0.5 features)")
        check(
            "left third on minus",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.minus) == .action("win-third-left")
        )
        check(
            "left two-thirds on ⇧minus",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.minus,
                shiftDown: true,
                hyperConsumesShift: false
            ) == .action("win-two-thirds-left")
        )
        check(
            "almost max on ⇧backslash",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.backslash,
                shiftDown: true,
                hyperConsumesShift: false
            ) == .action("win-almost-max")
        )
        check(
            "prev display on [",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.leftBracket)
                == .action("win-prev-screen")
        )
        check(
            "OCR on O",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.o) == .action("clip-ocr")
        )
        check(
            "history on V",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.v) == .action("clip-history")
        )
        check(
            "history on ⇧V (F18)",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.v,
                shiftDown: true,
                hyperConsumesShift: false
            ) == .action("clip-history")
        )
        check(
            "history on V with 4-mod",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.v,
                shiftDown: true,
                hyperConsumesShift: true
            ) == .action("clip-history")
        )
        check(
            "warp mouse on W",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.w) == .action("win-warp-mouse")
        )
        check(
            "AX recipes on Y",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.y) == .action("sys-recipes")
        )
        check(
            "scripts on ⇧Y",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.y,
                shiftDown: true,
                hyperConsumesShift: false
            ) == .action("sys-scripts")
        )
        check(
            "scroll right on L",
            HyperBindingResolver.resolve(keyCode: HyperKeyCode.l) == .action("scroll-right")
        )
        check(
            "workspaces on ⇧L",
            HyperBindingResolver.resolve(
                keyCode: HyperKeyCode.l,
                shiftDown: true,
                hyperConsumesShift: false
            ) == .action("sys-workspaces")
        )
        check(
            "every spec still resolves",
            HyperBindingResolver.specs.allSatisfy { spec in
                if case .action(let id) = HyperBindingResolver.resolve(
                    keyCode: spec.keyCode,
                    shiftDown: spec.requiresExtraShift,
                    hyperConsumesShift: false
                ) {
                    return id == spec.actionID
                }
                return false
            }
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

        print("\nFuzzy match (command-bar launcher)")
        check("empty query matches with zero score", FuzzyMatch.score(query: "", candidate: "anything") == 0)
        check(
            "ordered subsequence matches",
            FuzzyMatch.score(query: "snap left", candidate: "Snap Left Half") != nil
        )
        check(
            "out-of-order characters do not match",
            FuzzyMatch.score(query: "left snap", candidate: "Snap Left Half") == nil
        )
        check(
            "missing character does not match",
            FuzzyMatch.score(query: "keymap", candidate: "Keybinding Cheat Sheet") == nil
        )
        check("rank filters and orders by score", {
            let items = ["Terminal", "The Editor Recent Menu", "Zoom"]
            let ranked = FuzzyMatch.rank(items, query: "term", key: { $0 })
            return ranked == ["Terminal", "The Editor Recent Menu"]
        }())
        check("rank preserves input order on ties", {
            let ranked = FuzzyMatch.rank(["Alpha", "Beta"], query: "", key: { $0 })
            return ranked == ["Alpha", "Beta"]
        }())

        print("\nTrigger edge detection")
        check("fires on rising edge only", {
            var d = EdgeDetector<String>()
            let first = d.shouldFire(for: "a", currentlyMatching: true)
            let second = d.shouldFire(for: "a", currentlyMatching: true)
            return first && !second
        }())
        check("resets after condition goes false", {
            var d = EdgeDetector<String>()
            _ = d.shouldFire(for: "a", currentlyMatching: true)
            _ = d.shouldFire(for: "a", currentlyMatching: false)
            return d.shouldFire(for: "a", currentlyMatching: true)
        }())
        check("keys are independent", {
            var d = EdgeDetector<String>()
            let a = d.shouldFire(for: "a", currentlyMatching: true)
            let b = d.shouldFire(for: "b", currentlyMatching: true)
            return a && b
        }())
        check("never-matching key never fires", {
            var d = EdgeDetector<String>()
            return d.shouldFire(for: "a", currentlyMatching: false) == false
        }())

        print("\nAX recipe recording (coalescing)")
        check("consecutive characters coalesce into one typeText step", {
            let keys = [
                RecordedKeyEvent(character: "h", keyName: nil, timestampMs: 0),
                RecordedKeyEvent(character: "i", keyName: nil, timestampMs: 10),
            ]
            let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys)
            return steps == [RecordedStepDraft(kind: .typeText, value: "hi")]
        }())
        check("chord becomes standalone pressKey step", {
            let keys = [RecordedKeyEvent(character: nil, keyName: "cmd+s", timestampMs: 0)]
            let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys)
            return steps == [RecordedStepDraft(kind: .pressKey, value: "cmd+s")]
        }())
        check("click flushes pending text and becomes clickNamed", {
            let keys = [RecordedKeyEvent(character: "a", keyName: nil, timestampMs: 0)]
            let clicks = [RecordedClickEvent(label: "OK", isFragile: false, timestampMs: 10)]
            let steps = RecordingCoalescer.toSteps(clicks: clicks, keys: keys)
            return steps == [
                RecordedStepDraft(kind: .typeText, value: "a"),
                RecordedStepDraft(kind: .clickNamed, value: "OK", isFragile: false),
            ]
        }())
        check("large gap inserts pause step", {
            let keys = [
                RecordedKeyEvent(character: "a", keyName: nil, timestampMs: 0),
                RecordedKeyEvent(character: "b", keyName: nil, timestampMs: 1000),
            ]
            let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys, pauseThresholdMs: 250)
            return steps == [
                RecordedStepDraft(kind: .typeText, value: "a"),
                RecordedStepDraft(kind: .pause, value: "1.00"),
                RecordedStepDraft(kind: .typeText, value: "b"),
            ]
        }())
        check("fragile click propagates flag", {
            let clicks = [RecordedClickEvent(label: "AXButton", isFragile: true, timestampMs: 0)]
            let steps = RecordingCoalescer.toSteps(clicks: clicks, keys: [])
            return steps == [RecordedStepDraft(kind: .clickNamed, value: "AXButton", isFragile: true)]
        }())
        check("empty input produces no steps", RecordingCoalescer.toSteps(clicks: [], keys: []) == [])

        print("\nAX click wait policy")
        check("2s / 0.5s is 5 tries", AXClickWaitPolicy.attemptCount(timeout: 2.0, interval: 0.5) == 5)
        check("zero interval is one try", AXClickWaitPolicy.attemptCount(timeout: 2.0, interval: 0) == 1)
        check("first try has no delay", AXClickWaitPolicy.delayBeforeAttempt(0) == 0)
        check("later tries wait the interval", AXClickWaitPolicy.delayBeforeAttempt(1, interval: 0.12) == 0.12)

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
