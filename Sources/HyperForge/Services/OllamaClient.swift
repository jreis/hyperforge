// OllamaClient.swift
// Local-first natural language → structured HyperForge intents via Ollama HTTP API.
// Never leaves localhost. Graceful fallback when Ollama is offline.

import Foundation

struct AIIntent: Equatable {
    enum Kind: String {
        case runAction
        case generateKarabiner
        case generateSwift
        case explain
        case unknown
    }

    var kind: Kind
    var actionID: String?
    var payload: String?
    var title: String
    var detail: String
}

@MainActor
final class OllamaClient: ObservableObject {
    static let shared = OllamaClient()

    @Published var isAvailable = false
    @Published var model: String = UserDefaults.standard.string(forKey: "hf.ollamaModel") ?? "llama3.2"
    @Published var baseURLString: String =
        UserDefaults.standard.string(forKey: "hf.ollamaURL") ?? "http://127.0.0.1:11434"
    @Published var lastError: String?
    @Published var isThinking = false
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "hf.ollamaEnabled") as? Bool ?? true

    private init() {}

    var baseURL: URL? { URL(string: baseURLString) }

    func persistSettings() {
        UserDefaults.standard.set(model, forKey: "hf.ollamaModel")
        UserDefaults.standard.set(baseURLString, forKey: "hf.ollamaURL")
        UserDefaults.standard.set(enabled, forKey: "hf.ollamaEnabled")
    }

    /// Lightweight health check against local Ollama.
    func ping() async {
        guard enabled, let base = baseURL else {
            isAvailable = false
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            isAvailable = (response as? HTTPURLResponse)?.statusCode == 200
            lastError = isAvailable ? nil : "Ollama responded with an error"
        } catch {
            isAvailable = false
            lastError = "Ollama offline — using offline router"
        }
    }

    /// Interpret a natural-language command into an AIIntent.
    func interpret(_ prompt: String) async -> AIIntent {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AIIntent(
                kind: .unknown,
                actionID: nil,
                payload: nil,
                title: "Empty command",
                detail: "Type what you want HyperForge to do."
            )
        }

        // Prefer offline structured router first (instant, private, reliable).
        if let offline = OfflineIntentRouter.route(trimmed) {
            // Still try Ollama for generative intents when online.
            if offline.kind == .generateKarabiner || offline.kind == .generateSwift,
               enabled, isAvailable
            {
                if let ai = await generateWithOllama(trimmed, hint: offline) {
                    return ai
                }
            }
            return offline
        }

        guard enabled else {
            return AIIntent(
                kind: .unknown,
                actionID: nil,
                payload: nil,
                title: "No match",
                detail: "Enable Ollama in Settings or try a known action name."
            )
        }

        await ping()
        guard isAvailable else {
            return AIIntent(
                kind: .unknown,
                actionID: nil,
                payload: nil,
                title: "Ollama offline",
                detail: lastError ?? "Start Ollama locally, or use offline phrases."
            )
        }

        if let ai = await generateWithOllama(trimmed, hint: nil) {
            return ai
        }

        return AIIntent(
            kind: .unknown,
            actionID: nil,
            payload: nil,
            title: "Could not parse",
            detail: lastError ?? "Try rephrasing."
        )
    }

    private func generateWithOllama(_ prompt: String, hint: AIIntent?) async -> AIIntent? {
        guard let base = baseURL else { return nil }
        isThinking = true
        defer { isThinking = false }

        let catalog = ActionCatalog.defaults.prefix(40).map {
            "\($0.id): \($0.title) (\($0.shortcutDisplay))"
        }.joined(separator: "\n")

        let system = """
        You are HyperForge, a local macOS automation assistant. Reply with ONLY compact JSON:
        {"kind":"runAction|generateKarabiner|generateSwift|explain","actionID":"optional catalog id","payload":"optional text","title":"short","detail":"one line"}
        Catalog actionIDs:
        \(catalog)
        Prefer runAction when the user wants to execute something.
        For Karabiner/Swift generation put code in payload.
        Never invent network calls. Local only.
        """

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": "json",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 45

        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "Ollama chat failed"
                return nil
            }
            guard
                let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                let message = root["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                lastError = "Unexpected Ollama response"
                return nil
            }
            return parseIntentJSON(content) ?? hint
        } catch {
            lastError = error.localizedDescription
            return hint
        }
    }

    private func parseIntentJSON(_ raw: String) -> AIIntent? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let kindRaw = (obj["kind"] as? String) ?? "unknown"
        let kind = AIIntent.Kind(rawValue: kindRaw) ?? .unknown
        return AIIntent(
            kind: kind,
            actionID: obj["actionID"] as? String,
            payload: obj["payload"] as? String,
            title: (obj["title"] as? String) ?? kindRaw,
            detail: (obj["detail"] as? String) ?? ""
        )
    }
}

