import XCTest
@testable import HyperForgeKit

final class DashboardWindowPolicyTests: XCTestCase {
    func testIdentifierMatchWins() {
        let w = WindowTraits(
            title: "whatever",
            width: 100,
            height: 100,
            isBorderless: true,
            isNormalOrFloatingLevel: false,
            identifier: DashboardWindowPolicy.dashboardIdentifier
        )
        XCTAssertTrue(DashboardWindowPolicy.isDashboard(w))
    }

    func testRejectsCheatSheetByTitle() {
        let w = WindowTraits(
            title: "HyperForge — Keybindings",
            width: 740,
            height: 580,
            isBorderless: false,
            isNormalOrFloatingLevel: true
        )
        XCTAssertFalse(DashboardWindowPolicy.isDashboard(w))
    }

    func testRejectsTinyBanner() {
        let w = WindowTraits(
            title: "",
            width: 300,
            height: 44,
            isBorderless: true,
            isNormalOrFloatingLevel: true
        )
        XCTAssertFalse(DashboardWindowPolicy.isDashboard(w))
    }

    func testAcceptsLargeMainChrome() {
        let w = WindowTraits(
            title: "HyperForge",
            width: 1100,
            height: 720,
            isBorderless: false,
            isNormalOrFloatingLevel: true
        )
        XCTAssertTrue(DashboardWindowPolicy.isDashboard(w))
    }

    func testRejectsWrongLevel() {
        let w = WindowTraits(
            title: "HyperForge",
            width: 1100,
            height: 720,
            isBorderless: false,
            isNormalOrFloatingLevel: false
        )
        XCTAssertFalse(DashboardWindowPolicy.isDashboard(w))
    }
}
