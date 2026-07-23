// ConfigBackupService.swift
// Export / import a local HyperForge config pack (profiles, snippets, prefs, Space nav…).
// Fully offline JSON — never leaves the machine unless the user copies the file.

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Package schema

struct HyperForgeConfigPackage: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String?

    var profiles: ProfilesSlice?
    var snippets: [TextSnippet]?
    var appOverrides: [AppOverride]?
    var spaceNav: SpaceNavSlice?
    var prefs: PrefsSlice?
    var terminal: TerminalSlice?
    var ollama: OllamaSlice?
    var checklistVerified: [String]?

    struct ProfilesSlice: Codable {
        var profiles: [HyperProfile]
        var activeProfileID: UUID
        var autoTriggers: [AutoTrigger]
    }

    struct SpaceNavSlice: Codable {
        var enabled: Bool
        var holdMilliseconds: Int
        var blockedApps: [SpaceNavBlockedApp]
    }

    struct PrefsSlice: Codable {
        var launchEngineOnStart: Bool?
        var showDashboardOnStartup: Bool?
        var autoKeepAlive: Bool?
        var menuBarOnly: Bool?
        var snippetDateFormat: String?
    }

    struct TerminalSlice: Codable {
        var bundleID: String?
        var reuseMode: String?
    }

    struct OllamaSlice: Codable {
        var enabled: Bool?
        var model: String?
        var baseURL: String?
    }
}

@MainActor
enum ConfigBackupService {
    static let currentFormatVersion = 1

    // MARK: - Build package

    static func buildPackage() -> HyperForgeConfigPackage {
        let profiles = ProfileStore.shared
        let space = SpaceNavStore.shared
        let ollama = OllamaClient.shared
        let terminal = TerminalPreference.shared
        let defaults = UserDefaults.standard

        return HyperForgeConfigPackage(
            formatVersion: currentFormatVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                ?? "0.3.0",
            profiles: .init(
                profiles: profiles.profiles,
                activeProfileID: profiles.activeProfileID,
                autoTriggers: profiles.autoTriggers
            ),
            snippets: SnippetStore.shared.snippets,
            appOverrides: AppOverrideStore.shared.overrides,
            spaceNav: .init(
                enabled: space.isEnabled,
                holdMilliseconds: space.holdMilliseconds,
                blockedApps: space.blockedApps
            ),
            prefs: .init(
                launchEngineOnStart: defaults.object(forKey: "hf.launchEngineOnStart") as? Bool
                    ?? true,
                showDashboardOnStartup: defaults.object(forKey: "hf.showDashboardOnStartup") as? Bool
                    ?? true,
                autoKeepAlive: defaults.object(forKey: "hf.autoKeepAlive") as? Bool ?? false,
                menuBarOnly: defaults.object(forKey: "hf.menuBarOnly") as? Bool ?? true,
                snippetDateFormat: SnippetDateFormat.current
            ),
            terminal: .init(
                bundleID: terminal.bundleID,
                reuseMode: terminal.reuseMode.rawValue
            ),
            ollama: .init(
                enabled: ollama.enabled,
                model: ollama.model,
                baseURL: ollama.baseURLString
            ),
            checklistVerified: Array(BindingChecklistStore.shared.verifiedIDs).sorted()
        )
    }