// MARK: - Offline router (always works, no model required)

enum OfflineIntentRouter {
    static func route(_ q: String) -> AIIntent? {
        let lower = q.lowercased()

        // Generative
        if lower.contains("karabiner") || lower.contains("complex_modification") {
            let json = """
            {
              "description": "Caps Lock to F18 (Hyper trigger)",
              "manipulators": [{
                "type": "basic",
                "from": { "key_code": "caps_lock" },
                "to": [{ "key_code": "f18" }],
                "to_if_alone": [{ "key_code": "escape" }]
              }]
            }
            """
            return AIIntent(
                kind: .generateKarabiner,
                actionID: nil,
                payload: json,
                title: "Karabiner Caps→F18 rule",
                detail: "Copied-ready complex_modifications JSON"
            )
        }
        if lower.contains("swift") && (lower.contains("binding") || lower.contains("generate") || lower.contains("code")) {
            let sample = """
            // HyperForge custom action sketch
            case KeyCode.slash:
                LinkHintService.shared.toggle()
                return true
            """
            return AIIntent(
                kind: .generateSwift,
                actionID: nil,
                payload: sample,
                title: "Swift binding sketch",
                detail: "Engine switch-case stub for a new Hyper chord"
            )
        }

        // Natural phrases → actions
        let phrases: [(String, String, String)] = [
            ("half page", "vim-ctrl-d", "Half-page scroll down"),
            ("half-page", "vim-ctrl-d", "Half-page scroll down"),
            ("scroll down", "scroll-down", "Scroll down"),
            ("scroll up", "scroll-up", "Scroll up"),
            ("snap left", "win-left", "Snap left half"),
            ("left half", "win-left", "Snap left half"),
            ("snap right", "win-right", "Snap right half"),
            ("right half", "win-right", "Snap right half"),
            ("maximize", "win-max", "Maximize window"),
            ("fullscreen", "win-max", "Maximize window"),
            ("tile", "win-tile-all", "Tile all windows"),
            ("tile all", "win-tile-all", "Tile all windows"),
            ("mosaic", "win-tile-all", "Tile all windows"),
            ("terminal", "app-iterm", "New terminal window"),
            ("iterm", "app-iterm", "New terminal window"),
            ("ghostty", "app-iterm", "New terminal window"),
            ("beside", "win-right", "Snap right (place beside)"),
            ("lock", "sys-lock", "Lock screen"),
            ("keep alive", "prod-keepalive", "Toggle keep-alive"),
            ("keepalive", "prod-keepalive", "Toggle keep-alive"),
            ("plain text", "clip-plain", "Paste plain text"),
            ("clipboard image", "clip-image", "Show clipboard image"),
            ("link hint", "sys-link-hints", "Link hint mode"),
            ("hints", "sys-link-hints", "Link hint mode"),
            ("command bar", "sys-command-bar", "Open command bar"),
            ("cheat sheet", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("cheatsheet", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("keybinding", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("key bindings", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("what are the shortcuts", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("show bindings", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("help", "sys-cheatsheet", "Keybinding cheat sheet"),
            ("pomodoro", "prod-pomodoro", "Pomodoro timer"),
            ("note", "prod-note", "Quick note"),
        ]

        for (phrase, id, title) in phrases where lower.contains(phrase) {
            return AIIntent(
                kind: .runAction,
                actionID: id,
                payload: nil,
                title: title,
                detail: "Offline match · \(id)"
            )
        }

        // Fuzzy catalog title match
        for action in ActionCatalog.defaults {
            if lower.contains(action.title.lowercased())
                || action.id.split(separator: "-").contains(where: { lower.contains($0) })
            {
                return AIIntent(
                    kind: .runAction,
                    actionID: action.id,
                    payload: nil,
                    title: action.title,
                    detail: action.shortcutDisplay
                )
            }
        }

        if lower.hasPrefix("explain") || lower.contains("what does") || lower.contains("help") {
            return AIIntent(
                kind: .explain,
                actionID: nil,
                payload: """
                HyperForge: hold Caps (F18) + key for Hyper actions. \
                Right ⌘ for Vim nav. Hyper+Space opens this command bar. \
                Hyper+/ toggles link hints. Profiles switch action sets.
                """,
                title: "How HyperForge works",
                detail: "Local Hyper Key companion"
            )
        }

        return nil
    }
}
