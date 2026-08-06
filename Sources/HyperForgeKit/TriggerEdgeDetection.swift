// TriggerEdgeDetection.swift
// Fires once per "became true" transition — for triggers whose action should run
// once when a condition starts matching, not on every re-evaluation while it holds.

import Foundation

public struct EdgeDetector<Key: Hashable> {
    private var matching: Set<Key> = []

    public init() {}

    /// Returns `true` only on the transition from not-matching to matching for `key`.
    /// Resets when `currentlyMatching` is `false`, so a later re-match fires again.
    public mutating func shouldFire(for key: Key, currentlyMatching: Bool) -> Bool {
        guard currentlyMatching else {
            matching.remove(key)
            return false
        }
        let (inserted, _) = matching.insert(key)
        return inserted
    }
}
