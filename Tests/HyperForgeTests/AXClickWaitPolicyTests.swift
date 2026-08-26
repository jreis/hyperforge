import XCTest
@testable import HyperForgeKit

final class AXClickWaitPolicyTests: XCTestCase {
    func testAttemptCountIncludesImmediateTry() {
        XCTAssertEqual(AXClickWaitPolicy.attemptCount(timeout: 2.0, interval: 0.5), 5)
    }

    func testZeroIntervalIsOneTry() {
        XCTAssertEqual(AXClickWaitPolicy.attemptCount(timeout: 2.0, interval: 0), 1)
    }

    func testFirstAttemptHasNoDelay() {
        XCTAssertEqual(AXClickWaitPolicy.delayBeforeAttempt(0), 0)
        XCTAssertEqual(AXClickWaitPolicy.delayBeforeAttempt(1, interval: 0.12), 0.12)
    }
}
