// ScriptStore.swift
// User-authored JavaScript automations — the general-purpose escape hatch alongside
// the fixed-step AX Recipes (AXRecipeService.swift). Scripts call a small `HF` bridge
// exposed to the JSContext for window/clipboard/notification/app side effects.

import AppKit
import Combine
import Foundation
import JavaScriptCore

struct JSScript: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "curlybraces"
    var source: String
    /// Empty = any app. Otherwise bundle ID must match frontmost (same convention as AXRecipe).
    var bundleID: String = ""
    var isEnabled: Bool = true
    /// Message from the most recent run's uncaught exception, if any (shown in Settings).
    var lastError: String?
}

@MainActor
final class ScriptStore: ObservableObject {
    static let shared = ScriptStore()

    @Published var scripts: [JSScript] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("scripts.json")
        load()
        if scripts.isEmpty {
            scripts = Self.builtIns
            persist()
        }
    }

    static let builtIns: [JSScript] = [
        JSScript(
            name: "Say hello",
            symbol: "hand.wave",
            source: "HF.notify(\"Hello from HyperForge\");"
        ),
        JSScript(
            name: "Snap left & notify",
            symbol: "rectangle.lefthalf.filled",
            source: """
            HF.snap("left");
            HF.notify("Snapped left");
            """
        ),
        JSScript(
            name: "Uppercase clipboard",
            symbol: "textformat",
            source: """
            var text = HF.clipboardGet();
            if (text) {
                HF.clipboardSet(text.toUpperCase());
                HF.notify("Clipboard uppercased");
            } else {
                HF.notify("Clipboard is empty");
            }
            """
        ),
        JSScript(
            name: "New timestamped note",
            symbol: "note.text",
            source: """
            var stamp = new Date().toLocaleString();
            HF.launchApp("com.apple.Notes");
            HF.sleep(400);
            HF.pasteText("Note — " + stamp + "\\n");
            """
        ),
        JSScript(
            name: "Screenshot region to clipboard",
            symbol: "camera.viewfinder",
            source: """
            HF.pressKey("cmd+shift+4");
            HF.notify("Drag to capture — copied to clipboard");
            """
        ),
        JSScript(
            name: "Toggle Focus (Shortcut)",
            symbol: "moon.stars",
            source: """
            HF.runShortcut("Toggle Focus");
            HF.sleep(200);
            HF.notify("Focus toggled");
            """
        ),
    ]

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([JSScript].self, from: data)
        {
            scripts = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(scripts) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ s: JSScript) {
        scripts.append(s)
        persist()
    }

    func update(_ s: JSScript) {
        if let i = scripts.firstIndex(where: { $0.id == s.id }) {
            scripts[i] = s
            persist()
        }
    }

    func delete(_ s: JSScript) {
        scripts.removeAll { $0.id == s.id }
        persist()
    }

    /// Full replace used by config import.
    func replaceAll(_ list: [JSScript]) {
        scripts = list
        if scripts.isEmpty {
            scripts = Self.builtIns
        }
        persist()
    }

    func run(_ script: JSScript) {
        guard script.isEnabled else {
            Banner.show(
                "Script disabled",
                subtitle: script.name,
                style: .warning,
                symbol: "curlybraces"
            )
            return
        }
        if !script.bundleID.isEmpty {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if front != script.bundleID {
                Banner.show(
                    "Wrong app",
                    subtitle: "Need \(script.bundleID)",
                    style: .warning,
                    symbol: "app.badge.checkmark"
                )
                return
            }
        }
        Banner.show(
            "Running script",
            subtitle: script.name,
            style: .success,
            symbol: script.symbol.isEmpty ? "curlybraces" : script.symbol
        )
        let scriptID = script.id
        ScriptRunner.shared.run(script) { errorMessage in
            DispatchQueue.main.async {
                Task { @MainActor in
                    guard var latest = ScriptStore.shared.scripts.first(where: { $0.id == scriptID })
                    else { return }
                    latest.lastError = errorMessage
                    ScriptStore.shared.update(latest)
                }
            }
        }
    }

    func runByName(_ name: String) {
        if let s = scripts.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            run(s)
        } else {
            Banner.show(
                "No script found",
                subtitle: "“\(name)”",
                style: .warning,
                symbol: "curlybraces"
            )
        }
    }

    /// Popup picker for scripts — mirrors AXRecipeStore.showMenu().
    func showMenu() {
        let menu = NSMenu(title: "Scripts")
        let applicable = scripts.filter(\.isEnabled)
        if applicable.isEmpty {
            menu.addItem(withTitle: "No scripts", action: nil, keyEquivalent: "")
        }
        for s in applicable {
            let item = NSMenuItem(
                title: s.name,
                action: #selector(ScriptMenuTarget.runScript(_:)),
                keyEquivalent: ""
            )
            item.representedObject = s.id.uuidString
            item.target = ScriptMenuTarget.shared
            item.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: s.name)
            menu.addItem(item)
        }
        HyperKeyEngine.shared.beginMenuSession()
        defer { HyperKeyEngine.shared.endMenuSession() }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

@MainActor
final class ScriptMenuTarget: NSObject {
    static let shared = ScriptMenuTarget()

