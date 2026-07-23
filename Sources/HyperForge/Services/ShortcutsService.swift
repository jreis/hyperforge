// ShortcutsService.swift
// List & run installed macOS Shortcuts via the local `shortcuts` CLI.

import AppKit
import Foundation

enum ShortcutsService {
    private static let recentKey = "hf.shortcuts.recent"
    private static let maxRecent = 8
    private static let maxMenuItems = 80
    private static let cacheTTL: TimeInterval = 30

    private static var cachedNames: [String]?
    private static var cacheDate: Date?
    private static let cacheLock = NSLock()

    /// Names of installed shortcuts (cached briefly — `shortcuts list` can be slow).
    static func listNames(forceRefresh: Bool = false) -> [String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if !forceRefresh,
           let cached = cachedNames,
           let date = cacheDate,
           Date().timeIntervalSince(date) < cacheTTL
        {
            return cached
        }
        let names = fetchNamesFromCLI()
        cachedNames = names
        cacheDate = Date()
        return names
    }

    static func invalidateCache() {
        cacheLock.lock()
        cachedNames = nil
        cacheDate = nil
        cacheLock.unlock()
    }

    /// Run a shortcut by exact name (as shown in Shortcuts.app / `shortcuts list`).
    static func run(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", trimmed]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                DispatchQueue.main.async {
                    if ok {
                        rememberRecent(trimmed)
                        Banner.show(
                            "Shortcut",
                            subtitle: trimmed,
                            style: .success,
                            symbol: "sparkles.rectangle.stack"
                        )
                        HyperLog.event("Shortcut ran: \(trimmed)")
                    } else {
                        Banner.show(
                            "Shortcut failed",
                            subtitle: trimmed,
                            style: .warning,
                            symbol: "exclamationmark.triangle"
                        )
                        HyperLog.event("Shortcut failed (\(process.terminationStatus)): \(trimmed)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    Banner.show(
                        "Shortcuts unavailable",
                        subtitle: error.localizedDescription,
                        style: .danger,
                        symbol: "exclamationmark.triangle"
                    )
                }
            }
        }
    }

    /// Cursor menu of installed shortcuts (recents first).
    @MainActor
    static func showMenu() {
        // Prefer cache so the menu is instant; cold list runs off the main thread.
        cacheLock.lock()
        let warm = cachedNames
        let fresh = cacheDate.map { Date().timeIntervalSince($0) < cacheTTL } ?? false
        cacheLock.unlock()

        if let warm, fresh {
            presentMenu(names: warm)
            return
        }

        if let warm {
            // Stale-but-usable list now; refresh in background for next open.
            presentMenu(names: warm)
            DispatchQueue.global(qos: .utility).async {
                _ = listNames(forceRefresh: true)
            }
            return
        }

        Banner.show(
            "Loading shortcuts…",
            style: .info,
            symbol: "sparkles.rectangle.stack"
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let names = listNames(forceRefresh: true)
            DispatchQueue.main.async {
                presentMenu(names: names)
            }
        }
    }

    @MainActor
    private static func presentMenu(names all: [String]) {
        let menu = NSMenu(title: "Run Shortcut")
        let recent = recentNames().filter { all.contains($0) }
        let recentSet = Set(recent)

        if all.isEmpty {
            let empty = NSMenuItem(
                title: "No shortcuts found",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
            menu.addItem(.separator())
            let open = NSMenuItem(
                title: "Open Shortcuts app",
                action: #selector(ShortcutsMenuTarget.openApp),
                keyEquivalent: ""
            )
            open.target = ShortcutsMenuTarget.shared
            open.image = NSImage(
                systemSymbolName: "square.stack.3d.up",
                accessibilityDescription: nil
            )
            menu.addItem(open)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }

        if !recent.isEmpty {
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for name in recent {
                menu.addItem(shortcutItem(name))
            }
            menu.addItem(.separator())
        }

        let rest = all.filter { !recentSet.contains($0) }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let limited = Array(rest.prefix(maxMenuItems))
        for name in limited {
            menu.addItem(shortcutItem(name))
        }
        if rest.count > maxMenuItems {
            let more = NSMenuItem(
                title: "…and \(rest.count - maxMenuItems) more (search in Shortcuts)",
                action: nil,
                keyEquivalent: ""
            )
            more.isEnabled = false
            menu.addItem(more)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(
            title: "Refresh list",
            action: #selector(ShortcutsMenuTarget.refreshAndShow),
            keyEquivalent: ""
        )
        refresh.target = ShortcutsMenuTarget.shared
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refresh)

        let open = NSMenuItem(
            title: "Open Shortcuts app",
            action: #selector(ShortcutsMenuTarget.openApp),
            keyEquivalent: ""
        )
        open.target = ShortcutsMenuTarget.shared
        open.image = NSImage(
            systemSymbolName: "square.stack.3d.up",
            accessibilityDescription: nil
        )
        menu.addItem(open)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Private

    @MainActor
    private static func shortcutItem(_ name: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: name,
            action: #selector(ShortcutsMenuTarget.runShortcut(_:)),
            keyEquivalent: ""
        )
        item.representedObject = name
        item.target = ShortcutsMenuTarget.shared
        item.image = NSImage(
            systemSymbolName: "sparkles.rectangle.stack",
            accessibilityDescription: name
        )
        return item
    }

    private static func fetchNamesFromCLI() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func recentNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private static func rememberRecent(_ name: String) {
        var list = recentNames().filter { $0 != name }
        list.insert(name, at: 0)
        if list.count > maxRecent {
            list = Array(list.prefix(maxRecent))
        }
        UserDefaults.standard.set(list, forKey: recentKey)
    }
}

@MainActor
final class ShortcutsMenuTarget: NSObject {
    static let shared = ShortcutsMenuTarget()

    @objc func runShortcut(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ShortcutsService.run(name: name)
    }

    @objc func refreshAndShow() {
        ShortcutsService.invalidateCache()
        _ = ShortcutsService.listNames(forceRefresh: true)
        ShortcutsService.showMenu()
    }

    @objc func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let url = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(url)
        }
    }
}
