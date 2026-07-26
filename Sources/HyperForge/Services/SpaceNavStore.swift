// SpaceNavStore.swift
// Space-layer (TouchCursor) settings: global enable, hold threshold, per-app block list.
// Event-tap path reads a lock-based SpaceNavRuntime snapshot only.

import AppKit
import Combine
import Foundation

/// One app where Space navigation should stay off (terminals, Vim, …).
struct SpaceNavBlockedApp: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String

    var displayTitle: String {
        appName.isEmpty ? bundleID : appName
    }
}

/// Thread-safe snapshot for the CGEvent tap (never hops to MainActor).
final class SpaceNavRuntime: @unchecked Sendable {
    static let shared = SpaceNavRuntime()

    private let lock = NSLock()
    private var enabled = true
    private var holdMs = 0
    private var blockedBundleIDs: Set<String> = []
    private var frontmostBundleID: String?

    private init() {}

    func apply(enabled: Bool, holdMs: Int, blocked: Set<String>) {
        lock.lock()
        self.enabled = enabled
        self.holdMs = max(0, min(holdMs, 400))
        self.blockedBundleIDs = blocked
        lock.unlock()
    }

    func setFrontmostBundleID(_ id: String?) {
        lock.lock()
        frontmostBundleID = id
        lock.unlock()
    }

    var frontmostID: String? {
        lock.lock(); defer { lock.unlock() }
        return frontmostBundleID
    }

    /// Best-effort live frontmost (event tap runs on the main run loop).
    /// Keeps the cache warm and avoids a one-activation lag after app switches.
    @discardableResult
    func refreshFrontmostLive() -> String? {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        setFrontmostBundleID(bid)
        return bid
    }

    /// Whether Space should be captured for the layer right now.
    /// Always re-reads frontmost so Ghostty / app switches are not gated by a stale cache.
    func shouldCaptureSpace() -> Bool {
        let live = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lock.lock()
        if let live {
            frontmostBundleID = live
        }
        let bid = live ?? frontmostBundleID
        let allow = enabled && !(bid.map { blockedBundleIDs.contains($0) } ?? false)
        lock.unlock()
        return allow
    }

    /// True when the frontmost app is a terminal emulator (shell / TUI).
    /// Used so Space-layer word/line motions use readline chords (⌃A/E, ⌥B/F) instead of
    /// Cocoa ⌘← / ⌥← which most terminals ignore.
    func frontmostIsTerminalEmulator() -> Bool {
        let bid = currentFrontmostBundleID()?.lowercased() ?? ""
        guard !bid.isEmpty else { return false }
        // Exact known IDs (including Ghostty — intentionally unblocked for Space nav).
        let known: Set<String> = [
            "com.mitchellh.ghostty",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "dev.warp.warp-stable",
            "dev.warp.warp",
            "org.alacritty",
            "co.zeit.hyper",
            "com.github.rionninge.rio",
        ]
        if known.contains(bid) { return true }
        if bid.contains("ghostty") { return true }
        if bid.contains("terminal") { return true }
        if bid.contains("iterm") { return true }
        if bid.contains("alacritty") || bid.contains("wezterm") || bid.contains("kitty") {
            return true
        }
        return false
    }

    /// Chrome / Brave / Edge / Arc / Safari — Monaco & contenteditable need solid HID injection
    /// and prefer Home/End over ⌘← for line motions (CodeSignal, LeetCode, etc.).
    func frontmostIsBrowser() -> Bool {
        let bid = currentFrontmostBundleID()?.lowercased() ?? ""
        guard !bid.isEmpty else { return false }
        let known: Set<String> = [
            "com.google.chrome",
            "com.google.chrome.beta",
            "com.google.chrome.canary",
            "com.google.chrome.dev",
            "com.brave.browser",
            "com.brave.browser.beta",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.beta",
            "company.thebrowser.browser", // Arc
            "com.apple.safari",
            "com.apple.safaritechnologypreview",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "com.operasoftware.opera",
            "com.vivaldi.vivaldi",
            "com.kagi.kagibrowser",
            "app.zen-browser.zen",
        ]
        if known.contains(bid) { return true }
        if bid.contains("chrome") || bid.contains("chromium") { return true }
        if bid.contains("brave") || bid.contains("edgemac") { return true }
        if bid.contains("firefox") || bid.contains("safari") { return true }
        if bid.contains("codesignal") { return true }
        return false
    }

    private func currentFrontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? frontmostID
    }

    var holdMilliseconds: Int {
        lock.lock(); defer { lock.unlock() }
        return holdMs
    }
}

