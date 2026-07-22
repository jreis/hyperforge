// SnippetStore.swift
// Text expansions (hotstrings) — AHK :*: style, fully local.

import Combine
import Foundation

struct TextSnippet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Trigger typed by the user, e.g. ",sig" or "@@"
    var trigger: String
    /// Replacement text (supports \n)
    var expansion: String
    var isEnabled: Bool = true
    var note: String = ""
}

@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published var snippets: [TextSnippet] = []
    @Published var isEnabled = true

    private let fileURL: URL
    /// Ring buffer of recent characters for trigger matching.
    private var buffer = ""
    private let maxBuffer = 40

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
    }

    static let defaults: [TextSnippet] = [
        TextSnippet(trigger: ",sig", expansion: "Thanks,\nYour Name", note: "Email sign-off — edit me"),
        TextSnippet(trigger: "@@", expansion: "you@example.com", note: "Email — edit me"),
        TextSnippet(trigger: ",date", expansion: "{{date}}", note: "ISO date"),
        TextSnippet(trigger: ",v", expansion: "{{clipboard}}", note: "Type clipboard"),
        TextSnippet(trigger: ",host", expansion: "{{hostname}}", note: "Machine name"),
    ]

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

    /// Feed a typed character (from the event tap). Returns true if a snippet expanded
    /// (caller should swallow the triggering key).
    func handleTypedKey(character: String, keyCode: CGKeyCode) -> Bool {
        guard isEnabled else { return false }
        // Skip when Hyper/Vim modifiers are active
        if HyperKeyEngine.shared.hyperKeyActive { return false }
        if VimNavigation.shared.isActive { return false }

        // Backspace
        if keyCode == KeyCode.delete {
            if !buffer.isEmpty { buffer.removeLast() }
            return false
        }

        guard character.count == 1, let ch = character.first, ch.isASCII else {
            // Reset on weird keys / non-printables handled elsewhere
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

        // Longest trigger wins
        let enabled = snippets.filter(\.isEnabled).sorted { $0.trigger.count > $1.trigger.count }
        for snip in enabled {
            guard !snip.trigger.isEmpty, buffer.hasSuffix(snip.trigger) else { continue }
            expand(snip)
            buffer = ""
            return true
        }
        return false
    }

    func resetBuffer() {
        buffer = ""
    }

    private func expand(_ snip: TextSnippet) {
        // The last trigger character is swallowed by the event tap and never typed.
        // Delete only the characters already present in the focused field.
        let deleteCount = max(0, snip.trigger.count - 1)
        for _ in 0..<deleteCount {
            EventSynthesizer.postKey(KeyCode.delete)
            usleep(2_000)
        }
        let text = resolve(snip.expansion)
        EventSynthesizer.typeString(text)
        Banner.show("Snippet: \(snip.trigger)")
        HyperLog.event("Snippet expanded \(snip.trigger)")
    }

    private func resolve(_ template: String) -> String {
        var out = template.replacingOccurrences(of: "\\n", with: "\n")
        if out.contains("{{date}}") {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            out = out.replacingOccurrences(of: "{{date}}", with: f.string(from: Date()))
        }
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
}

import CoreGraphics
import AppKit
