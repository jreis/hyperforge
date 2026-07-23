// ModelFitness.swift
// Heuristics: will a local Ollama model run reasonably given host RAM?
// Pure / testable — no AppKit.

import Darwin
import Foundation

/// How well a configured model is expected to run on this machine.
public enum ModelFitLevel: String, Sendable, Equatable {
    case ok
    /// Likely runnable but may thrash or be very slow.
    case tight
    /// Almost certainly too large for comfortable use.
    case tooLarge
    /// Model name not present in Ollama’s installed list.
    case notInstalled
    /// Not enough data (offline, no size, etc.).
    case unknown
}

public struct ModelFitAssessment: Sendable, Equatable {
    public var level: ModelFitLevel
    public var title: String
    public var detail: String
    /// Suggested alternate model tag when current is a poor fit (optional).
    public var suggestion: String?

    public init(
        level: ModelFitLevel,
        title: String,
        detail: String,
        suggestion: String? = nil
    ) {
        self.level = level
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
    }

    public var isWarning: Bool {
        switch level {
        case .tight, .tooLarge, .notInstalled: return true
        case .ok, .unknown: return false
        }
    }
}

/// Snapshot of one installed Ollama model from `/api/tags`.
public struct OllamaModelInfo: Sendable, Equatable, Hashable {
    public var name: String
    /// On-disk size in bytes (from Ollama).
    public var sizeBytes: Int64
    /// e.g. "1.7B", "7B" from Ollama details.
    public var parameterSize: String?

    public init(name: String, sizeBytes: Int64, parameterSize: String? = nil) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.parameterSize = parameterSize
    }
}

public enum ModelFitness {
    /// Soft recommendation when RAM is low.
    public static let lowRAMSuggestion = "qwen3:1.7b"
    /// Soft recommendation for mid-range machines.
    public static let midRAMSuggestion = "llama3.2:3b"
    /// Soft recommendation when RAM is ample.
    public static let highRAMSuggestion = "llama3.2"

    /// Host physical RAM in bytes (caller supplies; tests inject).
    public static func assess(
        modelName: String,
        installed: [OllamaModelInfo],
        physicalMemoryBytes: UInt64
    ) -> ModelFitAssessment {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return ModelFitAssessment(
                level: .unknown,
                title: "No model set",
                detail: "Pick an installed Ollama model in Settings → Local AI."
            )
        }

        let match = findInstalled(name: name, in: installed)
        let ramGB = Double(physicalMemoryBytes) / 1_073_741_824.0
        let suggestion = suggestedModel(forRAMGB: ramGB)

        if match == nil, !installed.isEmpty {
            return ModelFitAssessment(
                level: .notInstalled,
                title: "Model not installed",
                detail: "“\(name)” is not in Ollama’s list. Run `ollama pull \(name)` or pick an installed tag.",
                suggestion: installed.first.map(\.name) ?? suggestion
            )
        }

        // Prefer disk size; fall back to parameter estimate from name / details.
        let disk = match.map { Double($0.sizeBytes) }
        let paramBytes = estimatedBytesFromParameters(
            match?.parameterSize ?? parameterHint(from: name)
        )
        let weightBytes = disk.flatMap { $0 > 0 ? $0 : nil } ?? paramBytes

        guard let weights = weightBytes, weights > 0 else {
            // No size data — still warn on very low RAM + known large tags.
            if ramGB <= 6, looksLargeByName(name) {
                return ModelFitAssessment(
                    level: .tooLarge,
                    title: "Likely too large for this Mac",
                    detail: String(
                        format: "This machine has ~%.0f GB RAM. “%@” usually needs more headroom for smooth local inference.",
                        ramGB,
                        name
                    ),
                    suggestion: suggestion
                )
            }
            return ModelFitAssessment(
                level: .unknown,
                title: "Can’t size this model yet",
                detail: "Ollama is reachable but size metadata is missing. Try Ping again after the model is fully pulled."
            )
        }

        // Runtime ≈ weights + KV/activations. Quantized blobs already include weight compression.
        let estimatedRuntime = weights * 1.35
        // Leave room for macOS, browser, HyperForge, etc.
        let reserve = max(2.0 * 1_073_741_824.0, Double(physicalMemoryBytes) * 0.40)
        let usable = max(0, Double(physicalMemoryBytes) - reserve)

        let weightsGB = weights / 1_073_741_824.0
        let runtimeGB = estimatedRuntime / 1_073_741_824.0
        let usableGB = usable / 1_073_741_824.0

        if estimatedRuntime > Double(physicalMemoryBytes) * 0.95 {
            return ModelFitAssessment(
                level: .tooLarge,
                title: "Too large for this Mac",
                detail: String(
                    format: "“%@” is ~%.1f GB on disk (~%.1f GB est. runtime) but this machine only has ~%.0f GB RAM. Expect thrashing or failure.",
                    name, weightsGB, runtimeGB, ramGB
                ),
                suggestion: suggestion
            )
        }

