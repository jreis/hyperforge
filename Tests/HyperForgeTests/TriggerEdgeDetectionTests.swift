import XCTest
@testable import HyperForgeKit

final class TriggerEdgeDetectionTests: XCTestCase {
    func testFiresOnRisingEdgeOnly() {
        var detector = EdgeDetector<String>()
        XCTAssertTrue(detector.shouldFire(for: "a", currentlyMatching: true))
        XCTAssertFalse(detector.shouldFire(for: "a", currentlyMatching: true))
        XCTAssertFalse(detector.shouldFire(for: "a", currentlyMatching: true))
    }

    func testResetsAfterConditionGoesFalse() {
        var detector = EdgeDetector<String>()
        XCTAssertTrue(detector.shouldFire(for: "a", currentlyMatching: true))
        XCTAssertFalse(detector.shouldFire(for: "a", currentlyMatching: false))
        XCTAssertTrue(detector.shouldFire(for: "a", currentlyMatching: true))
    }

    func testKeysAreIndependent() {
        var detector = EdgeDetector<String>()
        XCTAssertTrue(detector.shouldFire(for: "a", currentlyMatching: true))
        XCTAssertTrue(detector.shouldFire(for: "b", currentlyMatching: true))
    }

    func testNeverMatchingNeverFires() {
        var detector = EdgeDetector<String>()
        XCTAssertFalse(detector.shouldFire(for: "a", currentlyMatching: false))
    }
}
