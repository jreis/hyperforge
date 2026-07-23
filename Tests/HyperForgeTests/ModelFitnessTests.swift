import XCTest
@testable import HyperForgeKit

final class ModelFitnessTests: XCTestCase {
    private let fourGB: UInt64 = 4 * 1_073_741_824
    private let eightGB: UInt64 = 8 * 1_073_741_824
    private let sixteenGB: UInt64 = 16 * 1_073_741_824

    func testTinyModelOKOn4GB() {
        let installed = [
            OllamaModelInfo(name: "qwen3:1.7b", sizeBytes: 1_200_000_000, parameterSize: "1.7B"),
        ]
        let fit = ModelFitness.assess(
            modelName: "qwen3:1.7b",
            installed: installed,
            physicalMemoryBytes: fourGB
        )
        XCTAssertEqual(fit.level, .ok, fit.detail)
    }

    func testLargeModelTooBigOn4GB() {
        let installed = [
            OllamaModelInfo(name: "llama3.1:8b", sizeBytes: 4_700_000_000, parameterSize: "8B"),
        ]
        let fit = ModelFitness.assess(
            modelName: "llama3.1:8b",
            installed: installed,
            physicalMemoryBytes: fourGB
        )
        XCTAssertTrue(fit.level == .tooLarge || fit.level == .tight, fit.detail)
        XCTAssertTrue(fit.isWarning)
        XCTAssertEqual(fit.suggestion, ModelFitness.lowRAMSuggestion)
    }

    func testDefaultLlama32FlaggedOnLowRAMEvenWithoutInstallList() {
        let fit = ModelFitness.assess(
            modelName: "llama3.2",
            installed: [],
            physicalMemoryBytes: fourGB
        )
        // No size metadata → name heuristic on ≤6 GB
        XCTAssertEqual(fit.level, .tooLarge, fit.detail)
    }

    func testNotInstalledWhenListPresent() {
        let installed = [
            OllamaModelInfo(name: "qwen3:1.7b", sizeBytes: 1_200_000_000, parameterSize: "1.7B"),
        ]
        let fit = ModelFitness.assess(
            modelName: "llama3.2",
            installed: installed,
            physicalMemoryBytes: eightGB
        )
        XCTAssertEqual(fit.level, .notInstalled, fit.detail)
    }

    func testParameterHintFromTag() {
        XCTAssertEqual(ModelFitness.parameterHint(from: "qwen3:1.7b"), "1.7B")
        XCTAssertEqual(ModelFitness.parameterHint(from: "phi3:mini"), "1B")
    }

    func testSuggestedModelByRAM() {
        XCTAssertEqual(ModelFitness.suggestedModel(forRAMGB: 4), ModelFitness.lowRAMSuggestion)
        XCTAssertEqual(ModelFitness.suggestedModel(forRAMGB: 8), ModelFitness.midRAMSuggestion)
        XCTAssertEqual(ModelFitness.suggestedModel(forRAMGB: 16), ModelFitness.highRAMSuggestion)
    }

    func testEightGBHandlesMidModel() {
        let installed = [
            OllamaModelInfo(name: "llama3.2:3b", sizeBytes: 2_000_000_000, parameterSize: "3B"),
        ]
        let fit = ModelFitness.assess(
            modelName: "llama3.2:3b",
            installed: installed,
            physicalMemoryBytes: sixteenGB
        )
        XCTAssertEqual(fit.level, .ok, fit.detail)
    }
}
