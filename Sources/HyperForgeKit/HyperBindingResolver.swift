// HyperBindingResolver.swift
// Pure Hyper-key → action-id routing (no AppKit). Testable without Accessibility.

import Foundation

/// Result of resolving a Hyper chord to a catalog action.
public enum HyperBindingRoute: Equatable, Sendable {
    case action(String)
    case unhandled
}

/// Virtual key codes (match `KeyCode` in the app). Kept as raw UInt16 so Kit stays dependency-free.
public enum HyperKeyCode {
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let x: UInt16 = 0x07
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let b: UInt16 = 0x0B
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let y: UInt16 = 0x10
    public static let t: UInt16 = 0x11
    public static let one: UInt16 = 0x12
    public static let two: UInt16 = 0x13
    public static let three: UInt16 = 0x14
    public static let four: UInt16 = 0x15
    public static let six: UInt16 = 0x16
    public static let five: UInt16 = 0x17
    public static let nine: UInt16 = 0x19
    public static let seven: UInt16 = 0x1A
    public static let eight: UInt16 = 0x1C
    public static let zero: UInt16 = 0x1D
    // Numpad (ANSI) — full spatial window pad under Hyper
    public static let keypad0: UInt16 = 0x52
    public static let keypad1: UInt16 = 0x53
    public static let keypad2: UInt16 = 0x54
    public static let keypad3: UInt16 = 0x55
    public static let keypad4: UInt16 = 0x56
    public static let keypad5: UInt16 = 0x57
    public static let keypad6: UInt16 = 0x58
    public static let keypad7: UInt16 = 0x59
    public static let keypad8: UInt16 = 0x5B
    public static let keypad9: UInt16 = 0x5C
    public static let o: UInt16 = 0x1F
    public static let u: UInt16 = 0x20
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let semicolon: UInt16 = 0x29
    public static let comma: UInt16 = 0x2B
    public static let slash: UInt16 = 0x2C
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E
    public static let period: UInt16 = 0x2F
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let grave: UInt16 = 0x32
    /// Apostrophe / quote key — Run Shortcuts menu.
    public static let quote: UInt16 = 0x27
    public static let `return`: UInt16 = 0x24
    public static let escape: UInt16 = 0x35
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E
}

/// Spec for a Hyper chord that the resolver / smoke tests cover.
public struct HyperBindingSpec: Equatable, Sendable, Identifiable, Hashable {
    /// Unique across plain vs ⇧ vs numpad aliases that share an actionID.
    public var id: String { checklistKey }
    public var checklistKey: String {
        let base = requiresExtraShift ? "\(actionID)#shift" : actionID
        return "\(base)#k\(keyCode)"
    }

    public let actionID: String
    public let keyCode: UInt16
    /// When true, only matches with F18 + physical Shift (not 4-mod).
    public let requiresExtraShift: Bool
    public let title: String

    public init(actionID: String, keyCode: UInt16, requiresExtraShift: Bool = false, title: String) {
        self.actionID = actionID
        self.keyCode = keyCode
        self.requiresExtraShift = requiresExtraShift
        self.title = title
    }
}

