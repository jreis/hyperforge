// HyperAppSlotStore.swift
// User-configurable Hyper+1…5 app launch targets (launch → focus → minimize).

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// One number-key app slot (Hyper + digit).
struct HyperAppSlot: Codable, Identifiable, Equatable, Hashable {
    /// 1…5 (main keyboard digit row).
    var digit: Int
    /// Stable action id in the catalog / profiles (`app-chrome`, …).
    var actionID: String
    var displayName: String
    /// Preferred launch key — bundle id when known.
    var bundleID: String
    /// Fallback match via `NSRunningApplication.localizedName`.
    var appName: String
    var symbol: String

    var id: String { actionID }

    /// Best argument for `AppLauncher.launchFocusOrMinimize`.
    var launchTarget: String {
        if !bundleID.isEmpty { return bundleID }
        if !appName.isEmpty { return appName }
        return displayName
    }
}

@MainActor
final class HyperAppSlotStore: ObservableObject {
    static let shared = HyperAppSlotStore()

    static let storageKey = "hf.hyperAppSlots"

    /// Catalog action ids for digits 1…5 (kept for profile/checklist compatibility).
    static let actionIDsByDigit: [Int: String] = [
        1: "app-chrome",
        2: "app-zed",
        3: "app-teams",
        4: "app-vscode",
        5: "app-zoom",
    ]

    static let digitByActionID: [String: Int] = {
        var map: [String: Int] = [:]
        for (d, id) in actionIDsByDigit { map[id] = d }
        return map
    }()

