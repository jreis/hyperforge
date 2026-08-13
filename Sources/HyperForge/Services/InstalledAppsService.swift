// InstalledAppsService.swift
// Enumerates installed .app bundles for the Command Bar's app launcher — broader
// than the 5 user-configurable Hyper app slots (HyperAppSlotStore).

import AppKit
import Foundation

struct InstalledApp: Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var url: URL
}

enum InstalledAppsService {
    private static let cacheTTL: TimeInterval = 300
    private static let searchDirectories = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    private static var cachedApps: [InstalledApp]?
    private static var cacheDate: Date?
    private static let cacheLock = NSLock()

    /// Full scan of standard app directories, one vendor-subfolder deep — can take
    /// noticeable time with many apps installed, so hot paths should use
    /// `cachedOrRefreshing()` instead.
    static func scan(forceRefresh: Bool = false) -> [InstalledApp] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if !forceRefresh,
           let cached = cachedApps,
           let date = cacheDate,
           Date().timeIntervalSince(date) < cacheTTL
        {
            return cached
        }
        let apps = scanDirectories()
        cachedApps = apps
        cacheDate = Date()
        return apps
    }

    /// Cached apps only — never blocks on disk I/O. Used on hot paths (e.g.
    /// command-bar keystrokes). Kicks off a background refresh when stale so the
    /// *next* call sees fresh data.
    static func cachedOrRefreshing() -> [InstalledApp] {
        cacheLock.lock()
        let cached = cachedApps
        let isStale = cacheDate.map { Date().timeIntervalSince($0) >= cacheTTL } ?? true
        cacheLock.unlock()
        if isStale {
            DispatchQueue.global(qos: .utility).async { _ = scan(forceRefresh: true) }
        }
        return cached ?? []
    }

    private static func scanDirectories() -> [InstalledApp] {
        var seen = Set<String>()
        var results: [InstalledApp] = []
        let fm = FileManager.default
        for dir in searchDirectories {
            scanDirectory(URL(fileURLWithPath: dir), depth: 1, fm: fm, seen: &seen, into: &results)
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func scanDirectory(
        _ url: URL,
        depth: Int,
        fm: FileManager,
        seen: inout Set<String>,
        into results: inout [InstalledApp]
    ) {
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            if entry.pathExtension == "app" {
                guard let bundle = Bundle(url: entry), let bundleID = bundle.bundleIdentifier else {
                    continue
                }
                guard seen.insert(bundleID).inserted else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? entry.deletingPathExtension().lastPathComponent
                results.append(InstalledApp(bundleID: bundleID, name: name, url: entry))
            } else if depth > 0,
                      (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                scanDirectory(entry, depth: depth - 1, fm: fm, seen: &seen, into: &results)
            }
        }
    }
}