/// Pure dispatcher mirror of `HyperKeyActions.handle` (decision only).
public enum HyperBindingResolver {
    /// All Hyper chords the engine is expected to handle (primary + shift variants).
    public static let specs: [HyperBindingSpec] = [
        // Window
        .init(actionID: "win-left", keyCode: HyperKeyCode.leftArrow, title: "Snap Left"),
        .init(actionID: "win-right", keyCode: HyperKeyCode.rightArrow, title: "Snap Right"),
        .init(actionID: "win-top", keyCode: HyperKeyCode.upArrow, title: "Snap Top"),
        .init(actionID: "win-bottom", keyCode: HyperKeyCode.downArrow, title: "Snap Bottom"),
        .init(actionID: "win-max", keyCode: HyperKeyCode.return, title: "Maximize"),
        .init(actionID: "win-tile-all", keyCode: HyperKeyCode.six, title: "Tile All (6)"),
        .init(
            actionID: "win-tile-all",
            keyCode: HyperKeyCode.return,
            requiresExtraShift: true,
            title: "Tile All (⇧Return)"
        ),
        .init(actionID: "win-center", keyCode: HyperKeyCode.c, title: "Center"),
        .init(actionID: "win-next-screen", keyCode: HyperKeyCode.m, title: "Next Display"),
        .init(actionID: "win-undo", keyCode: HyperKeyCode.z, title: "Undo Snap"),
        .init(actionID: "win-tl", keyCode: HyperKeyCode.seven, title: "Top-Left"),
        .init(actionID: "win-tr", keyCode: HyperKeyCode.eight, title: "Top-Right"),
        .init(actionID: "win-bl", keyCode: HyperKeyCode.nine, title: "Bottom-Left"),
        .init(actionID: "win-br", keyCode: HyperKeyCode.zero, title: "Bottom-Right"),
        // Numpad full pad — spatial window layout (Hyper held)
        //  7 TL   8 Top   9 TR
        //  4 Left 5 Max   6 Right
        //  1 BL   2 Bot   3 BR
        //  0 Center
        .init(actionID: "win-tl", keyCode: HyperKeyCode.keypad7, title: "Top-Left (Num 7)"),
        .init(actionID: "win-top", keyCode: HyperKeyCode.keypad8, title: "Top Half (Num 8)"),
        .init(actionID: "win-tr", keyCode: HyperKeyCode.keypad9, title: "Top-Right (Num 9)"),
        .init(actionID: "win-left", keyCode: HyperKeyCode.keypad4, title: "Left Half (Num 4)"),
        .init(actionID: "win-max", keyCode: HyperKeyCode.keypad5, title: "Maximize (Num 5)"),
        .init(actionID: "win-right", keyCode: HyperKeyCode.keypad6, title: "Right Half (Num 6)"),
        .init(actionID: "win-bl", keyCode: HyperKeyCode.keypad1, title: "Bottom-Left (Num 1)"),
        .init(actionID: "win-bottom", keyCode: HyperKeyCode.keypad2, title: "Bottom Half (Num 2)"),
        .init(actionID: "win-br", keyCode: HyperKeyCode.keypad3, title: "Bottom-Right (Num 3)"),
        .init(actionID: "win-center", keyCode: HyperKeyCode.keypad0, title: "Center (Num 0)"),
        .init(actionID: "win-close", keyCode: HyperKeyCode.x, title: "Close Window"),
        .init(actionID: "win-always-on-top", keyCode: HyperKeyCode.a, title: "Always On Top"),
        .init(actionID: "win-minimize", keyCode: HyperKeyCode.b, title: "Minimize"),
        // Scroll / keep-alive
        .init(actionID: "scroll-left", keyCode: HyperKeyCode.h, title: "Scroll Left"),
        .init(actionID: "scroll-down", keyCode: HyperKeyCode.j, title: "Scroll Down"),
        .init(actionID: "prod-keepalive", keyCode: HyperKeyCode.k, title: "Keep-Alive"),
        .init(actionID: "scroll-right", keyCode: HyperKeyCode.l, title: "Scroll Right"),
        // Apps
        .init(actionID: "app-chrome", keyCode: HyperKeyCode.one, title: "Chrome"),
        .init(actionID: "app-zed", keyCode: HyperKeyCode.two, title: "Zed"),
        .init(actionID: "app-teams", keyCode: HyperKeyCode.three, title: "Teams"),
        .init(actionID: "app-vscode", keyCode: HyperKeyCode.four, title: "VS Code"),
        .init(actionID: "app-zoom", keyCode: HyperKeyCode.five, title: "Zoom"),
        .init(actionID: "app-iterm", keyCode: HyperKeyCode.t, title: "Terminal smart"),
        .init(
            actionID: "app-terminal-here",
            keyCode: HyperKeyCode.t,
            requiresExtraShift: true,
            title: "Terminal in Finder"
        ),
        .init(actionID: "app-finder", keyCode: HyperKeyCode.f, title: "Finder"),
        .init(
            actionID: "finder-open-editor",
            keyCode: HyperKeyCode.f,
            requiresExtraShift: true,
            title: "Open in Editor"
        ),
        .init(
            actionID: "finder-copy-text",
            keyCode: HyperKeyCode.c,
            requiresExtraShift: true,
            title: "Copy Finder Text"
        ),
        .init(actionID: "app-toggle", keyCode: HyperKeyCode.tab, title: "Toggle App"),
        // Productivity
        .init(actionID: "prod-shell", keyCode: HyperKeyCode.s, title: "Focus Terminal"),
        .init(
            actionID: "sys-shortcuts",
            keyCode: HyperKeyCode.s,
            requiresExtraShift: true,
            title: "Run Shortcut (⇧S)"
        ),
        .init(actionID: "sys-shortcuts", keyCode: HyperKeyCode.quote, title: "Run Shortcut (')"),
        .init(actionID: "prod-note", keyCode: HyperKeyCode.n, title: "Quick Note"),
        .init(actionID: "prod-today", keyCode: HyperKeyCode.d, title: "Today Notes"),
        .init(actionID: "prod-date", keyCode: HyperKeyCode.period, title: "Type Date"),
        .init(actionID: "prod-pomodoro", keyCode: HyperKeyCode.o, title: "Pomodoro"),
        .init(actionID: "prod-google", keyCode: HyperKeyCode.g, title: "Google Selection"),
        // Clipboard
        .init(actionID: "clip-url", keyCode: HyperKeyCode.u, title: "Open URL"),
        .init(actionID: "clip-plain", keyCode: HyperKeyCode.e, title: "Paste Plain"),
        .init(actionID: "clip-nvim", keyCode: HyperKeyCode.v, title: "Clipboard nvim"),
        .init(
            actionID: "clip-paste-menu",
            keyCode: HyperKeyCode.v,
            requiresExtraShift: true,
            title: "Paste Transform"
        ),
        .init(actionID: "clip-region-pin", keyCode: HyperKeyCode.p, title: "Pin Screen Region"),
        .init(
            actionID: "clip-image",
            keyCode: HyperKeyCode.p,
            requiresExtraShift: true,
            title: "Clipboard Image (⇧P)"
        ),
        // System
        .init(actionID: "sys-net", keyCode: HyperKeyCode.i, title: "Network Info"),
        .init(
            actionID: "sys-copy-ip",
            keyCode: HyperKeyCode.i,
            requiresExtraShift: true,
            title: "Copy IP"
        ),
        .init(
            actionID: "sys-copy-hostname",
            keyCode: HyperKeyCode.m,
            requiresExtraShift: true,
            title: "Copy Hostname"
        ),
        .init(
            actionID: "sys-reverse-dns",
            keyCode: HyperKeyCode.w,
            requiresExtraShift: true,
            title: "Reverse DNS"
        ),
        .init(actionID: "sys-mic", keyCode: HyperKeyCode.semicolon, title: "Mic Toggle"),
        .init(actionID: "sys-lock", keyCode: HyperKeyCode.escape, title: "Lock Screen"),
        .init(actionID: "sys-reload", keyCode: HyperKeyCode.r, title: "Reload Engine"),
        .init(actionID: "sys-command-bar", keyCode: HyperKeyCode.space, title: "Command Bar"),
        .init(actionID: "sys-dashboard", keyCode: HyperKeyCode.comma, title: "Dashboard"),
        .init(actionID: "sys-quick-menu", keyCode: HyperKeyCode.q, title: "Quick Menu"),
        .init(actionID: "sys-recipes", keyCode: HyperKeyCode.y, title: "AX Recipes"),
        .init(actionID: "sys-cheatsheet", keyCode: HyperKeyCode.grave, title: "Cheat Sheet (`)"),
        // Slash: primary F18 path is link-hints; 4-mod / extraShift → cheat sheet (see resolve)
        .init(actionID: "sys-link-hints", keyCode: HyperKeyCode.slash, title: "Link Hints (F18 /)"),
        .init(
            actionID: "sys-cheatsheet",
            keyCode: HyperKeyCode.slash,
            requiresExtraShift: true,
            title: "Cheat Sheet (⇧/)"
        ),
    ]

