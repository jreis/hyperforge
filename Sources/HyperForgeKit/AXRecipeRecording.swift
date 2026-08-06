// AXRecipeRecording.swift
// Turns a raw stream of recorded clicks/keystrokes into AX recipe steps — pure
// coalescing logic, no AppKit/Accessibility dependency.

import Foundation

public struct RecordedClickEvent: Equatable {
    /// Resolved AX title/description/value, or a role-name fallback when none was found.
    public let label: String
    /// `true` when `label` is a role-name fallback (no real AX label at the click point) —
    /// such a step will likely fail to re-match on replay and should be flagged in the UI.
    public let isFragile: Bool
    public let timestampMs: Double

    public init(label: String, isFragile: Bool, timestampMs: Double) {
        self.label = label
        self.isFragile = isFragile
        self.timestampMs = timestampMs
    }
}

public struct RecordedKeyEvent: Equatable {
    /// A printable character to append to a running typed-text step.
    public let character: String?
    /// A chord spec (e.g. "cmd+s"), set instead of `character` for modifier-key presses.
    public let keyName: String?
    public let timestampMs: Double

    public init(character: String?, keyName: String?, timestampMs: Double) {
        self.character = character
        self.keyName = keyName
        self.timestampMs = timestampMs
    }
}

public struct RecordedStepDraft: Equatable {
    public enum Kind: String {
        case clickNamed
        case pressKey
        case pause
        case typeText
    }

    public var kind: Kind
    public var value: String
    public var isFragile: Bool

    public init(kind: Kind, value: String, isFragile: Bool = false) {
        self.kind = kind
        self.value = value
        self.isFragile = isFragile
    }
}

public enum RecordingCoalescer {
    private enum TimelineEvent {
        case click(RecordedClickEvent)
        case key(RecordedKeyEvent)

        var timestampMs: Double {
            switch self {
            case .click(let c): return c.timestampMs
            case .key(let k): return k.timestampMs
            }
        }
    }

    /// Merges clicks and keys into a single chronological step list: consecutive typed
    /// characters coalesce into one `typeText` step, chord presses become standalone
    /// `pressKey` steps, clicks become `clickNamed` steps, and a gap of at least
    /// `pauseThresholdMs` between events inserts a `pause` step.
    public static func toSteps(
        clicks: [RecordedClickEvent],
        keys: [RecordedKeyEvent],
        pauseThresholdMs: Double = 250
    ) -> [RecordedStepDraft] {
        let timeline = (clicks.map(TimelineEvent.click) + keys.map(TimelineEvent.key))
            .sorted { $0.timestampMs < $1.timestampMs }

        var steps: [RecordedStepDraft] = []
        var pendingText = ""
        var lastTimestamp: Double?

        func flushPendingText() {
            guard !pendingText.isEmpty else { return }
            steps.append(RecordedStepDraft(kind: .typeText, value: pendingText))
            pendingText = ""
        }

        for event in timeline {
            let ts = event.timestampMs
            if let last = lastTimestamp, ts - last >= pauseThresholdMs {
                flushPendingText()
                steps.append(RecordedStepDraft(kind: .pause, value: formatSeconds((ts - last) / 1000)))
            }
            lastTimestamp = ts

            switch event {
            case .click(let c):
                flushPendingText()
                steps.append(RecordedStepDraft(kind: .clickNamed, value: c.label, isFragile: c.isFragile))
            case .key(let k):
                if let keyName = k.keyName {
                    flushPendingText()
                    steps.append(RecordedStepDraft(kind: .pressKey, value: keyName))
                } else if let char = k.character {
                    pendingText += char
                }
            }
        }
        flushPendingText()
        return steps
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }
}
