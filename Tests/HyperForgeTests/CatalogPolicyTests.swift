import XCTest
@testable import HyperForgeKit

final class CatalogPolicyTests: XCTestCase {
    func testCleanCatalogPasses() {
        let ids = Array(CatalogPolicy.requiredActionIDs) + ["extra-custom"]
        let blob = "Snap Left Half Maximize Focus Terminal Preferred terminal"
        let errors = CatalogPolicy.validate(actionIDs: ids, searchableBlob: blob)
        XCTAssertTrue(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    func testDetectsMissingRequired() {
        let errors = CatalogPolicy.validate(
            actionIDs: ["win-left"],
            searchableBlob: "ok"
        )
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains { $0.contains("Missing required") })
    }

    func testDetectsRetiredPersonalID() {
        let ids = Array(CatalogPolicy.requiredActionIDs) + ["prod-azure"]
        let errors = CatalogPolicy.validate(actionIDs: ids, searchableBlob: "ok")
        XCTAssertTrue(errors.contains { $0.contains("Retired") })
    }

    func testDetectsPersonalEmailInBlob() {
        let ids = Array(CatalogPolicy.requiredActionIDs)
        let errors = CatalogPolicy.validate(
            actionIDs: ids,
            searchableBlob: "contact jason@example.com"
        )
        XCTAssertTrue(errors.contains { $0.contains("Forbidden") })
    }

    func testDetectsDuplicates() {
        let ids = Array(CatalogPolicy.requiredActionIDs) + ["win-left"]
        let errors = CatalogPolicy.validate(actionIDs: ids, searchableBlob: "ok")
        XCTAssertTrue(errors.contains { $0.contains("Duplicate") })
    }
}
