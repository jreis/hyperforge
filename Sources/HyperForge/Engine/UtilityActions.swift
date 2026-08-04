// UtilityActions.swift
// Keep-alive, notes, clipboard helpers, pomodoro, network, mic, etc.
// System utilities: network, lock, clipboard helpers, notes.

import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

// MARK: - Keep Alive

@MainActor
final class KeepAliveService {
    static let shared = KeepAliveService()

    private(set) var isActive = false
    private var timer: Timer?
    var interval: TimeInterval = 45

    private init() {}

    func toggle() {
        if isActive {
            timer?.invalidate()
            timer = nil
            isActive = false
            Banner.show(
                "Idle lock armed",
                subtitle: "Keep-alive is off",
                style: .neutral,
                symbol: "lock.open"
            )
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                Task { @MainActor in
                    KeepAliveService.pulse()
                }
            }
            isActive = true
            Self.pulse()
            let mins = Int(interval) / 60
            let secs = Int(interval) % 60
            let every =
                mins > 0
                ? String(format: "Pulses every %d:%02d", mins, secs)
                : String(format: "Pulses every %ds", secs)
            Banner.show(
                "Keep-alive on",
                subtitle: every,
                style: .success,
                symbol: "bolt.heart.fill"
            )
        }
    }

    /// Nudge mouse 1px and assert user activity so idle timers (Teams etc.) reset.
    static func pulse() {
        guard let screen = NSScreen.main else { return }
        let p = NSEvent.mouseLocation
        let current = CGPoint(x: p.x, y: screen.frame.height - p.y)
        let nudgedX = current.x < screen.frame.width - 2 ? current.x + 1 : current.x - 1
        let nudged = CGPoint(x: nudgedX, y: current.y)

        if let ev = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: nudged,
            mouseButton: .left
        ) {
            ev.post(tap: .cghidEventTap)
        }
        usleep(20_000)
        if let ev = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: current,
            mouseButton: .left
        ) {
            ev.post(tap: .cghidEventTap)
        }

        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "HyperForge keep-alive" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }
}

// MARK: - Pomodoro

@MainActor
final class PomodoroService {
    static let shared = PomodoroService()

    private(set) var isRunning = false
    private var timer: Timer?
    private var secsLeft = 0
    private var isBreak = false
    var focusMinutes = 25
    var breakMinutes = 5

    private init() {}

    func toggle() {
        if isRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
            Banner.show("Pomodoro stopped")
        } else {
            isBreak = false
            secsLeft = focusMinutes * 60
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
            Banner.show("Pomodoro started (\(focusMinutes) min)")
        }
    }

    private func tick() {
        secsLeft -= 1
        if secsLeft <= 0 {
            timer?.invalidate()
            timer = nil
            isRunning = false
            Banner.show(isBreak ? "Break over! Time to focus 🍅" : "Pomodoro done! Take a break ☕")
            NSSound(named: "Glass")?.play()
        }
    }
}

// MARK: - Clipboard History

/// One clipboard-history entry. Persisted locally (Application Support) so
/// history — and pins — survive app restarts. Never leaves the machine.
struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var pinned: Bool = false
    var createdAt: Date = Date()
}

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    @Published private(set) var entries: [ClipboardEntry] = []
    /// Cap on *unpinned* entries — pinned entries are exempt from eviction.
    var maxItems = 20
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("clipboard-history.json")
        load()
    }

    /// Display order: pinned entries first, otherwise most-recent-first (stable sort
    /// keeps relative order within each group).
    var pinnedFirst: [ClipboardEntry] {
        entries.sorted { $0.pinned && !$1.pinned }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Snapshot current plain-text pasteboard into history if it changed.
    /// Called from the Clipboard panel / Hyper history menu — not a background timer.
    @discardableResult
    func poll() -> Bool {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return false }
        lastChangeCount = current

        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else {
            return false
        }
        record(content)
        return true
    }

    /// Insert text at the front of history (deduped, pin preserved). Used when
    /// HyperForge writes the pasteboard.
    func record(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Cap stored length so the menu stays snappy
        let stored = content.count > 8_000 ? String(content.prefix(8_000)) : content
        let wasPinned = entries.first { $0.text == stored }?.pinned ?? false
        entries.removeAll { $0.text == stored }
        entries.insert(ClipboardEntry(text: stored, pinned: wasPinned), at: 0)
        trimUnpinned()
        persist()
    }

    /// Drop oldest unpinned entries beyond `maxItems`; pinned entries never evict.
    private func trimUnpinned() {
        var unpinnedSeen = 0
        entries = entries.filter { entry in
            if entry.pinned { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= maxItems
        }
    }

    func togglePin(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].pinned.toggle()
        trimUnpinned()
        persist()
    }

    /// Clears unpinned history; pinned entries are kept.
    func clearHistory() {
        entries.removeAll { !$0.pinned }
        persist()
    }

    func pasteAsPlainText() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            Banner.show("Clipboard empty or no text")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        record(text)
        EventSynthesizer.postKey(KeyCode.v, flags: .maskCommand)
    }

    /// Paste a history entry (set pasteboard + ⌘V).
    func paste(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        lastChangeCount = pb.changeCount
        // Move to front (keeps pin state).
        record(entry.text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            EventSynthesizer.postCommandKey(KeyCode.v)
            Banner.show(
                "Pasted history",
                style: .success,
                symbol: "list.clipboard"
            )
        }
    }

    /// Hyper + V — local history (non-modal panel).
    func showHistoryMenu() {
        ClipboardHistoryPanel.show()
    }
}