    static let defaults: [HyperAppSlot] = [
        HyperAppSlot(
            digit: 1,
            actionID: "app-chrome",
            displayName: "Google Chrome",
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            symbol: "globe"
        ),
        HyperAppSlot(
            digit: 2,
            actionID: "app-zed",
            displayName: "Zed",
            bundleID: "dev.zed.Zed",
            appName: "Zed",
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        HyperAppSlot(
            digit: 3,
            actionID: "app-teams",
            displayName: "Microsoft Teams",
            bundleID: "com.microsoft.teams2",
            appName: "Microsoft Teams",
            symbol: "person.3"
        ),
        HyperAppSlot(
            digit: 4,
            actionID: "app-vscode",
            displayName: "Visual Studio Code",
            bundleID: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        HyperAppSlot(
            digit: 5,
            actionID: "app-zoom",
            displayName: "Zoom",
            bundleID: "us.zoom.xos",
            appName: "zoom.us",
            symbol: "video"
        ),
    ]

    /// Always five slots, sorted by digit.
    @Published private(set) var slots: [HyperAppSlot] = HyperAppSlotStore.defaults {
        didSet { persist() }
    }

    private init() {
        load()
        resolveMissingBundleIDs()
    }

    // MARK: - Lookup

    func slot(digit: Int) -> HyperAppSlot? {
        slots.first { $0.digit == digit }
    }

    func slot(actionID: String) -> HyperAppSlot? {
        slots.first { $0.actionID == actionID }
    }

    func isAppSlotAction(_ actionID: String) -> Bool {
        Self.digitByActionID[actionID] != nil
    }

    // MARK: - Mutate

    func setSlot(_ slot: HyperAppSlot) {
        guard (1...5).contains(slot.digit) else { return }
        var next = slots
        if let idx = next.firstIndex(where: { $0.digit == slot.digit }) {
            next[idx] = slot
        } else {
            next.append(slot)
        }
        next.sort { $0.digit < $1.digit }
        slots = next
    }

    func assign(digit: Int, bundleURL: URL) {
        guard let actionID = Self.actionIDsByDigit[digit] else { return }
        let bundle = Bundle(url: bundleURL)
        let bid = bundle?.bundleIdentifier
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
            ?? ""
        let name =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let symbol = slot(digit: digit)?.symbol ?? "app"
        setSlot(
            HyperAppSlot(
                digit: digit,
                actionID: actionID,
                displayName: name,
                bundleID: bid,
                appName: name,
                symbol: symbol
            )
        )
    }

    func assign(digit: Int, bundleID: String, displayName: String, appName: String? = nil, symbol: String? = nil) {
        guard let actionID = Self.actionIDsByDigit[digit] else { return }
        let existing = slot(digit: digit)
        setSlot(
            HyperAppSlot(
                digit: digit,
                actionID: actionID,
                displayName: displayName,
                bundleID: bundleID,
                appName: appName ?? displayName,
                symbol: symbol ?? existing?.symbol ?? "app"
            )
        )
    }

    func resetDefaults() {
        slots = Self.defaults
        resolveMissingBundleIDs()
    }

    func replaceAll(_ newSlots: [HyperAppSlot]) {
        var byDigit: [Int: HyperAppSlot] = [:]
        for s in newSlots where (1...5).contains(s.digit) {
            var fixed = s
            if fixed.actionID.isEmpty {
                fixed.actionID = Self.actionIDsByDigit[fixed.digit] ?? fixed.actionID
            }
            byDigit[fixed.digit] = fixed
        }
        // Fill any missing digits from defaults
        var merged: [HyperAppSlot] = []
        for d in 1...5 {
            if let s = byDigit[d] {
                merged.append(s)
            } else if let def = Self.defaults.first(where: { $0.digit == d }) {
                merged.append(def)
            }
        }
        slots = merged
    }

    // MARK: - Launch

    func launch(actionID: String) {
        guard let slot = slot(actionID: actionID) else {
            Banner.show("App slot not configured", style: .warning)
            return
        }
        // Prefer bundle id; also try Teams classic id if teams2 missing.
        let targets = launchCandidates(for: slot)
        for target in targets {
            if isInstalledOrRunning(target) {
                AppLauncher.shared.launchFocusOrMinimize(target)
                return
            }
        }
        // Last resort — still call launcher with primary target (may show nothing).
        AppLauncher.shared.launchFocusOrMinimize(slot.launchTarget)
        if !isInstalledOrRunning(slot.launchTarget) {
            Banner.show(
                "App not found",
                subtitle: "\(slot.displayName) — reassign in Settings → Apps",
                style: .warning,
                symbol: "app.badge.checkmark"
            )
        }
    }

    private func launchCandidates(for slot: HyperAppSlot) -> [String] {
        var list: [String] = []
        if !slot.bundleID.isEmpty { list.append(slot.bundleID) }
        // Teams ships as teams2 or legacy bundle id
        if slot.bundleID == "com.microsoft.teams2" {
            list.append("com.microsoft.teams")
        } else if slot.bundleID == "com.microsoft.teams" {
            list.append("com.microsoft.teams2")
        }
        if !slot.appName.isEmpty { list.append(slot.appName) }
        if !slot.displayName.isEmpty { list.append(slot.displayName) }
        // Dedupe preserving order
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    private func isInstalledOrRunning(_ target: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications
        if target.contains(".") {
            if running.contains(where: { $0.bundleIdentifier == target }) { return true }
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) != nil {
                return true
            }
        }
        if running.contains(where: { $0.localizedName == target }) { return true }
        let appName = target.hasSuffix(".app") ? target : "\(target).app"
        let paths = [
            "/Applications/\(appName)",
            NSHomeDirectory() + "/Applications/\(appName)",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - UI helpers

    /// Open an app picker and assign the chosen app to `digit`.
    func pickApplication(forDigit digit: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.message = "Choose the app for Hyper+\(digit)"
        panel.prompt = "Assign"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        assign(digit: digit, bundleURL: url)
        Banner.show(
            "Hyper+\(digit)",
            subtitle: slot(digit: digit)?.displayName ?? url.lastPathComponent,
            style: .success,
            symbol: "app.badge"
        )
    }

    /// Quick presets shown in Settings (installed ones first).
    var commonPresets: [(name: String, bundleID: String, symbol: String)] {
        let all: [(String, String, String)] = [
            ("Google Chrome", "com.google.Chrome", "globe"),
            ("Safari", "com.apple.Safari", "safari"),
            ("Firefox", "org.mozilla.firefox", "flame"),
            ("Arc", "company.thebrowser.Browser", "network"),
            ("Zed", "dev.zed.Zed", "chevron.left.forwardslash.chevron.right"),
            ("Visual Studio Code", "com.microsoft.VSCode", "chevron.left.forwardslash.chevron.right"),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "cursorarrow"),
            ("Xcode", "com.apple.dt.Xcode", "hammer"),
            ("Microsoft Teams", "com.microsoft.teams2", "person.3"),
            ("Slack", "com.tinyspeck.slackmacgap", "number"),
            ("Zoom", "us.zoom.xos", "video"),
            ("Messages", "com.apple.MobileSMS", "message"),
            ("Mail", "com.apple.mail", "envelope"),
            ("Notes", "com.apple.Notes", "note.text"),
            ("Finder", "com.apple.finder", "folder"),
            ("Music", "com.apple.Music", "music.note"),
            ("Spotify", "com.spotify.client", "music.note.list"),
        ]
        return all.compactMap { name, bid, symbol in
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
                || FileManager.default.fileExists(atPath: "/Applications/\(name).app")
            {
                return (name, bid, symbol)
            }
            return nil
        }
    }

    // MARK: - Persist

    private func persist() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([HyperAppSlot].self, from: data),
              !decoded.isEmpty
        else {
            slots = Self.defaults
            return
        }
        replaceAll(decoded)
    }

    /// If a slot has a name but empty/wrong bundle id, try to resolve from /Applications.
    private func resolveMissingBundleIDs() {
        var changed = false
        var next = slots
        for i in next.indices {
            let s = next[i]
            if !s.bundleID.isEmpty,
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: s.bundleID) != nil
            {
                continue
            }
            // Try display/app name
            for name in [s.appName, s.displayName] where !name.isEmpty {
                let path = "/Applications/\(name).app"
                if let bid = Bundle(path: path)?.bundleIdentifier {
                    next[i].bundleID = bid
                    changed = true
                    break
                }
            }
            // Teams fallback
            if next[i].actionID == "app-teams" {
                for bid in ["com.microsoft.teams2", "com.microsoft.teams"] {
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                        next[i].bundleID = bid
                        changed = true
                        break
                    }
                }
            }
        }
        if changed { slots = next }
    }

    /// Thread-safe snapshot for catalog UI (no MainActor required).
    nonisolated static func snapshotSlots() -> [HyperAppSlot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([HyperAppSlot].self, from: data),
              !decoded.isEmpty
        else {
            return defaults
        }
        var byDigit: [Int: HyperAppSlot] = [:]
        for s in decoded where (1...5).contains(s.digit) {
            byDigit[s.digit] = s
        }
        return (1...5).compactMap { d in
            byDigit[d] ?? defaults.first { $0.digit == d }
        }
    }
}

// MARK: - Catalog overlay

extension ActionCatalog {
    /// Defaults with Hyper+1…5 titles/details filled from the user's app slots.
    static func resolvedDefaults() -> [HyperAction] {
        let byAction: [String: HyperAppSlot] = Dictionary(
            uniqueKeysWithValues: HyperAppSlotStore.snapshotSlots().map { ($0.actionID, $0) }
        )
        return defaults.map { action in
            guard let slot = byAction[action.id] else { return action }
            var copy = action
            copy.title = slot.displayName
            copy.detail = "Hyper+\(slot.digit) · launch → focus → minimize"
            copy.symbol = slot.symbol
            return copy
        }
    }
}
