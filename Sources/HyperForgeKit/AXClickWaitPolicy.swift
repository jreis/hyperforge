// AXClickWaitPolicy.swift
// How long a recipe click waits for a control (sheet / Allow / OK).

import Foundation

public enum AXClickWaitPolicy {
    public static let defaultTimeout: TimeInterval = 2.0
    public static let defaultInterval: TimeInterval = 0.12

    /// Tries, including the first immediate try.
    public static func attemptCount(
        timeout: TimeInterval = defaultTimeout,
        interval: TimeInterval = defaultInterval
    ) -> Int {
        guard interval > 0 else { return 1 }
        return max(1, Int((timeout / interval).rounded(.down)) + 1)
    }

    /// Delay before attempt `index` (0-based). First try is 0.
    public static func delayBeforeAttempt(
        _ index: Int,
        interval: TimeInterval = defaultInterval
    ) -> TimeInterval {
        index <= 0 ? 0 : interval
    }
}