        if estimatedRuntime > usable {
            return ModelFitAssessment(
                level: .tight,
                title: "Tight fit — may be slow",
                detail: String(
                    format: "“%@” ≈ %.1f GB runtime vs ~%.1f GB usable after system reserve (%.0f GB total). It may work if little else is open; a smaller model is more reliable.",
                    name, runtimeGB, usableGB, ramGB
                ),
                suggestion: suggestion
            )
        }

        // Extra nudge on ≤4–6 GB even when math says ok (unified memory is contended).
        if ramGB <= 6, weightsGB >= 2.5 {
            return ModelFitAssessment(
                level: .tight,
                title: "Heavy for low-RAM Macs",
                detail: String(
                    format: "Only ~%.0f GB RAM and a ~%.1f GB model. Prefer ≤2B-class tags (e.g. %@) for the command bar.",
                    ramGB, weightsGB, suggestion
                ),
                suggestion: suggestion
            )
        }

        return ModelFitAssessment(
            level: .ok,
            title: "Looks fine for this Mac",
            detail: String(
                format: "“%@” ≈ %.1f GB on disk; ~%.0f GB RAM should handle short command-bar prompts.",
                name, weightsGB, ramGB
            )
        )
    }

    public static func suggestedModel(forRAMGB ramGB: Double) -> String {
        if ramGB <= 6 { return lowRAMSuggestion }
        if ramGB <= 12 { return midRAMSuggestion }
        return highRAMSuggestion
    }

    // MARK: - Helpers

    public static func findInstalled(name: String, in installed: [OllamaModelInfo]) -> OllamaModelInfo? {
        let lower = name.lowercased()
        if let exact = installed.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        // "llama3.2" matches "llama3.2:latest"
        if let tagged = installed.first(where: {
            $0.name.lowercased() == lower + ":latest"
                || $0.name.lowercased().hasPrefix(lower + ":")
        }) {
            return tagged
        }
        // "llama3.2:latest" → strip tag and retry base
        if let base = lower.split(separator: ":").first.map(String.init),
           base != lower
        {
            return installed.first(where: {
                $0.name.lowercased() == base
                    || $0.name.lowercased().hasPrefix(base + ":")
            })
        }
        return nil
    }

    /// Parse "1.7B", "7B", "13B" → approximate Q4 weight bytes.
    public static func estimatedBytesFromParameters(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // "1.7B", "7B", "670M"
        let pattern = #"^([0-9]*\.?[0-9]+)\s*([BMK])"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(
                  in: cleaned,
                  range: NSRange(cleaned.startIndex..., in: cleaned)
              ),
              let nRange = Range(match.range(at: 1), in: cleaned),
              let uRange = Range(match.range(at: 2), in: cleaned),
              let n = Double(cleaned[nRange])
        else { return nil }

        let unit = cleaned[uRange]
        let params: Double
        switch unit {
        case "B": params = n * 1_000_000_000
        case "M": params = n * 1_000_000
        case "K": params = n * 1_000
        default: return nil
        }
        // Rough Q4_K average: ~0.55–0.65 bytes/param → use 0.6
        return params * 0.6
    }

    /// Pull a size hint from tags like "qwen3:1.7b", "llama3.2:3b", "phi3:mini".
    public static func parameterHint(from modelName: String) -> String? {
        let lower = modelName.lowercased()
        if lower.contains("mini") || lower.contains("tiny") || lower.contains("1b") {
            return "1B"
        }
        // :1.7b / 1.7b / 3b / 7b / 8b / 13b / 70b
        let pattern = #"(?:^|[:\-_])([0-9]*\.?[0-9]+)\s*b(?:$|[:\-_])"#
        if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = re.firstMatch(
               in: lower,
               range: NSRange(lower.startIndex..., in: lower)
           ),
           let r = Range(match.range(at: 1), in: lower)
        {
            return "\(lower[r])B"
        }
        return nil
    }

    public static func looksLargeByName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("70b") || lower.contains("65b") || lower.contains("34b")
            || lower.contains("32b") || lower.contains("27b") || lower.contains("22b")
            || lower.contains("13b") || lower.contains("14b")
        {
            return true
        }
        if let hint = parameterHint(from: name),
           let n = Double(hint.replacingOccurrences(of: "B", with: "")),
           n >= 7
        {
            return true
        }
        // Unqualified "llama3.2" often pulls 3B+ — flag on very low RAM only (caller).
        if lower == "llama3.2" || lower == "llama3.2:latest" || lower.hasPrefix("llama3.1") {
            return true
        }
        return false
    }

    /// Physical RAM via sysctl (macOS). Returns 0 if unavailable.
    public static func physicalMemoryBytes() -> UInt64 {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return result == 0 ? size : 0
    }
}
