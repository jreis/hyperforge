import XCTest
@testable import HyperForgeKit

final class HyperChordRoutingTests: XCTestCase {
    func testAllowedNilMeansAll() {
        XCTAssertTrue(HyperChordRouting.isAllowed(actionID: "win-left", enabledIDs: nil))
        XCTAssertTrue(HyperChordRouting.isAllowed(actionID: "win-left", enabledIDs: []))
    }

    func testAllowedRespectsProfileSet() {
        let enabled: Set<String> = ["win-left", "sys-lock"]
        XCTAssertTrue(HyperChordRouting.isAllowed(actionID: "win-left", enabledIDs: enabled))
        XCTAssertFalse(HyperChordRouting.isAllowed(actionID: "prod-keepalive", enabledIDs: enabled))
    }

    func testExtraShiftOnlyWhenNotQuadHyper() {
        XCTAssertTrue(
            HyperChordRouting.extraShift(shiftDown: true, hyperConsumesShift: false)
        )
        XCTAssertFalse(
            HyperChordRouting.extraShift(shiftDown: true, hyperConsumesShift: true)
        )
        XCTAssertFalse(
            HyperChordRouting.extraShift(shiftDown: false, hyperConsumesShift: false)
        )
    }

    func testSlashF18PlainIsLinkHints() {
        let action = HyperChordRouting.slashAction(
            shiftDown: false,
            hyperConsumesShift: false,
            linkHintsAllowed: true
        )
        XCTAssertEqual(action, .linkHints)
    }

    func testSlashF18WithShiftIsCheatSheet() {
        let action = HyperChordRouting.slashAction(
            shiftDown: true,
            hyperConsumesShift: false,
            linkHintsAllowed: true
        )
        XCTAssertEqual(action, .cheatSheet)
    }

    func testSlashQuadModIsCheatSheet() {
        // 4-mod always has shift bit; hyperConsumesShift makes / = help
        let action = HyperChordRouting.slashAction(
            shiftDown: true,
            hyperConsumesShift: true,
            linkHintsAllowed: true
        )
        XCTAssertEqual(action, .cheatSheet)
    }

    func testSlashFallsBackToCheatSheetWhenHintsDisabled() {
        let action = HyperChordRouting.slashAction(
            shiftDown: false,
            hyperConsumesShift: false,
            linkHintsAllowed: false
        )
        XCTAssertEqual(action, .cheatSheetFallback)
    }
}