@MainActor
final class SpaceNavStore: ObservableObject {
    static let shared = SpaceNavStore()

    static let enabledKey = "hf.spaceNavEnabled"
    static let holdMsKey = "hf.spaceNavHoldMs"
    static let blockedKey = "hf.spaceNavBlockedApps"
    static let seededKey = "hf.spaceNavDefaultsSeeded"
    /// Sticky on-screen NAV pill while Space layer is armed.
    static let hudKey = "hf.showSpaceLayerHUD"
    /// One-time: allow Space nav in Ghostty (removed from defaults after seed).
    static let ghosttyUnblockMigrationKey = "hf.spaceNavUnblockGhostty"
    /// One-time: typing-safe hold default (was 0 = instant arm, bad for fast typists).
    static let typistHoldMigrationKey = "hf.spaceNavTypistHoldV1"
    /// Second pass: bump prior 160ms default to 200ms for faster typists.
    static let typistHoldMigrationKeyV2 = "hf.spaceNavTypistHoldV2"
    /// Default hold before Space becomes a nav layer (ms).
    static let defaultHoldMilliseconds = 200

    /// Sensible defaults — terminals & modal Vim UIs where Space must type.
    /// Ghostty is intentionally **not** blocked so Space+HJKL works for shell navigation.
    static let defaultBlocked: [(bundleID: String, name: String)] = [
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm2"),
        // Ghostty: allow Space nav (preferred terminal for many HyperForge users)
        ("net.kovidgoyal.kitty", "Kitty"),
        ("com.github.wez.wezterm", "WezTerm"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("dev.warp.Warp", "Warp"),
        ("org.vim.MacVim", "MacVim"),
        ("com.qvacua.VimR", "VimR"),
        ("com.apple.vim", "Vim"),
        ("com.neovimnvim.Vim", "Neovim"),
        // Full-screen / exclusive input
        ("com.valvesoftware.steam", "Steam"),
        ("com.apple.ScreenSharing", "Screen Sharing"),
    ]

    static let ghosttyBundleID = "com.mitchellh.ghostty"

    @Published var isEnabled: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            VimNavigation.shared.setEnabled(isEnabled, persist: false)
            pushRuntime()
        }
    }

    /// Show the floating NAV pill while Space layer is armed (default on).
    @Published var showLayerHUD: Bool = true {
        didSet {
            guard !isBootstrapping else { return }
            UserDefaults.standard.set(showLayerHUD, forKey: Self.hudKey)
            if !showLayerHUD {
                Task { @MainActor in SpaceLayerHUD.hide() }
            }
        }
    }

    /// Hold duration before Space arms as nav layer. 0 = arm immediately (power mode).
    /// ~160ms is typing-safe: keys during the window type space + letter, not chords.
    @Published var holdMilliseconds: Int = SpaceNavStore.defaultHoldMilliseconds {
        didSet {
            guard !isBootstrapping else { return }
            let clamped = max(0, min(holdMilliseconds, 400))
            if clamped != holdMilliseconds {
                holdMilliseconds = clamped
                return
            }
            UserDefaults.standard.set(holdMilliseconds, forKey: Self.holdMsKey)
            pushRuntime()
        }
    }

    @Published var blockedApps: [SpaceNavBlockedApp] = [] {
        didSet {
            guard !isBootstrapping else { return }
            persistBlocked()
            pushRuntime()
        }
    }

    private var isBootstrapping = true
    private var workspaceObs: NSObjectProtocol?
    private var launchObs: NSObjectProtocol?

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.enabledKey) != nil {
            isEnabled = d.bool(forKey: Self.enabledKey)
        }
        if d.object(forKey: Self.hudKey) != nil {
            showLayerHUD = d.bool(forKey: Self.hudKey)
        }
        if let stored = d.object(forKey: Self.holdMsKey) as? Int {
            holdMilliseconds = stored
        } else {
            holdMilliseconds = Self.defaultHoldMilliseconds
        }
        loadBlocked()
        if !d.bool(forKey: Self.seededKey) {
            seedDefaultsIfEmpty()
            d.set(true, forKey: Self.seededKey)
            persistBlocked()
        }
        // Existing installs had Ghostty on the block list — open it for Space nav.
        if !d.bool(forKey: Self.ghosttyUnblockMigrationKey) {
            blockedApps.removeAll { $0.bundleID == Self.ghosttyBundleID }
            d.set(true, forKey: Self.ghosttyUnblockMigrationKey)
            persistBlocked()
        }
        // Instant arm (0ms) makes Space+next-key fire chords while typing quickly.
        // One-time bump to typing-safe default; user can set 0 again in Settings.
        if !d.bool(forKey: Self.typistHoldMigrationKey) {
            if (d.object(forKey: Self.holdMsKey) as? Int) == 0 {
                holdMilliseconds = Self.defaultHoldMilliseconds
            }
            d.set(true, forKey: Self.typistHoldMigrationKey)
            d.set(holdMilliseconds, forKey: Self.holdMsKey)
        }
        // Users still on the old 160ms default → 200ms (explicit custom values left alone).
        if !d.bool(forKey: Self.typistHoldMigrationKeyV2) {
            if (d.object(forKey: Self.holdMsKey) as? Int) == 160 {
                holdMilliseconds = Self.defaultHoldMilliseconds
                d.set(holdMilliseconds, forKey: Self.holdMsKey)
            }
            d.set(true, forKey: Self.typistHoldMigrationKeyV2)
        }
        isBootstrapping = false
        VimNavigation.shared.setEnabled(isEnabled, persist: false)
        pushRuntime()
        startFrontmostTracking()
        refreshFrontmost()
    }

    deinit {
        if let workspaceObs { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObs) }
        if let launchObs { NSWorkspace.shared.notificationCenter.removeObserver(launchObs) }
    }

    // MARK: - Block list

    func addFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier
        else { return }
        add(bundleID: bid, appName: app.localizedName ?? bid)
    }

    func add(bundleID: String, appName: String) {
        let bid = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { return }
        guard !blockedApps.contains(where: { $0.bundleID == bid }) else { return }
        blockedApps.append(
            SpaceNavBlockedApp(bundleID: bid, appName: appName.isEmpty ? bid : appName)
        )
    }

    func remove(_ app: SpaceNavBlockedApp) {
        blockedApps.removeAll { $0.id == app.id }
    }

    func remove(bundleID: String) {
        blockedApps.removeAll { $0.bundleID == bundleID }
    }

    func isBlocked(bundleID: String) -> Bool {
        blockedApps.contains { $0.bundleID == bundleID }
    }

    func restoreDefaultBlockedApps() {
        var merged = blockedApps
        for preset in Self.defaultBlocked {
            if !merged.contains(where: { $0.bundleID == preset.bundleID }) {
                merged.append(SpaceNavBlockedApp(bundleID: preset.bundleID, appName: preset.name))
            }
        }
        blockedApps = merged
    }

    /// Full replace used by config import.
    func applyImport(enabled: Bool, holdMilliseconds: Int, blockedApps: [SpaceNavBlockedApp]) {
        isBootstrapping = true
        isEnabled = enabled
        self.holdMilliseconds = max(0, min(holdMilliseconds, 400))
        self.blockedApps = blockedApps
        isBootstrapping = false
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        UserDefaults.standard.set(self.holdMilliseconds, forKey: Self.holdMsKey)
        persistBlocked()
        VimNavigation.shared.setEnabled(isEnabled, persist: false)
        pushRuntime()
    }

    /// Merge store block list + AppOverride.disableSpaceNav flags into runtime.
    func pushRuntime() {
        var set = Set(blockedApps.map(\.bundleID))
        for ov in AppOverrideStore.shared.overrides where ov.isEnabled && ov.disableSpaceNav {
            set.insert(ov.bundleID)
        }
        SpaceNavRuntime.shared.apply(
            enabled: isEnabled,
            holdMs: holdMilliseconds,
            blocked: set
        )
    }

    // MARK: - Frontmost tracking

    func startFrontmostTracking() {
        guard workspaceObs == nil else { return }
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFrontmost() }
        }
        launchObs = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFrontmost() }
        }
    }

    func refreshFrontmost() {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        SpaceNavRuntime.shared.setFrontmostBundleID(bid)
    }

    // MARK: - Persist

    private func loadBlocked() {
        guard let data = UserDefaults.standard.data(forKey: Self.blockedKey),
              let decoded = try? JSONDecoder().decode([SpaceNavBlockedApp].self, from: data)
        else {
            blockedApps = []
            return
        }
        blockedApps = decoded
    }

    private func persistBlocked() {
        if let data = try? JSONEncoder().encode(blockedApps) {
            UserDefaults.standard.set(data, forKey: Self.blockedKey)
        }
    }

    private func seedDefaultsIfEmpty() {
        guard blockedApps.isEmpty else { return }
        blockedApps = Self.defaultBlocked.map {
            SpaceNavBlockedApp(bundleID: $0.bundleID, appName: $0.name)
        }
    }
}