    static func encodePackage(_ package: HyperForgeConfigPackage) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(package)
    }

    static func decodePackage(from data: Data) throws -> HyperForgeConfigPackage {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let package = try dec.decode(HyperForgeConfigPackage.self, from: data)
        guard package.formatVersion >= 1, package.formatVersion <= currentFormatVersion else {
            throw ConfigBackupError.unsupportedVersion(package.formatVersion)
        }
        return package
    }

    // MARK: - Apply

    /// Replace local config with the package (full restore).
    static func apply(_ package: HyperForgeConfigPackage) throws {
        if let slice = package.profiles, !slice.profiles.isEmpty {
            ProfileStore.shared.replaceAll(
                profiles: slice.profiles,
                activeProfileID: slice.activeProfileID,
                autoTriggers: slice.autoTriggers
            )
        }
        if let snippets = package.snippets {
            SnippetStore.shared.replaceAll(snippets)
        }
        if let overrides = package.appOverrides {
            AppOverrideStore.shared.replaceAll(overrides)
        }
        if let space = package.spaceNav {
            SpaceNavStore.shared.applyImport(
                enabled: space.enabled,
                holdMilliseconds: space.holdMilliseconds,
                blockedApps: space.blockedApps
            )
        }
        if let prefs = package.prefs {
            let d = UserDefaults.standard
            if let v = prefs.launchEngineOnStart { d.set(v, forKey: "hf.launchEngineOnStart") }
            if let v = prefs.showDashboardOnStartup { d.set(v, forKey: "hf.showDashboardOnStartup") }
            if let v = prefs.autoKeepAlive { d.set(v, forKey: "hf.autoKeepAlive") }
            if let v = prefs.menuBarOnly { d.set(v, forKey: "hf.menuBarOnly") }
            if let fmt = prefs.snippetDateFormat, !fmt.isEmpty {
                SnippetStore.shared.dateFormat = fmt
            }
            // Refresh AppState @AppStorage-backed fields via notification-friendly re-read
            AppState.shared.syncPrefsFromDefaults()
        }
        if let term = package.terminal {
            if let bid = term.bundleID, !bid.isEmpty {
                TerminalPreference.shared.bundleID = bid
            }
            if let raw = term.reuseMode, let mode = TerminalReuseMode(rawValue: raw) {
                TerminalPreference.shared.reuseMode = mode
            }
        }
        if let ai = package.ollama {
            if let v = ai.enabled { ollamaApply(enabled: v, model: ai.model, baseURL: ai.baseURL) }
            else { ollamaApply(enabled: nil, model: ai.model, baseURL: ai.baseURL) }
        }
        if let keys = package.checklistVerified {
            BindingChecklistStore.shared.replaceAll(Set(keys))
        }
    }

    private static func ollamaApply(enabled: Bool?, model: String?, baseURL: String?) {
        let o = OllamaClient.shared
        if let enabled { o.enabled = enabled }
        if let model, !model.isEmpty { o.model = model }
        if let baseURL, !baseURL.isEmpty { o.baseURLString = baseURL }
        o.persistSettings()
        o.refreshModelFit()
    }

    // MARK: - Panels

    @discardableResult
    static func exportWithSavePanel() -> URL? {
        let package = buildPackage()
        guard let data = try? encodePackage(package) else {
            Banner.show("Export failed", subtitle: "Could not encode config", style: .danger)
            return nil
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HyperForge-config.json"
        panel.title = "Export HyperForge config"
        panel.message = "Profiles, snippets, Space nav, overrides, and preferences (local only)."
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            Banner.show(
                "Config exported",
                subtitle: url.lastPathComponent,
                style: .success,
                symbol: "square.and.arrow.up"
            )
            HyperLog.event("Config exported → \(url.path)")
            return url
        } catch {
            Banner.show("Export failed", subtitle: error.localizedDescription, style: .danger)
            return nil
        }
    }

    @discardableResult
    static func importWithOpenPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import HyperForge config"
        panel.message = "Replaces profiles, snippets, overrides, Space nav, and matching prefs."

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return importFromURL(url)
    }

    @discardableResult
    static func importFromURL(_ url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let package = try decodePackage(from: data)
            try apply(package)
            Banner.show(
                "Config imported",
                subtitle: url.lastPathComponent,
                style: .success,
                symbol: "square.and.arrow.down"
            )
            HyperLog.event("Config imported ← \(url.path) v\(package.formatVersion)")
            return true
        } catch {
            Banner.show("Import failed", subtitle: error.localizedDescription, style: .danger)
            HyperLog.event("Config import failed: \(error)")
            return false
        }
    }
}

enum ConfigBackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Unsupported config format version \(v)"
        }
    }
}
