// HyperAction.swift
// Catalog of Hyper / Vim bindings shown in the dashboard and used by the engine.

import CoreGraphics
import Foundation
import SwiftUI

enum ActionCategory: String, CaseIterable, Identifiable, Codable {
    case window = "Window"
    case scroll = "Scroll"
    case apps = "Apps"
    case productivity = "Productivity"
    case clipboard = "Clipboard"
    case system = "System"
    case vim = "Space Nav"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .window: return "rectangle.split.2x1"
        case .scroll: return "arrow.up.and.down"
        case .apps: return "app.badge"
        case .productivity: return "bolt.fill"
        case .clipboard: return "doc.on.clipboard"
        case .system: return "gearshape"
        case .vim: return "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .window: return Color(hex: 0x5B8DEF)
        case .scroll: return Color(hex: 0x34C759)
        case .apps: return Color(hex: 0xFF9F0A)
        case .productivity: return Color(hex: 0xBF5AF2)
        case .clipboard: return Color(hex: 0x64D2FF)
        case .system: return Color(hex: 0x8E8E93)
        case .vim: return Color(hex: 0xFF375F)
        }
    }
}

enum BindingMode: String, Codable, CaseIterable {
    case hyper = "Hyper"
    case vim = "Vim"
    case vimShift = "Vim+Shift"
    case vimCtrl = "Vim+Ctrl"
}

struct HyperAction: Identifiable, Equatable, Codable, Hashable {
    let id: String
    var title: String
    var detail: String
    var keyCode: UInt16
    var mode: BindingMode
    var category: ActionCategory
    var isEnabled: Bool
    var symbol: String

    var keyLabel: String {
        switch id {
        case "sys-cheatsheet": return "/  or  `"
        case "sys-dashboard": return ","
        case "clip-paste-menu": return "⇧V"
        case "clip-region-pin": return "P"
        case "clip-image": return "⇧P"
        case "app-terminal-here": return "⇧T"
        case "finder-copy-text": return "⇧C"
        case "finder-open-editor": return "⇧F"
        case "sys-copy-ip": return "⇧I"
        case "sys-copy-hostname": return "⇧M"
        case "sys-reverse-dns": return "⇧W"
        case "sys-shortcuts": return "'  ·  ⇧S"
        case "win-tile-all": return "6"
        case "win-tl": return "7 · Num7"
        case "win-tr": return "8 · Num9"
        case "win-bl": return "9 · Num1"
        case "win-br": return "0 · Num3"
        default: return KeyCode.displayName(CGKeyCode(keyCode))
        }
    }

    var shortcutDisplay: String {
        switch id {
        case "sys-cheatsheet": return "Hyper + /  ·  Hyper + `  (4-mod: via F19)"
        case "sys-dashboard": return "Hyper + ,  ·  ⌘⇧D  (4-mod: via F20)"
        case "clip-paste-menu": return "Hyper + ⇧V"
        case "clip-region-pin": return "Hyper + P"
        case "clip-image": return "Hyper + ⇧P  (F18 extra Shift)"
        case "app-terminal-here": return "Hyper + ⇧T"
        case "finder-copy-text": return "Hyper + ⇧C"
        case "finder-open-editor": return "Hyper + ⇧F"
        case "sys-copy-ip": return "Hyper + ⇧I"
        case "sys-copy-hostname": return "Hyper + ⇧M"
        case "sys-reverse-dns": return "Hyper + ⇧W"
        case "sys-shortcuts": return "Hyper + '  ·  Hyper + ⇧S"
        case "win-tile-all": return "Hyper + 6  ·  Hyper + ⇧↩"
        case "win-tl": return "Hyper + 7  ·  Num 7"
        case "win-tr": return "Hyper + 8  ·  Num 9"
        case "win-bl": return "Hyper + 9  ·  Num 1"
        case "win-br": return "Hyper + 0  ·  Num 3"
        default: break
        }
        switch mode {
        case .hyper: return "Hyper + \(keyLabel)"
        case .vim: return "Space + \(keyLabel)"
        case .vimShift: return "Space + ⇧\(keyLabel)"
        case .vimCtrl: return "Space + ⌃\(keyLabel)"
        }
    }
}

// MARK: - Default catalog