// MARK: - Quick Notes

enum QuickNote {
    static var notesDirectory: String {
        NSHomeDirectory() + "/notes"
    }

    static func todayPath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return notesDirectory + "/\(formatter.string(from: Date())).md"
    }

    static func capture() {
        try? FileManager.default.createDirectory(
            atPath: notesDirectory,
            withIntermediateDirectories: true
        )
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let isoDate = formatter.string(from: Date())
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: Date())
        let notePath = notesDirectory + "/\(isoDate).md"

        let script = """
            set result to display dialog "\(isoDate) — what's on your mind?" default answer "" buttons {"Cancel", "Save"} default button "Save"
            if button returned of result is "Save" then
                return text returned of result
            end if
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return }

        let line = "\n- \(timeStr): \(text)"
        if let handle = FileHandle(forWritingAtPath: notePath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: notePath, contents: line.data(using: .utf8))
        }
        openInTerminalEditor(notePath)
        _ = dateStr
    }

    static func openToday() {
        let path = todayPath()
        try? FileManager.default.createDirectory(
            atPath: notesDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path, contents: nil)
        openInTerminalEditor(path)
    }

    /// Open a file in nvim via the user's preferred terminal.
    static func openInTerminalEditor(_ filePath: String) {
        Task { @MainActor in
            let escaped = filePath.replacingOccurrences(of: "\"", with: "\\\"")
            TerminalPreference.shared.runCommand("nvim \"\(escaped)\"")
        }
    }

    /// Back-compat alias.
    static func openInITermNvim(_ filePath: String) {
        openInTerminalEditor(filePath)
    }
}

// MARK: - System helpers

enum SystemActions {
    /// Lock the session (login screen). Never use `pmset displaysleepnow` — that only
    /// blanks the panel (looks like a black screen) and often fires by accident when
    /// Karabiner’s Caps-alone Escape collides with Hyper.
    static func lockScreen() {
        // Preferred: CGSession -suspend (same as menu bar lock).
        let cgSession = URL(
            fileURLWithPath:
                "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        )
        if FileManager.default.isExecutableFile(atPath: cgSession.path) {
            let task = Process()
            task.executableURL = cgSession
            task.arguments = ["-suspend"]
            do {
                try task.run()
                return
            } catch {
                HyperLog.event("CGSession -suspend failed: \(error.localizedDescription)")
            }
        }
        // Fallback: system shortcut ⌃⌘Q
        EventSynthesizer.postKey(KeyCode.q, flags: [.maskControl, .maskCommand])
    }

    static func typeDateISO() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        EventSynthesizer.typeString(formatter.string(from: Date()))
    }

    static func openClipboardURL() {
        guard let content = NSPasteboard.general.string(forType: .string) else {
            Task { @MainActor in Banner.show("No URL in clipboard") }
            return
        }
        let pattern = try? NSRegularExpression(pattern: "https?://[^\\s]+")
        let range = NSRange(content.startIndex..., in: content)
        if let match = pattern?.firstMatch(in: content, range: range),
           let swiftRange = Range(match.range, in: content),
           let url = URL(string: String(content[swiftRange]))
        {
            NSWorkspace.shared.open(url)
            return
        }
        Task { @MainActor in Banner.show("No URL found in clipboard") }
    }

    static func showNetworkInfo() {
        var lines: [String] = []

        let wifiTask = Process()
        wifiTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        wifiTask.arguments = ["-getairportnetwork", "en0"]
        let wifiPipe = Pipe()
        wifiTask.standardOutput = wifiPipe
        wifiTask.standardError = FileHandle.nullDevice
        try? wifiTask.run()
        wifiTask.waitUntilExit()
        if let wifiStr = String(data: wifiPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        {
            lines.append(
                "WiFi: \(wifiStr.replacingOccurrences(of: "Current Wi-Fi Network: ", with: ""))"
            )
        }

        let ipTask = Process()
        ipTask.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        ipTask.arguments = ["en0"]
        let ipPipe = Pipe()
        ipTask.standardOutput = ipPipe
        ipTask.standardError = FileHandle.nullDevice
        try? ipTask.run()
        ipTask.waitUntilExit()
        if let ipStr = String(data: ipPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            let pattern = try? NSRegularExpression(pattern: "inet (\\d+\\.\\d+\\.\\d+\\.\\d+)")
            let range = NSRange(ipStr.startIndex..., in: ipStr)
            if let match = pattern?.firstMatch(in: ipStr, range: range),
               let addrRange = Range(match.range(at: 1), in: ipStr)
            {
                lines.append("IP: \(String(ipStr[addrRange]))")
            }
        }

        lines.append("Host: \(ProcessInfo.processInfo.hostName)")
        Task { @MainActor in Banner.show(lines.joined(separator: " | ")) }
    }

    static func primaryIP() -> String? {
        let ipTask = Process()
        ipTask.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        ipTask.arguments = ["en0"]
        let ipPipe = Pipe()
        ipTask.standardOutput = ipPipe
        ipTask.standardError = FileHandle.nullDevice
        try? ipTask.run()
        ipTask.waitUntilExit()
        if let ipStr = String(data: ipPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            let pattern = try? NSRegularExpression(pattern: "inet (\\d+\\.\\d+\\.\\d+\\.\\d+)")
            let range = NSRange(ipStr.startIndex..., in: ipStr)
            if let match = pattern?.firstMatch(in: ipStr, range: range),
               let addrRange = Range(match.range(at: 1), in: ipStr)
            {
                return String(ipStr[addrRange])
            }
        }
        return nil
    }

    static func copyPrimaryIP() {
        guard let ip = primaryIP() else {
            Task { @MainActor in Banner.show("No IP on en0") }
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ip, forType: .string)
        Task { @MainActor in Banner.show("Copied \(ip)") }
    }

    static func copyHostname() {
        let host = ProcessInfo.processInfo.hostName
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(host, forType: .string)
        Task { @MainActor in Banner.show("Copied \(host)") }
    }

    /// Reverse DNS for clipboard IP (local dig/host).
    static func reverseDNSClipboard() {
        guard let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty
        else {
            Task { @MainActor in Banner.show("Clipboard empty") }
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/host")
        task.arguments = [clip]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "No result"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(out, forType: .string)
        Task { @MainActor in Banner.show(String(out.prefix(80))) }
    }

    static func toggleMic() {
        let getScript = "input volume of (get volume settings)"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", getScript]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        if let volStr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let vol = Int(volStr)
        {
            let newVol = vol > 0 ? 0 : 100
            let setTask = Process()
            setTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            setTask.arguments = ["-e", "set volume input volume \(newVol)"]
            try? setTask.run()
            Task { @MainActor in
                Banner.show(newVol == 0 ? "🎙 Mic MUTED" : "🎙 Mic LIVE")
            }
        }
    }

    static func googleSelection() {
        EventSynthesizer.postKey(KeyCode.c, flags: .maskCommand)
        usleep(150_000)
        guard let selected = NSPasteboard.general.string(forType: .string),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Task { @MainActor in Banner.show("Nothing selected") }
            return
        }
        let query = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func openClipboardInNvim() {
        guard let content = NSPasteboard.general.string(forType: .string) else {
            Task { @MainActor in Banner.show("Clipboard empty") }
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let tmpPath = NSTemporaryDirectory() + "clipboard-\(formatter.string(from: Date())).txt"
        try? content.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        QuickNote.openInITermNvim(tmpPath)
    }
}
