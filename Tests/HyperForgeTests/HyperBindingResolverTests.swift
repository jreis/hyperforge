import XCTest
@testable import HyperForgeKit

final class HyperBindingResolverTests: XCTestCase {
    func testEverySpecResolves() {
        for spec in HyperBindingResolver.specs {
            let route = HyperBindingResolver.resolve(
                keyCode: spec.keyCode,
                shiftDown: spec.requiresExtraShift,
                hyperConsumesShift: false
            )
            guard case .action(let id) = route else {
                XCTFail("\(spec.title) unhandled")
                continue
            }
            XCTAssertEqual(id, spec.actionID, spec.title)
        }
    }

    func testQuadModTerminalDoesNotCd() {
        let route = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.t,
            shiftDown: true,
            hyperConsumesShift: true
        )
        XCTAssertEqual(route, .action("app-iterm"))
    }

    func testF18ShiftTerminalIsHere() {
        let route = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.t,
            shiftDown: true,
            hyperConsumesShift: false
        )
        XCTAssertEqual(route, .action("app-terminal-here"))
    }

    func testPlainYIsRecipesNotScripts() {
        let route = HyperBindingResolver.resolve(keyCode: HyperKeyCode.y)
        XCTAssertEqual(route, .action("sys-recipes"))
    }

    func testShiftYIsScripts() {
        let route = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.y,
            shiftDown: true,
            hyperConsumesShift: false
        )
        XCTAssertEqual(route, .action("sys-scripts"))
    }

    func testPlainLIsScrollRightNotWorkspaces() {
        let route = HyperBindingResolver.resolve(keyCode: HyperKeyCode.l)
        XCTAssertEqual(route, .action("scroll-right"))
    }

    func testShiftLIsWorkspaces() {
        let route = HyperBindingResolver.resolve(
            keyCode: HyperKeyCode.l,
            shiftDown: true,
            hyperConsumesShift: false
        )
        XCTAssertEqual(route, .action("sys-workspaces"))
    }
}