enum ActionCatalog {
    static let defaults: [HyperAction] = [
        // Window
        HyperAction(id: "win-left", title: "Snap Left Half", detail: "Left 50% of screen", keyCode: KeyCode.leftArrow, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.lefthalf.filled"),
        HyperAction(id: "win-right", title: "Snap Right Half", detail: "Right 50% of screen", keyCode: KeyCode.rightArrow, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.righthalf.filled"),
        HyperAction(id: "win-top", title: "Snap Top Half", detail: "Top 50% of screen", keyCode: KeyCode.upArrow, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.tophalf.filled"),
        HyperAction(id: "win-bottom", title: "Snap Bottom Half", detail: "Bottom 50% of screen", keyCode: KeyCode.downArrow, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.bottomhalf.filled"),
        HyperAction(id: "win-max", title: "Maximize", detail: "Fill visible screen", keyCode: KeyCode.return, mode: .hyper, category: .window, isEnabled: true, symbol: "arrow.up.left.and.arrow.down.right"),
        HyperAction(id: "win-tile-all", title: "Tile All Windows", detail: "Grid every visible window on this screen", keyCode: KeyCode.six, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.split.3x3"),
        HyperAction(id: "win-center", title: "Center Window", detail: "Keep size, center on screen", keyCode: KeyCode.c, mode: .hyper, category: .window, isEnabled: true, symbol: "rectangle.center.inset.filled"),
        HyperAction(id: "win-next-screen", title: "Next Display", detail: "Move window to next screen", keyCode: KeyCode.m, mode: .hyper, category: .window, isEnabled: true, symbol: "display.2"),
        HyperAction(id: "win-undo", title: "Undo Snap", detail: "Restore previous frame", keyCode: KeyCode.z, mode: .hyper, category: .window, isEnabled: true, symbol: "arrow.uturn.backward"),
        HyperAction(id: "win-tl", title: "Top-Left Quarter", detail: "25% top-left · top-row 7 or numpad 7", keyCode: KeyCode.seven, mode: .hyper, category: .window, isEnabled: true, symbol: "square.grid.2x2"),
        HyperAction(id: "win-tr", title: "Top-Right Quarter", detail: "25% top-right · top-row 8 or numpad 9", keyCode: KeyCode.eight, mode: .hyper, category: .window, isEnabled: true, symbol: "square.grid.2x2"),
        HyperAction(id: "win-bl", title: "Bottom-Left Quarter", detail: "25% bottom-left · top-row 9 or numpad 1", keyCode: KeyCode.nine, mode: .hyper, category: .window, isEnabled: true, symbol: "square.grid.2x2"),
        HyperAction(id: "win-br", title: "Bottom-Right Quarter", detail: "25% bottom-right · top-row 0 or numpad 3", keyCode: KeyCode.zero, mode: .hyper, category: .window, isEnabled: true, symbol: "square.grid.2x2"),
        // Hide-others is available via Live Test / Command Bar (Hyper+H is scroll left in the engine).
        HyperAction(id: "win-hide-others", title: "Hide Other Apps", detail: "Hide every non-front app (command bar)", keyCode: KeyCode.h, mode: .hyper, category: .window, isEnabled: true, symbol: "eye.slash"),
        HyperAction(id: "win-close", title: "Close Window", detail: "⌘W on front window", keyCode: KeyCode.x, mode: .hyper, category: .window, isEnabled: true, symbol: "xmark"),
        HyperAction(id: "win-always-on-top", title: "Always On Top", detail: "Pin frontmost window (best-effort)", keyCode: KeyCode.a, mode: .hyper, category: .window, isEnabled: true, symbol: "pin"),
        HyperAction(id: "win-minimize", title: "Minimize Window", detail: "Minimize frontmost window", keyCode: KeyCode.b, mode: .hyper, category: .window, isEnabled: true, symbol: "minus.rectangle"),

        // Scroll (Hyper) — note: Hyper+K is keep-alive in the engine.
        HyperAction(id: "scroll-left", title: "Scroll Left", detail: "Hyper + H", keyCode: KeyCode.h, mode: .hyper, category: .scroll, isEnabled: true, symbol: "arrow.left"),
        HyperAction(id: "scroll-down", title: "Scroll Down", detail: "Hyper + J", keyCode: KeyCode.j, mode: .hyper, category: .scroll, isEnabled: true, symbol: "arrow.down"),
        HyperAction(id: "scroll-up", title: "Scroll Up", detail: "Live test / Vim ⌃u (Hyper+K is keep-alive)", keyCode: KeyCode.u, mode: .vimCtrl, category: .scroll, isEnabled: true, symbol: "arrow.up"),
        HyperAction(id: "scroll-right", title: "Scroll Right", detail: "Hyper + L", keyCode: KeyCode.l, mode: .hyper, category: .scroll, isEnabled: true, symbol: "arrow.right"),

        // Apps — launch / focus / minimize cycle (AHK RunOrActivateOrMinimize)
        HyperAction(id: "app-chrome", title: "Chrome", detail: "Launch → focus → minimize cycle", keyCode: KeyCode.one, mode: .hyper, category: .apps, isEnabled: true, symbol: "globe"),
        HyperAction(id: "app-zed", title: "Zed", detail: "Launch → focus → minimize cycle", keyCode: KeyCode.two, mode: .hyper, category: .apps, isEnabled: true, symbol: "chevron.left.forwardslash.chevron.right"),
        HyperAction(id: "app-teams", title: "Teams", detail: "Launch → focus → minimize cycle", keyCode: KeyCode.three, mode: .hyper, category: .apps, isEnabled: true, symbol: "person.3"),
        HyperAction(id: "app-vscode", title: "VS Code", detail: "Launch → focus → minimize cycle", keyCode: KeyCode.four, mode: .hyper, category: .apps, isEnabled: true, symbol: "chevron.left.forwardslash.chevron.right"),
        HyperAction(id: "app-zoom", title: "Zoom", detail: "Launch → focus → minimize cycle", keyCode: KeyCode.five, mode: .hyper, category: .apps, isEnabled: true, symbol: "video"),
        HyperAction(id: "app-iterm", title: "Terminal (smart)", detail: "New tab if running, else launch — Settings → Apps", keyCode: KeyCode.t, mode: .hyper, category: .apps, isEnabled: true, symbol: "terminal"),
        HyperAction(id: "app-terminal-here", title: "Terminal in Finder Folder", detail: "Preferred terminal → cd Finder path", keyCode: KeyCode.t, mode: .hyper, category: .apps, isEnabled: true, symbol: "folder.badge.gearshape"),
        HyperAction(id: "app-finder", title: "New Finder Window", detail: "Open Finder", keyCode: KeyCode.f, mode: .hyper, category: .apps, isEnabled: true, symbol: "folder"),
        HyperAction(id: "finder-open-editor", title: "Open Selection in Editor", detail: "Finder selection → Zed/VS Code", keyCode: KeyCode.f, mode: .hyper, category: .apps, isEnabled: true, symbol: "doc.badge.gearshape"),
        HyperAction(id: "finder-copy-text", title: "Copy Finder File Text", detail: "Selected file contents → clipboard", keyCode: KeyCode.c, mode: .hyper, category: .apps, isEnabled: true, symbol: "doc.text"),
        HyperAction(id: "app-toggle", title: "Toggle Last App", detail: "Switch between last two apps", keyCode: KeyCode.tab, mode: .hyper, category: .apps, isEnabled: true, symbol: "arrow.left.arrow.right"),

        // Productivity
        HyperAction(id: "prod-keepalive", title: "Keep-Alive Toggle", detail: "Prevent idle lock (Teams-safe)", keyCode: KeyCode.k, mode: .hyper, category: .productivity, isEnabled: true, symbol: "bolt.heart"),
        HyperAction(id: "prod-note", title: "Quick Note", detail: "Capture a thought to today's markdown", keyCode: KeyCode.n, mode: .hyper, category: .productivity, isEnabled: true, symbol: "note.text"),
        HyperAction(id: "prod-today", title: "Open Today’s Notes", detail: "Preferred terminal + nvim on daily note", keyCode: KeyCode.d, mode: .hyper, category: .productivity, isEnabled: true, symbol: "calendar"),
        HyperAction(id: "prod-date", title: "Type Date", detail: "Insert yyyy-MM-dd", keyCode: KeyCode.period, mode: .hyper, category: .productivity, isEnabled: true, symbol: "calendar.badge.clock"),
        HyperAction(id: "prod-pomodoro", title: "Pomodoro", detail: "25-minute focus timer", keyCode: KeyCode.o, mode: .hyper, category: .productivity, isEnabled: true, symbol: "timer"),
        HyperAction(id: "prod-google", title: "Google Selection", detail: "Search selected text", keyCode: KeyCode.g, mode: .hyper, category: .productivity, isEnabled: true, symbol: "magnifyingglass"),
        HyperAction(id: "prod-shell", title: "Focus Terminal", detail: "Preferred terminal (Settings → Apps)", keyCode: KeyCode.s, mode: .hyper, category: .productivity, isEnabled: true, symbol: "terminal"),

        // Clipboard
        HyperAction(id: "clip-url", title: "Open Clipboard URL", detail: "Extract & open first URL", keyCode: KeyCode.u, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "link"),
        HyperAction(id: "clip-plain", title: "Paste Plain Text", detail: "Strip rich formatting", keyCode: KeyCode.e, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "doc.plaintext"),
        HyperAction(id: "clip-nvim", title: "Clipboard → nvim", detail: "Edit pasteboard in preferred terminal", keyCode: KeyCode.v, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "doc.text"),
        HyperAction(id: "clip-paste-menu", title: "Paste Transform Menu", detail: "CSV, Base64, URL, timestamps…", keyCode: KeyCode.v, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "arrow.triangle.2.circlepath"),
        HyperAction(id: "clip-region-pin", title: "Pin Screen Region", detail: "Drag-select region → stay-on-top window", keyCode: KeyCode.p, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "crop"),
        HyperAction(id: "clip-image", title: "Clipboard Image", detail: "Manual pin of pasteboard image (Hyper+⇧P) · not auto", keyCode: KeyCode.p, mode: .hyper, category: .clipboard, isEnabled: true, symbol: "photo"),

        // System
        HyperAction(id: "sys-net", title: "Network Info", detail: "Wi-Fi + IP + hostname", keyCode: KeyCode.i, mode: .hyper, category: .system, isEnabled: true, symbol: "wifi"),
        HyperAction(id: "sys-copy-ip", title: "Copy IP", detail: "Primary en0 address → clipboard", keyCode: KeyCode.i, mode: .hyper, category: .system, isEnabled: true, symbol: "network"),
        HyperAction(id: "sys-copy-hostname", title: "Copy Hostname", detail: "Machine name → clipboard", keyCode: KeyCode.m, mode: .hyper, category: .system, isEnabled: true, symbol: "desktopcomputer"),
        HyperAction(id: "sys-reverse-dns", title: "Reverse DNS", detail: "host lookup on clipboard IP", keyCode: KeyCode.w, mode: .hyper, category: .system, isEnabled: true, symbol: "globe"),
        HyperAction(id: "sys-mic", title: "Mic Toggle", detail: "Mute / unmute input", keyCode: KeyCode.semicolon, mode: .hyper, category: .system, isEnabled: true, symbol: "mic"),
        HyperAction(id: "sys-lock", title: "Lock Screen", detail: "pmset displaysleepnow", keyCode: KeyCode.escape, mode: .hyper, category: .system, isEnabled: true, symbol: "lock"),
        HyperAction(id: "sys-reload", title: "Reload Engine", detail: "Soft restart HyperForge engine", keyCode: KeyCode.r, mode: .hyper, category: .system, isEnabled: true, symbol: "arrow.clockwise"),
        HyperAction(id: "sys-command-bar", title: "Command Bar", detail: "Local AI / action palette", keyCode: KeyCode.space, mode: .hyper, category: .system, isEnabled: true, symbol: "sparkles"),
        HyperAction(id: "sys-dashboard", title: "Show Dashboard", detail: "Open main UI · Esc hides it", keyCode: KeyCode.comma, mode: .hyper, category: .system, isEnabled: true, symbol: "rectangle.center.inset.filled"),
        HyperAction(id: "sys-quick-menu", title: "Quick Menu", detail: "Cursor power menu (AHK XButton2)", keyCode: KeyCode.q, mode: .hyper, category: .system, isEnabled: true, symbol: "list.bullet.rectangle"),
        HyperAction(id: "sys-recipes", title: "AX Recipes", detail: "UI automation playbooks", keyCode: KeyCode.y, mode: .hyper, category: .system, isEnabled: true, symbol: "wand.and.stars"),
        HyperAction(id: "sys-shortcuts", title: "Run Shortcut", detail: "Menu of installed macOS Shortcuts", keyCode: KeyCode.quote, mode: .hyper, category: .system, isEnabled: true, symbol: "sparkles.rectangle.stack"),
        HyperAction(id: "sys-link-hints", title: "Link Hints", detail: "F18 Hyper + / · (4-mod Hyper uses F19 for help)", keyCode: KeyCode.slash, mode: .hyper, category: .system, isEnabled: true, symbol: "link.circle"),
        HyperAction(id: "sys-cheatsheet", title: "Keybinding Cheat Sheet", detail: "Hyper + / (F19) · Hyper + ⇧/ (F18) · Hyper + ` · menu bar", keyCode: KeyCode.grave, mode: .hyper, category: .system, isEnabled: true, symbol: "keyboard"),

        // Space-layer nav (TouchCursor-style — hold Space, then key)
        HyperAction(id: "vim-h", title: "Left", detail: "Hold Space + H", keyCode: KeyCode.h, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.left"),
        HyperAction(id: "vim-j", title: "Down", detail: "Hold Space + J", keyCode: KeyCode.j, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.down"),
        HyperAction(id: "vim-k", title: "Up", detail: "Hold Space + K", keyCode: KeyCode.k, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.up"),
        HyperAction(id: "vim-l", title: "Right", detail: "Hold Space + L", keyCode: KeyCode.l, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.right"),
        HyperAction(id: "vim-b", title: "Word Back", detail: "Space + B · or delete word if d-waiting", keyCode: KeyCode.b, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.left.to.line"),
        HyperAction(id: "vim-w", title: "Word Forward", detail: "Space + W · or dw deletes word", keyCode: KeyCode.w, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.right.to.line"),
        HyperAction(id: "vim-e", title: "Word End", detail: "Space + E → ⌥→", keyCode: KeyCode.e, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.right.to.line"),
        HyperAction(id: "vim-0", title: "Line Start", detail: "Space + 0 or I → ⌘←", keyCode: KeyCode.zero, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.left.to.line.compact"),
        HyperAction(id: "vim-4", title: "Line End", detail: "Space + 4 or O → ⌘→", keyCode: KeyCode.four, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.right.to.line.compact"),
        HyperAction(id: "vim-x", title: "Kill to End of Line", detail: "Space + X · like vim D / ⌃K", keyCode: KeyCode.x, mode: .vim, category: .vim, isEnabled: true, symbol: "delete.right"),
        HyperAction(id: "vim-kill-sol", title: "Kill to Start of Line", detail: "Space + ⇧X", keyCode: KeyCode.x, mode: .vimShift, category: .vim, isEnabled: true, symbol: "delete.left"),
        HyperAction(id: "vim-dd", title: "Kill Line", detail: "Space + D D (vim dd)", keyCode: KeyCode.d, mode: .vim, category: .vim, isEnabled: true, symbol: "trash"),
        HyperAction(id: "vim-select-line", title: "Select Line", detail: "Space + A", keyCode: KeyCode.a, mode: .vim, category: .vim, isEnabled: true, symbol: "text.cursor"),
        HyperAction(id: "vim-y", title: "Copy", detail: "Space + Y → ⌘C", keyCode: KeyCode.y, mode: .vim, category: .vim, isEnabled: true, symbol: "doc.on.doc"),
        HyperAction(id: "vim-yank-line", title: "Copy Line", detail: "Space + ⇧Y", keyCode: KeyCode.y, mode: .vimShift, category: .vim, isEnabled: true, symbol: "doc.on.clipboard"),
        HyperAction(id: "vim-p", title: "Paste", detail: "Space + P → ⌘V", keyCode: KeyCode.p, mode: .vim, category: .vim, isEnabled: true, symbol: "doc.on.clipboard.fill"),
        HyperAction(id: "vim-c", title: "Cut", detail: "Space + C → ⌘X", keyCode: KeyCode.c, mode: .vim, category: .vim, isEnabled: true, symbol: "scissors"),
        HyperAction(id: "vim-u", title: "Undo", detail: "Space + U → ⌘Z", keyCode: KeyCode.u, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.uturn.backward"),
        HyperAction(id: "vim-r", title: "Redo", detail: "Space + R → ⌘⇧Z", keyCode: KeyCode.r, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.uturn.forward"),
        HyperAction(id: "vim-s", title: "Save", detail: "Space + S → ⌘S", keyCode: KeyCode.s, mode: .vim, category: .vim, isEnabled: true, symbol: "square.and.arrow.down"),
        HyperAction(id: "vim-f", title: "Find", detail: "Space + F → ⌘F", keyCode: KeyCode.f, mode: .vim, category: .vim, isEnabled: true, symbol: "magnifyingglass"),
        HyperAction(id: "vim-n", title: "Find Next", detail: "Space + N → ⌘G", keyCode: KeyCode.n, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.right.circle"),
        HyperAction(id: "vim-N", title: "Find Previous", detail: "Space + ⇧N → ⌘⇧G", keyCode: KeyCode.n, mode: .vimShift, category: .vim, isEnabled: true, symbol: "arrow.left.circle"),
        HyperAction(id: "vim-q", title: "Escape", detail: "Space + Q", keyCode: KeyCode.q, mode: .vim, category: .vim, isEnabled: true, symbol: "escape"),
        HyperAction(id: "vim-m", title: "Return", detail: "Space + M", keyCode: KeyCode.m, mode: .vim, category: .vim, isEnabled: true, symbol: "return"),
        HyperAction(id: "vim-page-up", title: "Page Up", detail: "Space + ,", keyCode: KeyCode.comma, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.up.doc"),
        HyperAction(id: "vim-page-down", title: "Page Down", detail: "Space + .", keyCode: KeyCode.period, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.down.doc"),
        HyperAction(id: "vim-gg", title: "Top of Doc", detail: "Space + G G — jump to top", keyCode: KeyCode.g, mode: .vim, category: .vim, isEnabled: true, symbol: "arrow.up.to.line"),
        HyperAction(id: "vim-G", title: "Bottom of Doc", detail: "Space + ⇧G — jump to bottom", keyCode: KeyCode.g, mode: .vimShift, category: .vim, isEnabled: true, symbol: "arrow.down.to.line"),
        HyperAction(id: "vim-ctrl-d", title: "Half Page Down", detail: "Space + ⌃D scroll", keyCode: KeyCode.d, mode: .vimCtrl, category: .vim, isEnabled: true, symbol: "arrow.down.doc"),
        HyperAction(id: "vim-ctrl-u", title: "Half Page Up", detail: "Space + ⌃U scroll", keyCode: KeyCode.u, mode: .vimCtrl, category: .vim, isEnabled: true, symbol: "arrow.up.doc"),
        HyperAction(id: "vim-ctrl-f", title: "Full Page Down", detail: "Space + ⌃F scroll", keyCode: KeyCode.f, mode: .vimCtrl, category: .vim, isEnabled: true, symbol: "arrow.down.to.line.compact"),
        HyperAction(id: "vim-ctrl-b", title: "Full Page Up", detail: "Space + ⌃B scroll", keyCode: KeyCode.b, mode: .vimCtrl, category: .vim, isEnabled: true, symbol: "arrow.up.to.line.compact"),
        HyperAction(id: "vim-t", title: "Focus Terminal", detail: "Space + T · or zt align", keyCode: KeyCode.t, mode: .vim, category: .vim, isEnabled: true, symbol: "terminal"),
    ]

    static func grouped(_ actions: [HyperAction]) -> [(ActionCategory, [HyperAction])] {
        ActionCategory.allCases.compactMap { cat in
            let items = actions.filter { $0.category == cat && $0.isEnabled }
            return items.isEmpty ? nil : (cat, items)
        }
    }
}

// MARK: - Space-layer cheat-sheet subgroups

enum SpaceNavGroup: String, CaseIterable, Identifiable {
    case move = "Move"
    case kill = "Kill / edit"
    case clipboard = "Clipboard"
    case mac = "Mac"
    case scroll = "Scroll"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .kill: return "delete.right"
        case .clipboard: return "doc.on.clipboard"
        case .mac: return "command"
        case .scroll: return "arrow.up.and.down"
        case .other: return "ellipsis.circle"
        }
    }

    static func group(for action: HyperAction) -> SpaceNavGroup {
        switch action.id {
        case "vim-h", "vim-j", "vim-k", "vim-l",
             "vim-b", "vim-w", "vim-e", "vim-0", "vim-4",
             "vim-gg", "vim-G", "vim-page-up", "vim-page-down":
            return .move
        case "vim-x", "vim-kill-sol", "vim-dd", "vim-select-line":
            return .kill
        case "vim-y", "vim-yank-line", "vim-p", "vim-c", "vim-u", "vim-r":
            return .clipboard
        case "vim-s", "vim-f", "vim-n", "vim-N", "vim-q", "vim-m", "vim-t":
            return .mac
        case "vim-ctrl-d", "vim-ctrl-u", "vim-ctrl-f", "vim-ctrl-b":
            return .scroll
        default:
            return action.mode == .hyper ? .other : .other
        }
    }

    /// Group Space-layer actions for the cheat sheet (stable order).
    static func grouped(_ actions: [HyperAction]) -> [(SpaceNavGroup, [HyperAction])] {
        let space = actions.filter { $0.mode != .hyper }
        return SpaceNavGroup.allCases.compactMap { group in
            let items = space.filter { Self.group(for: $0) == group }
            return items.isEmpty ? nil : (group, items)
        }
    }
}
