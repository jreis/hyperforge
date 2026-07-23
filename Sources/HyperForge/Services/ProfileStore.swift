// ProfileStore.swift
// Persist profiles and the active selection (local-first JSON).

import Combine
import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var profiles: [HyperProfile]
    @Published var activeProfileID: UUID
    @Published var autoTriggers: [AutoTrigger] = []

    private let fileURL: URL

    var activeProfile: HyperProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(StorePayload.self, from: data),
           !decoded.profiles.isEmpty
        {
            profiles = decoded.profiles
            activeProfileID = decoded.activeProfileID
            autoTriggers = decoded.autoTriggers
        } else {
            let builtIns = HyperProfile.builtIns
            profiles = builtIns
            activeProfileID = builtIns[0].id
            persist()
        }
    }

    func select(_ profile: HyperProfile) {
        activeProfileID = profile.id
        applyToEngine()
        persist()
    }

    func applyToEngine() {
        let p = activeProfile
        HyperKeyEngine.shared.enabledActionIDs =
            p.enabledActionIDs.isEmpty ? nil : p.enabledActionIDs
        KarabinerService.shared.ruleJSON = p.karabinerRuleJSON
    }

    func add(_ profile: HyperProfile) {
        profiles.append(profile)
        persist()
    }

    func update(_ profile: HyperProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            if profile.id == activeProfileID {
                applyToEngine()
            }
            persist()
        }
    }

    func delete(_ profile: HyperProfile) {
        guard !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = profiles[0].id
            applyToEngine()
        }
        persist()
    }

    func saveCurrentLayout(named name: String) {
        var p = activeProfile
        let snap = WindowManager.shared.captureLayout()
        p.layouts.append(WorkspaceLayout(name: name, windows: snap))
        update(p)
    }

    func restoreLayout(_ layout: WorkspaceLayout) {
        WindowManager.shared.restoreLayout(layout.windows)
        Banner.show("Restored “\(layout.name)”")
    }

    func addTrigger(_ trigger: AutoTrigger) {
        autoTriggers.append(trigger)
        persist()
    }

    func updateTrigger(_ trigger: AutoTrigger) {
        if let idx = autoTriggers.firstIndex(where: { $0.id == trigger.id }) {
            autoTriggers[idx] = trigger
            persist()
        }
    }

    func deleteTrigger(_ trigger: AutoTrigger) {
        autoTriggers.removeAll { $0.id == trigger.id }
        persist()
    }

    /// Full replace used by config import.
    func replaceAll(profiles: [HyperProfile], activeProfileID: UUID, autoTriggers: [AutoTrigger]) {
        guard !profiles.isEmpty else { return }
        self.profiles = profiles
        if profiles.contains(where: { $0.id == activeProfileID }) {
            self.activeProfileID = activeProfileID
        } else {
            self.activeProfileID = profiles[0].id
        }
        self.autoTriggers = autoTriggers
        applyToEngine()
        persist()
    }

    private struct StorePayload: Codable {
        var profiles: [HyperProfile]
        var activeProfileID: UUID
        var autoTriggers: [AutoTrigger]
    }

    private func persist() {
        let payload = StorePayload(
            profiles: profiles,
            activeProfileID: activeProfileID,
            autoTriggers: autoTriggers
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