    /// Resolve Hyper keyDown → catalog action id (or unhandled).
    public static func resolve(
        keyCode: UInt16,
        shiftDown: Bool = false,
        hyperConsumesShift: Bool = false,
        enabledIDs: Set<String>? = nil
    ) -> HyperBindingRoute {
        func allowed(_ id: String) -> Bool {
            HyperChordRouting.isAllowed(actionID: id, enabledIDs: enabledIDs)
        }
        let extraShift = HyperChordRouting.extraShift(
            shiftDown: shiftDown,
            hyperConsumesShift: hyperConsumesShift
        )

        switch keyCode {
        case HyperKeyCode.leftArrow where allowed("win-left"):
            return .action("win-left")
        case HyperKeyCode.rightArrow where allowed("win-right"):
            return .action("win-right")
        case HyperKeyCode.upArrow where allowed("win-top"):
            return .action("win-top")
        case HyperKeyCode.downArrow where allowed("win-bottom"):
            return .action("win-bottom")
        case HyperKeyCode.return:
            if extraShift, allowed("win-tile-all") { return .action("win-tile-all") }
            if allowed("win-max") { return .action("win-max") }
            return .unhandled
        case HyperKeyCode.six where allowed("win-tile-all"):
            return .action("win-tile-all")
        case HyperKeyCode.c:
            if extraShift, allowed("finder-copy-text") { return .action("finder-copy-text") }
            if allowed("win-center") { return .action("win-center") }
            return .unhandled
        case HyperKeyCode.m:
            if extraShift, allowed("sys-copy-hostname") { return .action("sys-copy-hostname") }
            if allowed("win-next-screen") { return .action("win-next-screen") }
            return .unhandled
        case HyperKeyCode.z where allowed("win-undo"):
            return .action("win-undo")
        case HyperKeyCode.seven where allowed("win-tl"),
             HyperKeyCode.keypad7 where allowed("win-tl"):
            return .action("win-tl")
        case HyperKeyCode.eight where allowed("win-tr"):
            // Top-row 8 = top-right quarter (legacy); numpad 8 = top half
            return .action("win-tr")
        case HyperKeyCode.keypad8 where allowed("win-top"):
            return .action("win-top")
        case HyperKeyCode.keypad9 where allowed("win-tr"):
            return .action("win-tr")
        case HyperKeyCode.nine where allowed("win-bl"),
             HyperKeyCode.keypad1 where allowed("win-bl"):
            return .action("win-bl")
        case HyperKeyCode.zero where allowed("win-br"),
             HyperKeyCode.keypad3 where allowed("win-br"):
            return .action("win-br")
        case HyperKeyCode.keypad4 where allowed("win-left"):
            return .action("win-left")
        case HyperKeyCode.keypad5 where allowed("win-max"):
            return .action("win-max")
        case HyperKeyCode.keypad6 where allowed("win-right"):
            return .action("win-right")
        case HyperKeyCode.keypad2 where allowed("win-bottom"):
            return .action("win-bottom")
        case HyperKeyCode.keypad0 where allowed("win-center"):
            return .action("win-center")
        case HyperKeyCode.tab where allowed("app-toggle"):
            return .action("app-toggle")
        case HyperKeyCode.h where allowed("scroll-left"):
            return .action("scroll-left")
        case HyperKeyCode.j where allowed("scroll-down"):
            return .action("scroll-down")
        case HyperKeyCode.k where allowed("prod-keepalive"):
            return .action("prod-keepalive")
        case HyperKeyCode.l where allowed("scroll-right"):
            return .action("scroll-right")
        case HyperKeyCode.one where allowed("app-chrome"):
            return .action("app-chrome")
        case HyperKeyCode.two where allowed("app-zed"):
            return .action("app-zed")
        case HyperKeyCode.three where allowed("app-teams"):
            return .action("app-teams")
        case HyperKeyCode.four where allowed("app-vscode"):
            return .action("app-vscode")
        case HyperKeyCode.five where allowed("app-zoom"):
            return .action("app-zoom")
        case HyperKeyCode.t where allowed("app-iterm") || allowed("app-terminal-here"):
            if extraShift, allowed("app-terminal-here") { return .action("app-terminal-here") }
            if allowed("app-iterm") { return .action("app-iterm") }
            if allowed("app-terminal-here") { return .action("app-terminal-here") }
            return .unhandled
        case HyperKeyCode.f where allowed("app-finder") || allowed("finder-open-editor"):
            if extraShift, allowed("finder-open-editor") { return .action("finder-open-editor") }
            if allowed("app-finder") { return .action("app-finder") }
            return .unhandled
        case HyperKeyCode.s where allowed("prod-shell") || allowed("sys-shortcuts"):
            if extraShift, allowed("sys-shortcuts") { return .action("sys-shortcuts") }
            if allowed("prod-shell") { return .action("prod-shell") }
            return .unhandled
        case HyperKeyCode.quote where allowed("sys-shortcuts"):
            return .action("sys-shortcuts")
        case HyperKeyCode.n where allowed("prod-note"):
            return .action("prod-note")
        case HyperKeyCode.d where allowed("prod-today"):
            return .action("prod-today")
        case HyperKeyCode.period where allowed("prod-date"):
            return .action("prod-date")
        case HyperKeyCode.i where allowed("sys-net") || allowed("sys-copy-ip"):
            if extraShift, allowed("sys-copy-ip") { return .action("sys-copy-ip") }
            if allowed("sys-net") { return .action("sys-net") }
            return .unhandled
        case HyperKeyCode.u where allowed("clip-url"):
            return .action("clip-url")
        case HyperKeyCode.x where allowed("win-close"):
            return .action("win-close")
        case HyperKeyCode.semicolon where allowed("sys-mic"):
            return .action("sys-mic")
        case HyperKeyCode.v where allowed("clip-nvim") || allowed("clip-paste-menu"):
            if extraShift, allowed("clip-paste-menu") { return .action("clip-paste-menu") }
            if allowed("clip-nvim") { return .action("clip-nvim") }
            return .unhandled
        case HyperKeyCode.p where allowed("clip-region-pin") || allowed("clip-image"):
            if extraShift, allowed("clip-image") { return .action("clip-image") }
            if allowed("clip-region-pin") { return .action("clip-region-pin") }
            if allowed("clip-image") { return .action("clip-image") }
            return .unhandled
        case HyperKeyCode.o where allowed("prod-pomodoro"):
            return .action("prod-pomodoro")
        case HyperKeyCode.e where allowed("clip-plain"):
            return .action("clip-plain")
        case HyperKeyCode.g where allowed("prod-google"):
            return .action("prod-google")
        case HyperKeyCode.escape where allowed("sys-lock"):
            return .action("sys-lock")
        case HyperKeyCode.r where allowed("sys-reload"):
            return .action("sys-reload")
        case HyperKeyCode.space where allowed("sys-command-bar"):
            return .action("sys-command-bar")
        case HyperKeyCode.comma where allowed("sys-dashboard"):
            return .action("sys-dashboard")
        case HyperKeyCode.slash:
            switch HyperChordRouting.slashAction(
                shiftDown: shiftDown,
                hyperConsumesShift: hyperConsumesShift,
                linkHintsAllowed: allowed("sys-link-hints")
            ) {
            case .cheatSheet, .cheatSheetFallback:
                return allowed("sys-cheatsheet") || true ? .action("sys-cheatsheet") : .unhandled
            case .linkHints:
                return .action("sys-link-hints")
            }
        case HyperKeyCode.grave:
            return .action("sys-cheatsheet")
        case HyperKeyCode.a where allowed("win-always-on-top"):
            return .action("win-always-on-top")
        case HyperKeyCode.b where allowed("win-minimize"):
            return .action("win-minimize")
        case HyperKeyCode.q where allowed("sys-quick-menu"):
            return .action("sys-quick-menu")
        case HyperKeyCode.y where allowed("sys-recipes"):
            return .action("sys-recipes")
        case HyperKeyCode.w where extraShift && allowed("sys-reverse-dns"):
            return .action("sys-reverse-dns")
        default:
            return .unhandled
        }
    }

    /// Action IDs that the Hyper engine routes (for catalog coverage checks).
    public static var routedActionIDs: Set<String> {
        Set(specs.map(\.actionID))
    }
}
