// BindingChecklistStore.swift
// Manual verification progress for Hyper bindings (persisted).

import Combine
import Foundation
import HyperForgeKit

@MainActor
final class BindingChecklistStore: ObservableObject {
    static let shared = BindingChecklistStore()

    @Published private(set) var verifiedIDs: Set<String> = []

    private let key = "hf.bindingChecklist.verified"

    private init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            verifiedIDs = Set(arr)
        }
    }

    var total: Int { HyperBindingResolver.specs.count }

    var verifiedCount: Int {
        HyperBindingResolver.specs.filter { verifiedIDs.contains($0.checklistKey) }.count
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(verifiedCount) / Double(total)
    }

    func isVerified(_ spec: HyperBindingSpec) -> Bool {
        verifiedIDs.contains(spec.checklistKey)
    }

    func toggle(_ spec: HyperBindingSpec) {
        let k = spec.checklistKey
        if verifiedIDs.contains(k) {
            verifiedIDs.remove(k)
        } else {
            verifiedIDs.insert(k)
        }
        persist()
    }

    func markVerified(_ spec: HyperBindingSpec) {
        verifiedIDs.insert(spec.checklistKey)
        persist()
    }

    func resetAll() {
        verifiedIDs.removeAll()
        persist()
    }

    /// Full replace used by config import.
    func replaceAll(_ ids: Set<String>) {
        verifiedIDs = ids
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(verifiedIDs).sorted(), forKey: key)
    }
}

