// TerminalPreference.swift
// Preferred terminal is user-configurable (Ghostty, iTerm2, Terminal, Warp, …).

import AppKit
import Combine
import Foundation

/// Built-in presets + custom bundle ID support.
struct TerminalAppOption: Identifiable, Equatable, Hashable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let symbol: String

    static let presets: [TerminalAppOption] = [
        TerminalAppOption(name: "Ghostty", bundleID: "com.mitchellh.ghostty", symbol: "terminal.fill"),
        TerminalAppOption(name: "iTerm2", bundleID: "com.googlecode.iterm2", symbol: "terminal"),
        TerminalAppOption(name: "Terminal", bundleID: "com.apple.Terminal", symbol: "terminal"),
        TerminalAppOption(name: "Warp", bundleID: "dev.warp.Warp-Stable", symbol: "bolt.horizontal.circle"),
        TerminalAppOption(name: "Kitty", bundleID: "net.kovidgoyal.kitty", symbol: "cat"),
        TerminalAppOption(name: "Alacritty", bundleID: "org.alacritty", symbol: "terminal"),
        TerminalAppOption(name: "WezTerm", bundleID: "com.github.wez.wezterm", symbol: "terminal"),
        // Alternate Warp bundle seen in the wild
        TerminalAppOption(name: "Warp (alt)", bundleID: "dev.warp.Warp", symbol: "bolt.horizontal.circle"),
    ]
}

/// What Hyper+T does when the terminal is already running.
enum TerminalReuseMode: String, CaseIterable, Identifiable {
    case newTab
    case newWindow
    case focusOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: return "New tab"
        case .newWindow: return "New window"
        case .focusOnly: return "Just focus"
        }
    }

    var detail: String {
        switch self {
        case .newTab: return "⌘T in the existing instance (recommended)"
        case .newWindow: return "⌘N — separate window"
        case .focusOnly: return "Bring terminal forward, no new session"
        }
    }
}

@MainActor
final class TerminalPreference: ObservableObject {
    static let shared = TerminalPreference()

    /// Stored bundle ID of the preferred terminal.
    @Published var bundleID: String {
        didSet {
            UserDefaults.standard.set(bundleID, forKey: Self.bundleKey)
            objectWillChange.send()
        }
    }

    /// Hyper+T reuse behavior when the app is already running.
    @Published var reuseMode: TerminalReuseMode {
        didSet {
            UserDefaults.standard.set(reuseMode.rawValue, forKey: Self.reuseKey)
            objectWillChange.send()
        }
    }