    @objc func runScript(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let script = ScriptStore.shared.scripts.first(where: { $0.id == id })
        else { return }
        ScriptStore.shared.run(script)
    }
}

/// Executes JS scripts off the main actor / tap thread so a slow or runaway script can
/// never stall the CGEvent tap (see `.tapDisabledByTimeout` handling in
/// HyperKeyEngine.swift) or the UI. `HFScriptBridge` methods hop back to MainActor for
/// the actual side effects and block this queue (never main) waiting on the result —
/// safe because this queue is guaranteed non-main.
///
/// `JSContextGroupSetExecutionTimeLimit` (the JavaScriptCore C API that can hard-abort a
/// runaway script) is not exposed to Swift on this SDK, so there is no forced interrupt
/// for an infinite loop — the dedicated background queue keeps a hung script from
/// affecting anything else, but that one queue stays blocked until the app restarts.
final class ScriptRunner: @unchecked Sendable {
    static let shared = ScriptRunner()

    private let queue = DispatchQueue(label: "app.hyperforge.scriptRunner")

    func run(_ script: JSScript, completion: (@Sendable (String?) -> Void)? = nil) {
        queue.async {
            let context = JSContext()
            let bridge = HFScriptBridge()
            context?.setObject(bridge, forKeyedSubscript: "HF" as NSString)

            var exceptionMessage: String?
            context?.exceptionHandler = { _, exception in
                exceptionMessage = exception?.toString() ?? "Unknown script error"
            }

            context?.evaluateScript(script.source)

            if let message = exceptionMessage {
                HyperLog.event("Script \(script.name) failed: \(message)")
                DispatchQueue.main.async {
                    Banner.show(
                        "Script error",
                        subtitle: message,
                        style: .warning,
                        symbol: "exclamationmark.triangle"
                    )
                }
            }
            completion?(exceptionMessage)
        }
    }
}

/// `HF` — the API surface exposed inside a script's `JSContext`. Every method hops to
/// MainActor for the real side effect and blocks the calling (background) queue for the
/// result via a semaphore, so scripts can call these synchronously in any order.
@objc protocol HFScriptBridgeExporting: JSExport {
    func snap(_ position: String) -> Bool
    func notify(_ message: String)
    func log(_ message: String)
    func clipboardGet() -> String?
    func clipboardSet(_ text: String)
    func pasteText(_ text: String)
    func pressKey(_ chord: String)
    func runShortcut(_ name: String)
    func launchApp(_ bundleID: String)
    func sleep(_ ms: Double)
}

@objc final class HFScriptBridge: NSObject, HFScriptBridgeExporting {
    /// Runs `work` on MainActor and blocks the calling (non-main) thread until it
    /// finishes. Never call this from main — it would deadlock.
    private func onMainSync<T: Sendable>(_ work: @escaping @MainActor () -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T!
        DispatchQueue.main.async {
            Task { @MainActor in
                result = work()
                semaphore.signal()
            }
        }
        semaphore.wait()
        return result
    }

    func snap(_ position: String) -> Bool {
        onMainSync {
            let wm = WindowManager.shared
            switch position {
            case "left": wm.snap(x: 0, y: 0, w: 0.5, h: 1)
            case "right": wm.snap(x: 0.5, y: 0, w: 0.5, h: 1)
            case "top": wm.snap(x: 0, y: 0, w: 1, h: 0.5)
            case "bottom": wm.snap(x: 0, y: 0.5, w: 1, h: 0.5)
            case "max": wm.snap(x: 0, y: 0, w: 1, h: 1)
            case "center": wm.centerKeepSize()
            case "centerNice": wm.centerNice()
            case "thirdLeft": wm.snapThird(column: 0)
            case "thirdCenter": wm.snapThird(column: 1)
            case "thirdRight": wm.snapThird(column: 2)
            case "twoThirdsLeft": wm.snapTwoThirds(leading: true)
            case "twoThirdsRight": wm.snapTwoThirds(leading: false)
            case "almostMax": wm.almostMaximize()
            default: return false
            }
            return true
        }
    }

    func notify(_ message: String) {
        onMainSync {
            Banner.show("Script", subtitle: message, style: .success, symbol: "curlybraces")
        }
    }

    func log(_ message: String) {
        HyperLog.event("Script log: \(message)")
    }

    func clipboardGet() -> String? {
        onMainSync {
            NSPasteboard.general.string(forType: .string)
        }
    }

    func clipboardSet(_ text: String) {
        onMainSync {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func pasteText(_ text: String) {
        onMainSync {
            EventSynthesizer.typeString(text)
        }
    }

    func pressKey(_ chord: String) {
        onMainSync {
            AXRecipeStore.pressKeyChord(chord)
        }
    }

    func runShortcut(_ name: String) {
        onMainSync {
            ShortcutsService.run(name: name)
        }
    }

    func launchApp(_ bundleID: String) {
        onMainSync {
            AppLauncher.shared.launchFocusOrMinimize(bundleID)
        }
    }

    func sleep(_ ms: Double) {
        // Blocks only this script's own background queue thread, never main.
        Thread.sleep(forTimeInterval: max(0, ms) / 1000)
    }
}
