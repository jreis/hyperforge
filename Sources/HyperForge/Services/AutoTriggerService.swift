// AutoTriggerService.swift
// Watches Wi‑Fi, frontmost app, and time-of-day to auto-switch profiles.

import AppKit
import Foundation

@MainActor
final class AutoTriggerService: ObservableObject {
    static let shared = AutoTriggerService()

    @Published var isEnabled = true
    @Published private(set) var lastMatchDescription: String?
    @Published private(set) var currentSSID: String?
    @Published private(set) var frontmostBundleID: String?

    private var timer: Timer?
    private var lastAppliedProfileID: UUID?
    private var lastSSID: String?

    private init() {}

    func start() {
        guard timer == nil else { return }
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        // App activation is more immediate than polling alone.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate() {
        guard isEnabled else { return }
        let store = ProfileStore.shared
        let triggers = store.autoTriggers.filter(\.isEnabled)
        guard !triggers.isEmpty else { return }

        currentSSID = Self.fetchSSID()
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Priority: app > wifi > time (more specific first)
        let ordered = triggers.sorted { a, b in
            rank(a.kind) < rank(b.kind)
        }

        for trigger in ordered {
            if matches(trigger) {
                if store.activeProfileID != trigger.profileID {
                    if let profile = store.profiles.first(where: { $0.id == trigger.profileID }) {
                        store.select(profile)
                        lastAppliedProfileID = profile.id
                        lastMatchDescription =
                            "\(trigger.kind.title): \(trigger.value) → \(profile.name)"
                        Banner.show("Profile: \(profile.name)")
                        HyperLog.event("AutoTrigger \(lastMatchDescription ?? "")")
                    }
                } else {
                    lastMatchDescription =
                        "Holding \(store.activeProfile.name) via \(trigger.kind.title)"
                }
                return
            }
        }
    }

    private func rank(_ kind: AutoTrigger.Kind) -> Int {
        switch kind {
        case .appBundleID: return 0
        case .wifiSSID: return 1
        case .timeOfDay: return 2
        }
    }

    private func matches(_ trigger: AutoTrigger) -> Bool {
        switch trigger.kind {
        case .wifiSSID:
            guard let ssid = currentSSID else { return false }
            return ssid.caseInsensitiveCompare(trigger.value) == .orderedSame
        case .appBundleID:
            guard let bid = frontmostBundleID else { return false }
            let v = trigger.value
            if bid.caseInsensitiveCompare(v) == .orderedSame { return true }
            // Allow matching by app name fragment
            if let name = NSWorkspace.shared.frontmostApplication?.localizedName,
               name.localizedCaseInsensitiveContains(v)
            {
                return true
            }
            return bid.localizedCaseInsensitiveContains(v)
        case .timeOfDay:
            return Self.timeInRange(trigger.value)
        }
    }

    /// Parse "HH:mm-HH:mm" (supports overnight ranges).
    static func timeInRange(_ value: String) -> Bool {
        let parts = value.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = parseTime(parts[0]),
              let end = parseTime(parts[1])
        else { return false }

        let cal = Calendar.current
        let now = Date()
        let mins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if start <= end {
            return mins >= start && mins <= end
        } else {
            // Overnight e.g. 22:00-06:00
            return mins >= start || mins <= end
        }
    }

    private static func parseTime(_ s: String) -> Int? {
        let bits = s.split(separator: ":")
        guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        return h * 60 + m
    }

    /// Best-effort SSID via networksetup (no special entitlement).
    static func fetchSSID() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getairportnetwork", "en0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard
            let str = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if str.localizedCaseInsensitiveContains("not associated") { return nil }
        return str.replacingOccurrences(of: "Current Wi-Fi Network: ", with: "")
    }
}
