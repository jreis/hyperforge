import XCTest
@testable import HyperForgeKit

final class AXRecipeRecordingTests: XCTestCase {
    func testConsecutiveCharactersCoalesceIntoOneTypeTextStep() {
        let keys = [
            RecordedKeyEvent(character: "h", keyName: nil, timestampMs: 0),
            RecordedKeyEvent(character: "i", keyName: nil, timestampMs: 10),
        ]
        let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys)
        XCTAssertEqual(steps, [RecordedStepDraft(kind: .typeText, value: "hi")])
    }

    func testChordBecomesStandalonePressKeyStep() {
        let keys = [RecordedKeyEvent(character: nil, keyName: "cmd+s", timestampMs: 0)]
        let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys)
        XCTAssertEqual(steps, [RecordedStepDraft(kind: .pressKey, value: "cmd+s")])
    }

    func testClickBecomesClickNamedStepAndFlushesPendingText() {
        let keys = [RecordedKeyEvent(character: "a", keyName: nil, timestampMs: 0)]
        let clicks = [RecordedClickEvent(label: "OK", isFragile: false, timestampMs: 10)]
        let steps = RecordingCoalescer.toSteps(clicks: clicks, keys: keys)
        XCTAssertEqual(steps, [
            RecordedStepDraft(kind: .typeText, value: "a"),
            RecordedStepDraft(kind: .clickNamed, value: "OK", isFragile: false),
        ])
    }

    func testLargeGapInsertsPauseStep() {
        let keys = [
            RecordedKeyEvent(character: "a", keyName: nil, timestampMs: 0),
            RecordedKeyEvent(character: "b", keyName: nil, timestampMs: 1000),
        ]
        let steps = RecordingCoalescer.toSteps(clicks: [], keys: keys, pauseThresholdMs: 250)
        XCTAssertEqual(steps, [
            RecordedStepDraft(kind: .typeText, value: "a"),
            RecordedStepDraft(kind: .pause, value: "1.00"),
            RecordedStepDraft(kind: .typeText, value: "b"),
        ])
    }

    func testFragileClickPropagatesFlag() {
        let clicks = [RecordedClickEvent(label: "AXButton", isFragile: true, timestampMs: 0)]
        let steps = RecordingCoalescer.toSteps(clicks: clicks, keys: [])
        XCTAssertEqual(steps, [RecordedStepDraft(kind: .clickNamed, value: "AXButton", isFragile: true)])
    }

    func testEmptyInputProducesNoSteps() {
        XCTAssertEqual(RecordingCoalescer.toSteps(clicks: [], keys: []), [])
    }
}
