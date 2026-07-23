// DemoExportService.swift
// Export portfolio-ready demo assets: binding catalog, profile summary, screenshots, README.

import AppKit
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class DemoExportService: ObservableObject {
    static let shared = DemoExportService()

    @Published private(set) var lastExportURL: URL?
    @Published private(set) var status: String = "Ready to export"

    private init() {}

    /// Writes a demo pack to ~/Desktop/HyperForge-Demo-<timestamp>/
    @discardableResult
    func exportPortfolioPack() -> URL? {
        status = "Exporting…"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let dir = desktop.appendingPathComponent("HyperForge-Demo-\(stamp)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            try writeBindingsMarkdown(to: dir.appendingPathComponent("BINDINGS.md"))
            try writeBindingsJSON(to: dir.appendingPathComponent("bindings.json"))
            try writeProfilesMarkdown(to: dir.appendingPathComponent("PROFILES.md"))
            try writeKarabiner(to: dir.appendingPathComponent("karabiner-caps-to-f18.json"))
            try writeFeatureREADME(to: dir.appendingPathComponent("README.md"))
            try writeArchitectureNotes(to: dir.appendingPathComponent("ARCHITECTURE.md"))

            lastExportURL = dir
            status = "Capturing screenshots…"
            let shotsDir = dir.appendingPathComponent("screenshots", isDirectory: true)
            Task { @MainActor in
                await self.captureWindowScreenshots(into: shotsDir)
                self.status = "Exported → \(dir.path)"
                Banner.show("Demo pack on Desktop")
                NSWorkspace.shared.open(dir)
            }
            return dir
        } catch {
            status = "Export failed: \(error.localizedDescription)"
            Banner.show("Export failed")
            return nil
        }
    }

    private func writeBindingsMarkdown(to url: URL) throws {
        var md = """
        # HyperForge Bindings

        Generated \(Date().formatted()) · local-first automation companion

        | Shortcut | Action | Category | Detail |
        |----------|--------|----------|--------|
        """
        for a in ActionCatalog.defaults {
            md +=
                "\n| `\(a.shortcutDisplay)` | **\(a.title)** | \(a.category.rawValue) | \(a.detail) |"
        }
        md += """


        ## Modes

        - **Hyper** — hold Caps Lock (F18 via Karabiner) + key
        - **Space nav** — hold Space + H/J/K/L (TouchCursor-style)
        - **Link hints** — Hyper + /
        - **Command bar** — Hyper + Space (local Ollama optional)

        """
        try md.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeBindingsJSON(to url: URL) throws {
        let payload = ActionCatalog.defaults.map {
            [
                "id": $0.id,
                "title": $0.title,
                "detail": $0.detail,
                "shortcut": $0.shortcutDisplay,
                "category": $0.category.rawValue,
                "mode": $0.mode.rawValue,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func writeProfilesMarkdown(to url: URL) throws {
        let store = ProfileStore.shared
        var md = "# HyperForge Profiles\n\n"
        for p in store.profiles {
            let count =
                p.enabledActionIDs.isEmpty
                ? ActionCatalog.defaults.count : p.enabledActionIDs.count
            let active = p.id == store.activeProfileID ? " **(active)**" : ""
            md += "## \(p.name)\(active)\n\n"
            md += "- Symbol: `\(p.symbol)`\n"
            md += "- Actions: \(count)\n"
            md += "- Notes: \(p.notes)\n"
            md += "- Layouts: \(p.layouts.count)\n\n"
        }
        if !store.autoTriggers.isEmpty {
            md += "## Auto-triggers\n\n"
            for t in store.autoTriggers {
                let name = store.profiles.first { $0.id == t.profileID }?.name ?? "?"
                md +=
                    "- \(t.kind.title): `\(t.value)` → **\(name)** \(t.isEnabled ? "" : "(disabled)")\n"
            }
        }
        try md.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeKarabiner(to url: URL) throws {
        let json = """
        {
          "title": "HyperForge — Caps Lock as Hyper",
          "rules": [
            {
              "description": "Caps Lock to F18 (Hyper trigger)",
              "manipulators": [
                {
                  "from": { "key_code": "caps_lock" },
                  "to": [{ "key_code": "f18" }],
                  "to_if_alone": [{ "key_code": "escape" }],
                  "type": "basic"
                }
              ]
            }
          ]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeFeatureREADME(to url: URL) throws {
        let text = """
        # HyperForge — Portfolio Demo Pack

        **HyperForge** is a local-first macOS automation companion for Hyper Key + Karabiner setups.
        Built for restricted environments where Hammerspoon and browser extensions are blocked.

        ## Highlights

        - **Hyper Key engine** — CGEvent tap, F18 or 4-mod Hyper, window snaps, app launchers, keep-alive
        - **Karabiner pack** — Caps→Hyper + F19 help / F20 dashboard bridges
        - **Doctor** — Accessibility + rule health check
        - **Space navigation** — system-wide h/j/k/l, words, pages (hold Space)
        - **Link hints** — Accessibility-based click targets (Vimium fallback)
        - **Local AI command bar** — offline router + optional Ollama on localhost
        - **Profiles & auto-triggers** — Wi‑Fi / app / time → profile switch
        - **Per-app overrides** — disable or remap bindings per bundle ID
        - **Workspaces** — save/restore window layouts
        - **Privacy** — local-first; no telemetry

        ## Contents

        | File | Description |
        |------|-------------|
        | `BINDINGS.md` | Full shortcut table |
        | `bindings.json` | Machine-readable catalog |
        | `PROFILES.md` | Profile snapshot |
        | `karabiner-caps-to-f18.json` | Production Caps→F18 rule |
        | `ARCHITECTURE.md` | Module overview |
        | `screenshots/` | Live window captures |

        ## Stack

        Swift · SwiftUI · AppKit · Accessibility · Karabiner-Elements · (optional) Ollama

        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeArchitectureNotes(to url: URL) throws {
        let text = """
        # Architecture

        ```
        App/            SwiftUI shell, AppState, menu bar
        Engine/         HyperKeyEngine (CGEvent tap), actions, vim, link hints, windows
        Models/         HyperAction catalog, Profile, AppOverride
        Services/       Ollama, AutoTrigger, Karabiner, DemoExport, AppOverrideStore
        Views/          Dashboard, Profiles, Triggers, Overrides, Settings, CommandBar
        ```

        ### Event path

        1. Karabiner maps Caps Lock → F18 (tap alone → Escape)
        2. `HyperKeyEngine` session tap sees F18 keyDown → hyper active
        3. Next keyDown while hyper active → `HyperKeyActions.handle`
        4. Profile + AppOverride filters apply; remaps win over defaults
        5. Actions use AX (windows) or CGEvent (keys/scroll)

        ### Design goals

        - Muscle memory from classic Hyper Key setups preserved
        - UI is a control plane; engine stays fast and local
        - Features are modular — enable without rewriting the tap

        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Own windows via AppKit (no Screen Recording). Desktop via ScreenCaptureKit when allowed.
    private func captureWindowScreenshots(into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var windowIndex = 0
        for window in NSApp.windows where window.isVisible && window.frame.width >= 200 {
            if let png = Self.pngData(from: window) {
                windowIndex += 1
                let file = dir.appendingPathComponent(String(format: "window-%02d.png", windowIndex))
                try? png.write(to: file)
            }
        }

        // Optional full-display context — may require Screen Recording permission.
        if let png = await Self.captureMainDisplayPNG() {
            try? png.write(to: dir.appendingPathComponent("desktop-context.png"))
        }
    }

    /// Capture an NSWindow we own without deprecated CGWindowList APIs.
    private static func pngData(from window: NSWindow) -> Data? {
        // Same-process contentView snapshot — no Screen Recording permission needed.
        guard let view = window.contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Main display screenshot via ScreenCaptureKit (macOS 14+). Fails soft without permission.
    private static func captureMainDisplayPNG() async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Retina-friendly: match pixel dimensions of the display.
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.captureResolution = .best

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .png, properties: [:])
        } catch {
            HyperLog.event("DemoExport desktop capture skipped: \(error.localizedDescription)")
            return nil
        }
    }
}
