// FuzzyMatch.swift
// Simple subsequence fuzzy matcher for the command-bar launcher — no AppKit dependency.

import Foundation

public enum FuzzyMatch {
    /// Scores `candidate` against `query` as a case-insensitive ordered subsequence match.
    /// Returns `nil` when `query` isn't a subsequence of `candidate` (no match).
    /// Higher score = better match. An empty query matches everything with score 0.
    public static func score(query: String, candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !c.isEmpty else { return nil }

        var qi = 0
        var score = 0
        var runLength = 0
        var previousMatchIndex = -1

        for (ci, ch) in c.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                if previousMatchIndex == ci - 1 {
                    runLength += 1
                } else {
                    runLength = 1
                }
                // Contiguous runs score higher than scattered matches; an early
                // (near-prefix) match scores higher than a late one.
                score += 10 + (runLength - 1) * 5
                if ci == qi { score += 3 } // prefix bonus while still aligned
                previousMatchIndex = ci
                qi += 1
            }
        }

        guard qi == q.count else { return nil }
        // Shorter candidates rank slightly higher among equal matches (tighter match).
        score -= c.count / 8
        return score
    }

    /// Ranks `items` by fuzzy score against `query`, dropping non-matches.
    /// Stable-sorts by descending score, preserving input order for ties.
    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        let scored: [(item: T, score: Int, index: Int)] = items.enumerated().compactMap { index, item in
            guard let s = score(query: query, candidate: key(item)) else { return nil }
            return (item, s, index)
        }
        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
            }
            .map(\.item)
    }
}
