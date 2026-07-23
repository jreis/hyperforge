// SnippetStore.swift
// Text expansions (hotstrings) — AHK :*: style, fully local.
// UI store is @MainActor; matching for the CGEvent tap is lock-based (no main hop).

import AppKit
import Combine
import CoreGraphics
import Foundation

struct TextSnippet: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    /// Trigger typed by the user, e.g. ",sig" or "@@"
    var trigger: String
    /// Replacement text (supports \n)
    var expansion: String
    var isEnabled: Bool = true
    var note: String = ""
}

/// Shared date formatting for `{{date}}` tokens (engine + settings UI).
enum SnippetDateFormat {
    static let defaultsKey = "hf.snippetDateFormat"
    static let fallback = "yyyy-MM-dd"

    /// Common presets shown in the Snippets UI (labels include a live sample).
    static var presets: [(id: String, label: String, format: String)] {
        let named: [(String, String, String)] = [
            ("iso", "ISO", "yyyy-MM-dd"),
            ("us", "US", "MM/dd/yyyy"),
            ("eu", "EU", "dd/MM/yyyy"),
            ("long", "Long", "MMM d, yyyy"),
            ("full", "Full", "EEEE, MMMM d, yyyy"),
            ("iso-time", "ISO + time", "yyyy-MM-dd HH:mm"),
            ("time", "Time", "HH:mm"),
        ]
        var rows = named.map { id, name, format in
            (id, "\(name) · \(formatDate(format: format))", format)
        }
        rows.append(("custom", "Custom…", ""))
        return rows
    }

    /// Current global format (safe from any thread — UserDefaults).
    nonisolated static var current: String {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? fallback : raw
    }

