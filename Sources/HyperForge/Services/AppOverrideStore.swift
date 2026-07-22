// AppOverrideStore.swift
// Persist per-app binding overrides and resolve effective action IDs / remaps.

import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppOverrideStore: ObservableObject {
    static let shared = AppOverrideStore()

    @Published var overrides: [AppOverride] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app-overrides.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([AppOverride].self, from: data)
        {
            overrides = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(overrides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(for app: NSRunningApplication) {
        guard let bid = app.bundleIdentifier else { return }
        if overrides.contains(where: { $0.bundleID == bid }) { return }
        overrides.append(
            AppOverride(
                bundleID: bid,
                appName: app.localizedName ?? bid
            )
        )
        persist()
    }

    func addManual(bundleID: String, appName: String) {
        guard !bundleID.isEmpty,
              !overrides.contains(where: { $0.bundleID == bundleID })
        else { return }
        overrides.append(AppOverride(bundleID: bundleID, appName: appName.isEmpty ? bundleID : appName))
        persist()
    }

    func update(_ item: AppOverride) {
        if let idx = overrides.firstIndex(where: { $0.id == item.id }) {
            overrides[idx] = item
            persist()
        }
    }

    func delete(_ item: AppOverride) {
        overrides.removeAll { $0.id == item.id }
        persist()
    }

    /// Active override for the current frontmost app (if any).
    func activeOverride() -> AppOverride? {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }
        return overrides.first { $0.isEnabled && $0.bundleID == bid }
    }

    /// Merge profile-enabled IDs with per-app disables.
    func effectiveEnabledIDs(profileIDs: Set<String>?) -> Set<String>? {
        let base: Set<String>?
        if let profileIDs, !profileIDs.isEmpty {
            base = profileIDs
        } else {
            base = nil
        }

        guard let ov = activeOverride(), !ov.disabledActionIDs.isEmpty else {
            return base
        }

        if let base {
            return base.subtracting(ov.disabledActionIDs)
        }
        // All defaults minus disabled
        return Set(ActionCatalog.defaults.map(\.id)).subtracting(ov.disabledActionIDs)
    }

    /// If this key is remapped for the frontmost app, return the action id.
    func remapActionID(for keyCode: CGKeyCode) -> String? {
        guard let ov = activeOverride() else { return nil }
        return ov.remaps.first { $0.keyCode == keyCode }?.actionID
    }
}
