// WindowMemoryStore.swift
// Opt-in per-app window position memory. For apps you explicitly add, HyperForge
// remembers that app's main window frame whenever you switch away from it, and
// re-applies it the next time that app cold-launches — never fights a window you're
// actively using, since restore only fires on a genuine launch, not on every switch.

import AppKit
import Foundation

/// One app HyperForge should remember the window position for.
struct WindowMemoryApp: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String

    var displayTitle: String {
        appName.isEmpty ? bundleID : appName
    }
}

private struct RememberedFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}

@MainActor
final class WindowMemoryStore: ObservableObject {
    static let shared = WindowMemoryStore()

    @Published var rememberedApps: [WindowMemoryApp] = [] {
        didSet { persist() }
    }

    private var frames: [String: RememberedFrame] = [:]
    private let fileURL: URL
    private var started = false

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("window-memory.json")
        load()
    }

    // MARK: - Opt-in list

    func add(bundleID: String, appName: String) {
        let bid = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else { return }
        guard !rememberedApps.contains(where: { $0.bundleID == bid }) else { return }
        rememberedApps.append(WindowMemoryApp(bundleID: bid, appName: appName.isEmpty ? bid : appName))
    }

    func addFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier,
              bid != Bundle.main.bundleIdentifier
        else { return }
        add(bundleID: bid, appName: app.localizedName ?? bid)
    }

    func remove(_ app: WindowMemoryApp) {
        rememberedApps.removeAll { $0.id == app.id }
        frames.removeValue(forKey: app.bundleID)
        persist()
    }

    func isRemembered(bundleID: String) -> Bool {
        rememberedApps.contains { $0.bundleID == bundleID }
    }

    /// Full replace used by config import.
    func replaceAll(_ list: [WindowMemoryApp]) {
        rememberedApps = list
    }

    // MARK: - Watch app switches

    func start() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.captureFrame(from: note) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.scheduleRestore(from: note) }
        }
    }

    private func captureFrame(from note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bid = app.bundleIdentifier,
              isRemembered(bundleID: bid),
              let window = Self.mainWindow(for: app),
              let frame = WindowManager.shared.getFrame(window)
        else { return }
        frames[bid] = RememberedFrame(frame)
        persist()
    }

    private func scheduleRestore(from note: Notification, attempt: Int = 0) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bid = app.bundleIdentifier,
              isRemembered(bundleID: bid),
              let remembered = frames[bid]
        else { return }

        guard let window = Self.mainWindow(for: app) else {
            // New apps can take a moment to create their first window.
            guard attempt < 10 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.scheduleRestore(from: note, attempt: attempt + 1)
            }
            return
        }
        WindowManager.shared.setFrame(window, remembered.rect)
    }

    private static func mainWindow(for app: NSRunningApplication) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
            == .success,
            let window = windowRef as! AXUIElement?
        {
            return window
        }
        var windowsRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
                == .success,
            let windows = windowsRef as? [AXUIElement],
            let first = windows.first
        else { return nil }
        return first
    }

    // MARK: - Persistence

    private struct StorePayload: Codable {
        var rememberedApps: [WindowMemoryApp]
        var frames: [String: RememberedFrame]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StorePayload.self, from: data)
        else { return }
        rememberedApps = decoded.rememberedApps
        frames = decoded.frames
    }

    private func persist() {
        let payload = StorePayload(rememberedApps: rememberedApps, frames: frames)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