    nonisolated static func setCurrent(_ format: String) {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? fallback : trimmed, forKey: defaultsKey)
    }

    nonisolated static func formatDate(_ date: Date = Date(), format: String? = nil) -> String {
        let pattern = (format?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// Preview for the settings UI (uses system locale for friendlier sample when wanted —
    /// formatting itself stays POSIX so patterns are predictable).
    @MainActor
    static func preview(format: String, date: Date = Date()) -> String {
        formatDate(date, format: format)
    }
}

/// Lock-based matcher used by the event tap — never waits on MainActor.
final class SnippetEngine: @unchecked Sendable {
    static let shared = SnippetEngine()

    private let lock = NSLock()
    private var buffer = ""
    private let maxBuffer = 40
    private var isEnabled = true
    private var didLoadFromDisk = false
    /// Longest trigger first.
    private var triggers: [(trigger: String, expansion: String)] = []

    private init() {
        // Load immediately so hotstrings work before any SwiftUI panel is opened.
        loadFromDiskIfNeeded()
    }

    func update(snippets: [TextSnippet], enabled: Bool) {
        let sorted = snippets
            .filter(\.isEnabled)
            .filter { !$0.trigger.isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
            .map { ($0.trigger, $0.expansion) }
        lock.lock()
        triggers = sorted
        isEnabled = enabled
        didLoadFromDisk = true
        lock.unlock()
    }

    func resetBuffer() {
        lock.lock()
        buffer = ""
        lock.unlock()
    }

    /// Disk load without MainActor — used at engine init and as a tap-path safety net.
    private func loadFromDiskIfNeeded() {
        lock.lock()
        if didLoadFromDisk {
            lock.unlock()
            return
        }
        lock.unlock()

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        let fileURL = dir.appendingPathComponent("snippets.json")
        var loaded: [TextSnippet] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TextSnippet].self, from: data)
        {
            loaded = decoded
        }
        if loaded.isEmpty {
            loaded = SnippetStore.defaults
        }
        update(snippets: loaded, enabled: true)
    }

    /// Called from the CGEvent tap. Must stay fast and never block on main.
    func handleTypedKey(
        character: String,
        keyCode: CGKeyCode,
        hyperActive: Bool,
        vimActive: Bool
    ) -> Bool {
        if hyperActive || vimActive { return false }

        // Safety net if bootstrap never touched SnippetStore.
        loadFromDiskIfNeeded()

        lock.lock()
        defer { lock.unlock() }

        guard isEnabled else { return false }

        if keyCode == KeyCode.delete {
            if !buffer.isEmpty { buffer.removeLast() }
            return false
        }

        guard character.count == 1, let ch = character.first, ch.isASCII else {
            if keyCode == KeyCode.return || keyCode == KeyCode.tab || keyCode == KeyCode.escape {
                buffer = ""
            }
            return false
        }

        if ch.isNewline || ch == "\t" {
            buffer = ""
            return false
        }

        buffer.append(ch)
        if buffer.count > maxBuffer {
            buffer = String(buffer.suffix(maxBuffer))
        }

        for item in triggers {
            guard buffer.hasSuffix(item.trigger) else { continue }
            let expansion = item.expansion
            let trigger = item.trigger
            buffer = ""
            // Expand outside the lock (may type keys).
            lock.unlock()
            Self.expand(trigger: trigger, expansion: expansion)
            lock.lock()
            return true
        }
        return false
    }

    private static func expand(trigger: String, expansion: String) {
        // Last trigger char is swallowed by the tap; delete the rest already typed.
        let deleteCount = max(0, trigger.count - 1)
        for _ in 0..<deleteCount {
            EventSynthesizer.postKey(KeyCode.delete)
        }
        EventSynthesizer.typeString(resolve(expansion))
        Banner.show(
            "Snippet",
            subtitle: trigger,
            style: .success,
            symbol: "text.badge.plus"
        )
        HyperLog.event("Snippet expanded \(trigger)")
    }

    private static func resolve(_ template: String) -> String {
        // Support both real newlines (from the editor) and typed "\n" / "\t" escapes.
        var out = template
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\r", with: "\n")
        out = resolveDateTokens(in: out)
        if out.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            out = out.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }
        if out.contains("{{hostname}}") {
            out = out.replacingOccurrences(
                of: "{{hostname}}",
                with: ProcessInfo.processInfo.hostName
            )
        }
        return out
    }

    /// `{{date}}` uses the global format; `{{date:MM/dd/yyyy}}` overrides per token.
    private static func resolveDateTokens(in template: String) -> String {
        guard template.contains("{{date") else { return template }
        guard let re = try? NSRegularExpression(
            pattern: #"\{\{date(?::([^}]+))?\}\}"#,
            options: []
        ) else {
            return template.replacingOccurrences(
                of: "{{date}}",
                with: SnippetDateFormat.formatDate()
            )
        }
        let ns = template as NSString
        let matches = re.matches(in: template, options: [], range: NSRange(location: 0, length: ns.length))
        var out = template
        // Replace from the end so ranges stay valid.
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: out) else { continue }
            let format: String?
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound,
               let fmtRange = Range(match.range(at: 1), in: out)
            {
                format = String(out[fmtRange])
            } else {
                format = nil
            }
            out.replaceSubrange(fullRange, with: SnippetDateFormat.formatDate(format: format))
        }
        return out
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published var snippets: [TextSnippet] = [] {
        didSet { syncEngine() }
    }
    @Published var isEnabled = true {
        didSet { syncEngine() }
    }
    /// Unicode date pattern for bare `{{date}}` tokens.
    @Published var dateFormat: String = SnippetDateFormat.current {
        didSet {
            let trimmed = dateFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.isEmpty ? SnippetDateFormat.fallback : trimmed
            if value != dateFormat {
                dateFormat = value
                return
            }
            SnippetDateFormat.setCurrent(value)
        }
    }

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snippets.json")
        load()
        if snippets.isEmpty {
            snippets = Self.defaults
            persist()
        }
        syncEngine()
    }

    /// Immutable seed list — safe from any isolation (SnippetEngine loads off MainActor).
    nonisolated static let defaults: [TextSnippet] = [
        TextSnippet(trigger: ",sig", expansion: "Thanks,\nYour Name", note: "Email sign-off — edit me"),
        TextSnippet(trigger: "@@", expansion: "you@example.com", note: "Email — edit me"),
        TextSnippet(trigger: ",date", expansion: "{{date}}", note: "Today’s date"),
        TextSnippet(trigger: ",v", expansion: "{{clipboard}}", note: "Type clipboard"),
        TextSnippet(trigger: ",host", expansion: "{{hostname}}", note: "Machine name"),
    ]

    private func syncEngine() {
        SnippetEngine.shared.update(snippets: snippets, enabled: isEnabled)
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TextSnippet].self, from: data)
        {
            snippets = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ s: TextSnippet) {
        snippets.append(s)
        persist()
    }

    func update(_ s: TextSnippet) {
        if let i = snippets.firstIndex(where: { $0.id == s.id }) {
            snippets[i] = s
            persist()
        }
    }

    func delete(_ s: TextSnippet) {
        snippets.removeAll { $0.id == s.id }
        persist()
    }

    func resetBuffer() {
        SnippetEngine.shared.resetBuffer()
    }

    /// Full replace used by config import.
    func replaceAll(_ list: [TextSnippet]) {
        snippets = list
        if snippets.isEmpty {
            snippets = Self.defaults
        }
        persist()
        syncEngine()
    }
}
