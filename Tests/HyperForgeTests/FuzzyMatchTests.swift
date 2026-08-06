import XCTest
@testable import HyperForgeKit

final class FuzzyMatchTests: XCTestCase {
    func testEmptyQueryMatchesEverythingWithZeroScore() {
        XCTAssertEqual(FuzzyMatch.score(query: "", candidate: "anything"), 0)
    }

    func testExactSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatch.score(query: "snap left", candidate: "Snap Left Half"))
    }

    func testOutOfOrderCharactersDoNotMatch() {
        XCTAssertNil(FuzzyMatch.score(query: "left snap", candidate: "Snap Left Half"))
    }

    func testMissingCharacterDoesNotMatch() {
        XCTAssertNil(FuzzyMatch.score(query: "keymap", candidate: "Keybinding Cheat Sheet"))
    }

    func testContiguousMatchScoresHigherThanScattered() {
        let contiguous = FuzzyMatch.score(query: "term", candidate: "Terminal")
        let scattered = FuzzyMatch.score(query: "term", candidate: "The Editor Recent Menu")
        XCTAssertNotNil(contiguous)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(contiguous!, scattered!)
    }

    func testRankFiltersAndOrdersByScore() {
        let items = ["Terminal", "The Editor Recent Menu", "Zoom"]
        let ranked = FuzzyMatch.rank(items, query: "term", key: { $0 })
        XCTAssertEqual(ranked, ["Terminal", "The Editor Recent Menu"])
    }

    func testRankPreservesInputOrderOnTies() {
        let items = ["Alpha", "Beta"]
        let ranked = FuzzyMatch.rank(items, query: "", key: { $0 })
        XCTAssertEqual(ranked, ["Alpha", "Beta"])
    }
}
