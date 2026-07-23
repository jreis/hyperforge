// AXRecipeService.swift
// UIA-inspired multi-step Accessibility recipes — local playbooks.

import AppKit
import ApplicationServices
import Combine
import Foundation

struct AXRecipeStep: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    enum Kind: String, Codable, CaseIterable {
        case clickNamed
        case pressKey
        case pause
        case typeText
        case pasteClipboard
    }

    var kind: Kind
    /// Button/link title, key name, seconds, or text depending on kind.
    var value: String
}

struct AXRecipe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "wand.and.stars"
    /// Empty = any app. Otherwise bundle ID must match frontmost.
    var bundleID: String = ""
    var steps: [AXRecipeStep]
    var isEnabled: Bool = true
}

@MainActor
final class AXRecipeStore: ObservableObject {
    static let shared = AXRecipeStore()

    @Published var recipes: [AXRecipe] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("ax-recipes.json")
        load()
        if recipes.isEmpty {
            recipes = Self.builtIns
            persist()
        }
    }

    static let builtIns: [AXRecipe] = [
        AXRecipe(
            name: "Click OK / Allow",
            symbol: "checkmark.circle",
            steps: [
                AXRecipeStep(kind: .clickNamed, value: "OK"),
            ]
        ),
        AXRecipe(
            name: "Click Allow",
            symbol: "hand.raised",
            steps: [
                AXRecipeStep(kind: .clickNamed, value: "Allow"),
            ]
        ),
        AXRecipe(
            name: "Save (⌘S)",
            symbol: "square.and.arrow.down",
            steps: [
                AXRecipeStep(kind: .pressKey, value: "cmd+s"),
            ]
        ),
        AXRecipe(
            name: "New Mail + Paste",
            symbol: "envelope",
            bundleID: "com.apple.mail",
            steps: [
                AXRecipeStep(kind: .pressKey, value: "cmd+n"),
                AXRecipeStep(kind: .pause, value: "0.4"),
                AXRecipeStep(kind: .pasteClipboard, value: ""),
            ]
        ),
        AXRecipe(
            name: "Focus Search Field",
            symbol: "magnifyingglass",
            steps: [
                AXRecipeStep(kind: .clickNamed, value: "Search"),
            ]
        ),
    ]

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([AXRecipe].self, from: data)
        {
            recipes = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(recipes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ r: AXRecipe) {
        recipes.append(r)
        persist()
    }

    func update(_ r: AXRecipe) {
        if let i = recipes.firstIndex(where: { $0.id == r.id }) {
            recipes[i] = r
            persist()
        }
    }

    func delete(_ r: AXRecipe) {
        recipes.removeAll { $0.id == r.id }
        persist()
    }

    func run(_ recipe: AXRecipe) {
        guard recipe.isEnabled else {
            Banner.show(
                "Recipe disabled",
                subtitle: recipe.name,
                style: .warning,
                symbol: "wand.and.stars"
            )
            return
        }
        if !recipe.bundleID.isEmpty {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if front != recipe.bundleID {
                Banner.show(
                    "Wrong app",
                    subtitle: "Need \(recipe.bundleID)",
                    style: .warning,
                    symbol: "app.badge.checkmark"
                )
                return
            }
        }
        Banner.show(
            "Running recipe",
            subtitle: recipe.name,
            style: .success,
            symbol: recipe.symbol.isEmpty ? "wand.and.stars" : recipe.symbol
        )
        Task {
            for step in recipe.steps {
                await Self.perform(step)
            }
        }
    }

    func runByName(_ name: String) {
        if let r = recipes.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            run(r)
        } else {
            Banner.show(
                "No recipe found",
                subtitle: "“\(name)”",
                style: .warning,
                symbol: "wand.and.stars"
            )
        }
    }

    /// Popup picker for recipes.
    func showMenu() {
        let menu = NSMenu(title: "AX Recipes")
        let applicable = recipes.filter(\.isEnabled)
        if applicable.isEmpty {
            menu.addItem(withTitle: "No recipes", action: nil, keyEquivalent: "")
        }
        for r in applicable {
            let item = NSMenuItem(
                title: r.name,
                action: #selector(RecipeMenuTarget.runRecipe(_:)),
                keyEquivalent: ""
            )
            item.representedObject = r.id.uuidString
            item.target = RecipeMenuTarget.shared
            item.image = NSImage(systemSymbolName: r.symbol, accessibilityDescription: r.name)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func perform(_ step: AXRecipeStep) async {
        switch step.kind {
        case .pause:
            let secs = Double(step.value) ?? 0.3
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
        case .pressKey:
            await MainActor.run { pressKeyChord(step.value) }
        case .typeText:
            await MainActor.run { EventSynthesizer.typeString(step.value) }
        case .pasteClipboard:
            await MainActor.run { EventSynthesizer.postCommandKey(KeyCode.v) }
        case .clickNamed:
            await MainActor.run {
                if !clickElement(named: step.value) {
                    Banner.show(
                        "Element not found",
                        subtitle: step.value,
                        style: .warning,
                        symbol: "wand.and.stars"
                    )
                }
            }
        }
    }

    private static func pressKeyChord(_ spec: String) {
        let lower = spec.lowercased().replacingOccurrences(of: " ", with: "")
        var flags: CGEventFlags = []
        var key = lower
        if key.contains("cmd") || key.contains("command") {
            flags.insert(.maskCommand)
            key = key.replacingOccurrences(of: "cmd+", with: "")
                .replacingOccurrences(of: "command+", with: "")
        }
        if key.contains("shift") {
            flags.insert(.maskShift)
            key = key.replacingOccurrences(of: "shift+", with: "")
        }
        if key.contains("alt") || key.contains("option") {
            flags.insert(.maskAlternate)
            key = key.replacingOccurrences(of: "alt+", with: "")
                .replacingOccurrences(of: "option+", with: "")
        }
        if key.contains("ctrl") || key.contains("control") {
            flags.insert(.maskControl)
            key = key.replacingOccurrences(of: "ctrl+", with: "")
                .replacingOccurrences(of: "control+", with: "")
        }
        let code: CGKeyCode? = {
            switch key {
            case "s": return KeyCode.s
            case "n": return KeyCode.n
            case "w": return KeyCode.w
            case "v": return KeyCode.v
            case "c": return KeyCode.c
            case "a": return KeyCode.a
            case "z": return KeyCode.z
            case "return", "enter": return KeyCode.return
            case "escape", "esc": return KeyCode.escape
            case "tab": return KeyCode.tab
            case "space": return KeyCode.space
            default: return nil
            }
        }()
        guard let code else { return }
        if flags.contains(.maskCommand) {
            EventSynthesizer.postCommandKey(code)
        } else {
            EventSynthesizer.postKey(code, flags: flags)
        }
    }

    /// Walk AX tree for a pressable element whose title/description matches.
    @discardableResult
    static func clickElement(named name: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var found: AXUIElement?
        var visited = 0
        find(axApp, name: name, into: &found, visited: &visited, limit: 600)
        guard let el = found else { return false }
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        if err == .success { return true }
        // Fallback: click center
        if let frame = frame(of: el), let screen = NSScreen.main {
            let point = CGPoint(x: frame.midX, y: screen.frame.height - frame.midY)
            if let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
                let up = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: point,
                    mouseButton: .left
                )
            {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                return true
            }
        }
        return false
    }

    private static func find(
        _ el: AXUIElement,
        name: String,
        into found: inout AXUIElement?,
        visited: inout Int,
        limit: Int
    ) {
        guard found == nil, visited < limit else { return }
        visited += 1

        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
        var descRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        var valueRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
        let labels = [titleRef as? String, descRef as? String, valueRef as? String]
            .compactMap { $0 }
        if labels.contains(where: { $0.localizedCaseInsensitiveContains(name) }) {
            var actionsRef: CFArray?
            AXUIElementCopyActionNames(el, &actionsRef)
            let actions = (actionsRef as? [String]) ?? []
            if actions.contains(kAXPressAction as String) || !labels.isEmpty {
                found = el
                return
            }
        }

        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
            == .success,
            let children = childrenRef as? [AXUIElement]
        {
            for child in children {
                find(child, name: name, into: &found, visited: &visited, limit: limit)
                if found != nil { return }
            }
        }
    }

    private static func frame(of el: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }
}

@MainActor
final class RecipeMenuTarget: NSObject {
    static let shared = RecipeMenuTarget()

    @objc func runRecipe(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let recipe = AXRecipeStore.shared.recipes.first(where: { $0.id == id })
        else { return }
        AXRecipeStore.shared.run(recipe)
    }
}

import CoreGraphics
