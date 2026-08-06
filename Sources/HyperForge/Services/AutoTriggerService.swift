// AutoTriggerService.swift
// Watches Wi‑Fi, frontmost app, and time-of-day to auto-switch profiles, run a recipe,
// or restore a workspace layout.

import AppKit
import Foundation
import HyperForgeKit

@MainActor
final class AutoTriggerService: ObservableObject {
    static let shared = AutoTriggerService()

    @Published var isEnabled = true
    @Published private(set) var lastMatchDescription: String?
    @Published private(set) var currentSSID: String?
    @Published private(set) var frontmostBundleID: String?

    private var timer: Timer?
    private var lastAppliedProfileID: UUID?
    private var lastSSID: String?
    /// Rising-edge bookkeeping for `.runRecipe`/`.restoreLayout` triggers only —
    /// `.switchProfile` stays level-triggered (unchanged legacy behavior).
    private var edgeDetector = EdgeDetector<UUID>()

    private init() {}

    func start() {
        guard timer == nil else { return }
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        // App activation is more immediate than polling alone.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate() {
        guard isEnabled else { return }
        let store = ProfileStore.shared
        let triggers = store.autoTriggers.filter(\.isEnabled)
        guard !triggers.isEmpty else { return }

        currentSSID = Self.fetchSSID()
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Priority: app > wifi > time (more specific first)
        let ordered = triggers.sorted { a, b in
            rank(a.kind) < rank(b.kind)
        }

        // Track match + rising-edge state for every trigger this cycle — not just the
        // eventual winner — so an edge-triggered trigger that loses priority this round
        // still observes its own falling edge and can re-fire later. Only the
        // highest-priority matching trigger's action actually runs per cycle (same
        // single-winner limitation the level-triggered profile switch has always had —
        // e.g. a lower-priority runRecipe trigger for the same app as a switchProfile
        // trigger will never win and never fire).
        var matchFlags: [UUID: Bool] = [:]
        var firedThisCycle: Set<UUID> = []
        for trigger in ordered {
            let isMatch = matches(trigger)
            matchFlags[trigger.id] = isMatch
            if trigger.action != .switchProfile {
                if edgeDetector.shouldFire(for: trigger.id, currentlyMatching: isMatch) {
                    firedThisCycle.insert(trigger.id)
                }
            }
        }

        guard let winner = ordered.first(where: { matchFlags[$0.id] == true }) else { return }

        switch winner.action {
        case .switchProfile:
            if store.activeProfileID != winner.profileID {
                if let profile = store.profiles.first(where: { $0.id == winner.profileID }) {
                    store.select(profile)
                    lastAppliedProfileID = profile.id
                    lastMatchDescription =
                        "\(winner.kind.title): \(winner.value) → \(profile.name)"
                    Banner.show("Profile: \(profile.name)")
                    HyperLog.event("AutoTrigger \(lastMatchDescription ?? "")")
                }
            } else {
                lastMatchDescription =
                    "Holding \(store.activeProfile.name) via \(winner.kind.title)"
            }

        case .runRecipe:
            guard firedThisCycle.contains(winner.id) else { return }
            guard let recipeID = winner.recipeID,
                  let recipe = AXRecipeStore.shared.recipes.first(where: { $0.id == recipeID })
            else {
                Banner.show("Trigger recipe not found", style: .warning)
                return
            }
            AXRecipeStore.shared.run(recipe)
            lastMatchDescription = "\(winner.kind.title): \(winner.value) → Run recipe: \(recipe.name)"
            HyperLog.event("AutoTrigger \(lastMatchDescription ?? "")")

        case .restoreLayout:
            guard firedThisCycle.contains(winner.id) else { return }
            guard let layoutID = winner.layoutID,
                  let profile = store.profiles.first(where: { $0.id == winner.profileID }),
                  let layout = profile.layouts.first(where: { $0.id == layoutID })
            else {
                Banner.show("Trigger layout not found", style: .warning)
                return
            }
            store.restoreLayout(layout)
            lastMatchDescription = "\(winner.kind.title): \(winner.value) → Restore: \(layout.name)"
            HyperLog.event("AutoTrigger \(lastMatchDescription ?? "")")
        }
    }

    private func rank(_ kind: AutoTrigger.Kind) -> Int {
        switch kind {
        case .appBundleID: return 0
        case .wifiSSID: return 1
        case .timeOfDay: return 2
        }
    }

    private func matches(_ trigger: AutoTrigger) -> Bool {
        switch trigger.kind {
        case .wifiSSID:
            guard let ssid = currentSSID else { return false }
            return ssid.caseInsensitiveCompare(trigger.value) == .orderedSame
        case .appBundleID:
            guard let bid = frontmostBundleID else { return false }
            let v = trigger.value
            if bid.caseInsensitiveCompare(v) == .orderedSame { return true }
            // Allow matching by app name fragment
            if let name = NSWorkspace.shared.frontmostApplication?.localizedName,
               name.localizedCaseInsensitiveContains(v)
            {
                return true
            }
            return bid.localizedCaseInsensitiveContains(v)
        case .timeOfDay:
            return Self.timeInRange(trigger.value)
        }
    }

    /// Parse "HH:mm-HH:mm" (supports overnight ranges).
    static func timeInRange(_ value: String) -> Bool {
        let parts = value.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = parseTime(parts[0]),
              let end = parseTime(parts[1])
        else { return false }

        let cal = Calendar.current
        let now = Date()
        let mins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if start <= end {
            return mins >= start && mins <= end
        } else {
            // Overnight e.g. 22:00-06:00
            return mins >= start || mins <= end
        }
    }

    private static func parseTime(_ s: String) -> Int? {
        let bits = s.split(separator: ":")
        guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        return h * 60 + m
    }

    /// Best-effort SSID via networksetup (no special entitlement).
    static func fetchSSID() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getairportnetwork", "en0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard
            let str = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if str.localizedCaseInsensitiveContains("not associated") { return nil }
        return str.replacingOccurrences(of: "Current Wi-Fi Network: ", with: "")
    }
}
