// FirstRunChallengeStore.swift
// Interactive “prove it works” path: Hyper · Space+HJKL · window snap.
// Completing all three (or skipping) persists so Dashboard stops nagging.

import Foundation
import SwiftUI

@MainActor
final class FirstRunChallengeStore: ObservableObject {
    static let shared = FirstRunChallengeStore()

    static let completedKey = "hf.firstRunChallengeCompleted"
    static let skippedKey = "hf.firstRunChallengeSkipped"
    static let hyperKey = "hf.challenge.hyper"
    static let spaceKey = "hf.challenge.spaceNav"
    static let snapKey = "hf.challenge.windowSnap"

    @Published private(set) var hyperDone: Bool
    @Published private(set) var spaceDone: Bool
    @Published private(set) var snapDone: Bool
    @Published private(set) var skipped: Bool
    @Published private(set) var completed: Bool

    private init() {
        let d = UserDefaults.standard
        hyperDone = d.bool(forKey: Self.hyperKey)
        spaceDone = d.bool(forKey: Self.spaceKey)
        snapDone = d.bool(forKey: Self.snapKey)
        skipped = d.bool(forKey: Self.skippedKey)
        completed = d.bool(forKey: Self.completedKey)
        if hyperDone && spaceDone && snapDone && !completed {
            markCompletedQuietly()
        }
    }

    var allProved: Bool { hyperDone && spaceDone && snapDone }

    /// Show on Dashboard when onboarding is done but the user hasn’t finished or skipped.
    var shouldShowCard: Bool {
        let onboarded = UserDefaults.standard.bool(forKey: "hf.hasCompletedOnboarding")
        return onboarded && !completed && !skipped
    }

    var progressLabel: String {
        let n = [hyperDone, spaceDone, snapDone].filter(\.self).count
        return "\(n)/3"
    }

    func noteHyper() {
        guard !hyperDone else { return }
        hyperDone = true
        UserDefaults.standard.set(true, forKey: Self.hyperKey)
        celebrate("Hyper key", "Caps held — engine sees Hyper")
        checkAll()
    }

    func noteSpaceNav() {
        guard !spaceDone else { return }
        spaceDone = true
        UserDefaults.standard.set(true, forKey: Self.spaceKey)
        celebrate("Space layer", "HJKL navigation works")
        checkAll()
    }

    func noteWindowSnap() {
        guard !snapDone else { return }
        snapDone = true
        UserDefaults.standard.set(true, forKey: Self.snapKey)
        celebrate("Window snap", "Hyper + arrow (or numpad) works")
        checkAll()
    }

    func skip() {
        skipped = true
        UserDefaults.standard.set(true, forKey: Self.skippedKey)
        Banner.show(
            "Challenge skipped",
            subtitle: "Replay anytime from Doctor",
            style: .info,
            symbol: "forward.fill",
            duration: 2.0
        )
    }

    func reset() {
        let d = UserDefaults.standard
        for k in [Self.hyperKey, Self.spaceKey, Self.snapKey, Self.completedKey, Self.skippedKey] {
            d.set(false, forKey: k)
        }
        hyperDone = false
        spaceDone = false
        snapDone = false
        skipped = false
        completed = false
    }

    private func checkAll() {
        guard allProved else { return }
        markCompletedQuietly()
        Banner.show(
            "You're dangerous",
            subtitle: "Hyper · Space nav · snaps — all green",
            style: .success,
            symbol: "flame.fill",
            duration: 3.0
        )
    }

    private func markCompletedQuietly() {
        completed = true
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    private func celebrate(_ title: String, _ subtitle: String) {
        Banner.show(title, subtitle: subtitle, style: .success, symbol: "checkmark.circle.fill", duration: 1.6)
    }
}