    private static let bundleKey = "hf.preferredTerminalBundleID"
    private static let reuseKey = "hf.terminalReuseMode"

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.bundleKey), !saved.isEmpty {
            bundleID = saved
        } else {
            bundleID = Self.detectDefault().bundleID
        }
        if let raw = UserDefaults.standard.string(forKey: Self.reuseKey),
           let mode = TerminalReuseMode(rawValue: raw)
        {
            reuseMode = mode
        } else {
            reuseMode = .newTab
        }
    }

    var isRunning: Bool { findRunning() != nil }

    /// Prefer exact bundle ID; also match by name / “ghostty” substring so we never
    /// miss a live process and accidentally call `openApplication` (new window).
    func findRunning() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let exact = apps.first(where: { $0.bundleIdentifier == bundleID }) {
            return exact
        }
        let name = current.name
        if let byName = apps.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return byName
        }
        // Ghostty / app renames
        let needle = bundleID.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        if needle.count >= 4 {
            return apps.first(where: {
                $0.bundleIdentifier?.lowercased().contains(needle) == true
                    || $0.localizedName?.lowercased().contains(needle) == true
            })
        }
        return nil
    }

    /// Currently selected option (preset or custom).
    var current: TerminalAppOption {
        if let preset = TerminalAppOption.presets.first(where: { $0.bundleID == bundleID }) {
            return preset
        }
        let name =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
            ?? bundleID
        return TerminalAppOption(name: name, bundleID: bundleID, symbol: "terminal")
    }

    /// Presets that are actually installed, plus current if custom.
    var installedOptions: [TerminalAppOption] {
        var list = TerminalAppOption.presets.filter { isInstalled($0.bundleID) }
        // Dedupe Warp variants if both missing one
        var seen = Set<String>()
        list = list.filter { seen.insert($0.bundleID).inserted }
        if !list.contains(where: { $0.bundleID == bundleID }), isInstalled(bundleID) {
            list.insert(current, at: 0)
        }
        // Always offer Terminal as last-resort fallback entry
        if !list.contains(where: { $0.bundleID == "com.apple.Terminal" }) {
            list.append(
                TerminalAppOption(
                    name: "Terminal",
                    bundleID: "com.apple.Terminal",
                    symbol: "terminal"
                )
            )
        }
        return list
    }

    func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// First installed from preference order: Ghostty → iTerm → Warp → Kitty → Wez → Alacritty → Terminal.
    static func detectDefault() -> TerminalAppOption {
        let order = [
            "com.mitchellh.ghostty",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "org.alacritty",
            "com.apple.Terminal",
        ]
        for id in order {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil,
               let preset = TerminalAppOption.presets.first(where: { $0.bundleID == id })
            {
                return preset
            }
        }
        return TerminalAppOption(
            name: "Terminal",
            bundleID: "com.apple.Terminal",
            symbol: "terminal"
        )
    }

    // MARK: - Actions

    func launchOrFocus() {
        activateExistingOrLaunch()
    }

    /// Hyper+T entry point — reuses a running instance when possible.
    func openSmart() {
        if let running = findRunning() {
            switch reuseMode {
            case .newTab:
                openNewTab(in: running)
            case .newWindow:
                openNewWindow(in: running)
            case .focusOnly:
                activateOnly(running)
                Banner.show(
                    current.name,
                    subtitle: "Focused (no new session)",
                    style: .info,
                    symbol: "terminal"
                )
            }
        } else {
            // Cold start only — never send ⌘N/⌘T (that would open a second surface).
            coldLaunch()
            Banner.show(
                current.name,
                subtitle: "Launched",
                style: .info,
                symbol: "terminal"
            )
        }
    }

    /// New tab in the existing instance. Does **not** call `openApplication` if already running.
    func openNewTab() {
        if let running = findRunning() {
            openNewTab(in: running)
        } else {
            coldLaunch()
            Banner.show(current.name, subtitle: "Launched", style: .info, symbol: "terminal")
        }
    }

    private func openNewTab(in app: NSRunningApplication) {
        activateOnly(app)
        // Target this process with System Events so ⌘T can't hit another app,
        // and so we never re-open Ghostty (which spawns a new window/instance).
        let processName = app.localizedName ?? current.name
        let bid = app.bundleIdentifier ?? bundleID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let ok = self.keystrokeToProcess(
                processName: processName,
                bundleID: bid,
                key: "t",
                command: true
            )
            if !ok {
                // Fallback: global synthesizer only if frontmost is already our terminal
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    EventSynthesizer.postCommandKey(KeyCode.t)
                } else {
                    app.activate(options: [.activateAllWindows])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        EventSynthesizer.postCommandKey(KeyCode.t)
                    }
                }
            }
            Banner.show(
                self.current.name,
                subtitle: "New tab",
                style: .success,
                symbol: "plus.rectangle.on.rectangle"
            )
            HyperLog.event("terminal newTab → \(bid) via \(ok ? "System Events" : "CGEvent")")
        }
    }

    /// Open a new terminal *window* in the existing app (or launch once).
    func openNewWindow(force: Bool = true) {
        if let running = findRunning() {
            openNewWindow(in: running)
        } else {
            coldLaunch()
            Banner.show(current.name, subtitle: "Launched", style: .info, symbol: "macwindow.badge.plus")
        }
    }

    private func openNewWindow(in app: NSRunningApplication) {
        let id = app.bundleIdentifier ?? bundleID
        switch id {
        case "com.apple.Terminal":
            runAppleScript(
                """
                tell application "Terminal"
                    activate
                    do script ""
                end tell
                """
            )
        case "com.googlecode.iterm2":
            let ok = runAppleScript(
                """
                tell application "iTerm2"
                    activate
                    create window with default profile
                end tell
                """
            )
            if !ok {
                activateOnly(app)
                keystrokeToProcess(
                    processName: app.localizedName ?? "iTerm2",
                    bundleID: id,
                    key: "n",
                    command: true
                )
            }
        default:
            activateOnly(app)
            let processName = app.localizedName ?? current.name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                _ = self.keystrokeToProcess(
                    processName: processName,
                    bundleID: id,
                    key: "n",
                    command: true
                )
            }
        }
        Banner.show(
            current.name,
            subtitle: "New window",
            style: .info,
            symbol: "macwindow.badge.plus"
        )
    }

    /// Activate only — never `openApplication` (Ghostty treats that as a new instance).
    private func activateOnly(_ app: NSRunningApplication) {
        app.activate(options: [.activateAllWindows])
    }

    private func activateExistingOrLaunch() {
        if let app = findRunning() {
            activateOnly(app)
            return
        }
        coldLaunch()
    }

    private func coldLaunch() {
        guard findRunning() == nil else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, err in
                if let err {
                    HyperLog.event("terminal coldLaunch error: \(err.localizedDescription)")
                }
            }
            return
        }
        AppLauncher.shared.launchOrFocus(bundleID)
    }

    /// Send a key to a specific app process (System Events). Requires Accessibility.
    @discardableResult
    private func keystrokeToProcess(
        processName: String,
        bundleID: String,
        key: String,
        command: Bool
    ) -> Bool {
        let mods = command ? "command down" : ""
        // Prefer bundle id match; fall back to process name (Ghostty).
        let script = """
            tell application "System Events"
                set targetProc to missing value
                try
                    set targetProc to first process whose bundle identifier is "\(bundleID)"
                end try
                if targetProc is missing value then
                    try
                        set targetProc to first process whose name is "\(processName)"
                    end try
                end if
                if targetProc is missing value then return false
                set frontmost of targetProc to true
                delay 0.05
                tell targetProc
                    keystroke "\(key)" using {\(mods)}
                end tell
                return true
            end tell
            """
        return runAppleScript(script)
    }

    /// Open terminal with working directory (Finder “terminal here”).
    func openInDirectory(_ path: String) {
        let id = bundleID
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        // Single-quoted path for shell (handles spaces; escape embedded ')
        let shellQuoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"

        switch id {
        case "com.apple.Terminal":
            // Terminal accepts a folder via `open -a` and cds there.
            if openFolderWithApp(path: path) || runAppleScript(
                """
                tell application "Terminal"
                    activate
                    do script "cd \(shellQuoted)"
                end tell
                """
            ) {
                Banner.show("Terminal → \(folderName)", style: .success, symbol: "folder")
            } else {
                openAndTypeCD(path: path, alreadyRunningDelay: 0.25, launchDelay: 0.8)
            }
            return

        case "com.googlecode.iterm2":
            let ok = runAppleScript(
                """
                tell application "iTerm2"
                    activate
                    try
                        create window with default profile command "cd \(shellQuoted) && exec $SHELL -l"
                    on error
                        create window with default profile
                        tell current session of current window
                            write text "cd \(shellQuoted)"
                        end tell
                    end try
                end tell
                """
            )
            if ok {
                Banner.show("\(current.name) → \(folderName)", style: .success, symbol: "folder")
            } else {
                openAndTypeCD(path: path, alreadyRunningDelay: 0.3, launchDelay: 0.8)
            }
            return

        case "com.mitchellh.ghostty":
            // Prefer CLI with working-directory when cold; if running, new tab + cd
            // (CLI while running can spawn a second Ghostty instance).
            if findRunning() == nil,
               openViaCLI(["ghostty"], args: ["--working-directory=\(path)"])
            {
                Banner.show("Ghostty → \(folderName)", style: .success, symbol: "folder")
                return
            }
            // Also try: open -na Ghostty --args --working-directory=…
            if findRunning() == nil, openGhosttyWorkingDirectory(path) {
                Banner.show("Ghostty → \(folderName)", style: .success, symbol: "folder")
                return
            }
            openAndTypeCD(path: path, alreadyRunningDelay: 0.25, launchDelay: 0.85)
            return

        case "dev.warp.Warp-Stable", "dev.warp.Warp":
            openAndTypeCD(path: path, alreadyRunningDelay: 0.4, launchDelay: 1.0)
            return

        case "net.kovidgoyal.kitty":
            if openViaCLI(["kitty"], args: ["--directory", path]) {
                Banner.show("Kitty → \(folderName)", style: .success, symbol: "folder")
                return
            }
            openAndTypeCD(path: path, alreadyRunningDelay: 0.35, launchDelay: 0.9)
            return

        case "com.github.wez.wezterm":
            if openViaCLI(["wezterm"], args: ["start", "--cwd", path]) {
                Banner.show("WezTerm → \(folderName)", style: .success, symbol: "folder")
                return
            }
            openAndTypeCD(path: path, alreadyRunningDelay: 0.35, launchDelay: 0.9)
            return

        case "org.alacritty":
            if openViaCLI(["alacritty"], args: ["--working-directory", path]) {
                Banner.show("Alacritty → \(folderName)", style: .success, symbol: "folder")
                return
            }
            openAndTypeCD(path: path, alreadyRunningDelay: 0.35, launchDelay: 0.9)
            return

        default:
            openAndTypeCD(path: path, alreadyRunningDelay: 0.35, launchDelay: 0.9)
        }
    }

    /// `open -a Terminal /path` style handoff (works well for Terminal.app).
    @discardableResult
    private func openFolderWithApp(path: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([dir], withApplicationAt: appURL, configuration: config) { _, err in
            if let err {
                HyperLog.event("openFolderWithApp error: \(err.localizedDescription)")
            }
        }
        return true
    }

    @discardableResult
    private func openGhosttyWorkingDirectory(_ path: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.mitchellh.ghostty"
        ) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [
            "-na", appURL.path,
            "--args", "--working-directory=\(path)",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            return true
        } catch {
            return false
        }
    }

    /// Run a shell command in a new terminal session (e.g. `nvim /path/file`).
    func runCommand(_ command: String) {
        let id = bundleID
        let shellCmd = command.replacingOccurrences(of: "\"", with: "\\\"")

        switch id {
        case "com.apple.Terminal":
            let q = command.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            runAppleScript(
                """
                tell application "Terminal"
                    activate
                    do script "\(q)"
                end tell
                """
            )
        case "com.googlecode.iterm2":
            let q = command.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            runAppleScript(
                """
                tell application "iTerm2"
                    activate
                    try
                        create window with default profile
                    end try
                    tell current session of current window
                        write text "\(q)"
                    end tell
                end tell
                """
            )
        default:
            if let app = findRunning() {
                activateOnly(app)
                let processName = app.localizedName ?? current.name
                let bid = app.bundleIdentifier ?? bundleID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    _ = self.keystrokeToProcess(
                        processName: processName,
                        bundleID: bid,
                        key: "t",
                        command: true
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        EventSynthesizer.typeString(shellCmd)
                        EventSynthesizer.postKey(KeyCode.return)
                    }
                }
            } else {
                coldLaunch()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    EventSynthesizer.typeString(shellCmd)
                    EventSynthesizer.postKey(KeyCode.return)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Types `cd 'path'` into a new tab/window. `path` must be a raw filesystem path (not pre-escaped).
    private func openAndTypeCD(path: String, alreadyRunningDelay: TimeInterval, launchDelay: TimeInterval) {
        // Prefer single quotes for shell safety (spaces, $, etc.)
        let typed = "cd " + "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let folderName = URL(fileURLWithPath: path).lastPathComponent

        if let app = findRunning() {
            activateOnly(app)
            let processName = app.localizedName ?? current.name
            let bid = app.bundleIdentifier ?? bundleID
            let useNewTab = reuseMode == .newTab
            DispatchQueue.main.asyncAfter(deadline: .now() + alreadyRunningDelay) {
                if useNewTab {
                    _ = self.keystrokeToProcess(
                        processName: processName,
                        bundleID: bid,
                        key: "t",
                        command: true
                    )
                } else if self.reuseMode == .newWindow {
                    _ = self.keystrokeToProcess(
                        processName: processName,
                        bundleID: bid,
                        key: "n",
                        command: true
                    )
                }
                let typeDelay: TimeInterval = useNewTab || self.reuseMode == .newWindow ? 0.28 : 0.12
                DispatchQueue.main.asyncAfter(deadline: .now() + typeDelay) {
                    // Ensure terminal is frontmost before typing
                    if let running = self.findRunning() {
                        running.activate(options: [.activateAllWindows])
                    }
                    EventSynthesizer.typeString(typed)
                    EventSynthesizer.postKey(KeyCode.return)
                    Banner.show(
                        "\(self.current.name) → \(folderName)",
                        style: .success,
                        symbol: "folder"
                    )
                    HyperLog.event("openAndTypeCD typed into \(bid)")
                }
            }
            return
        }
        coldLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + launchDelay) {
            if let running = self.findRunning() {
                running.activate(options: [.activateAllWindows])
            }
            EventSynthesizer.typeString(typed)
            EventSynthesizer.postKey(KeyCode.return)
            Banner.show(
                "\(self.current.name) → \(folderName)",
                style: .success,
                symbol: "folder"
            )
            HyperLog.event("openAndTypeCD after cold launch")
        }
    }

    @discardableResult
    private func openViaCLI(_ names: [String], args: [String]) -> Bool {
        let paths = names.flatMap { name -> [String] in
            [
                "/opt/homebrew/bin/\(name)",
                "/usr/local/bin/\(name)",
                "\(NSHomeDirectory())/.local/bin/\(name)",
                "/Applications/\(name).app/Contents/MacOS/\(name)",
            ]
        }
        guard let exe = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
