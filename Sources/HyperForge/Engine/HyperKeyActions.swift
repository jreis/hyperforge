// HyperKeyActions.swift
// Hyper (F18 / Caps) + key dispatch. Behavior matches hyperkey.swift handleHyperKey.
// Not MainActor-isolated so the CGEvent tap can call it; AppKit hops are explicit.

import AppKit
import CoreGraphics
import Foundation
import HyperForgeKit

enum HyperKeyActions {
    /// Returns true if the key was handled.
    /// - Parameter hyperConsumesShift: true when Hyper itself is the 4-mod chord
    ///   (Ctrl+Opt+Cmd+Shift). In that mode every Hyper key already has Shift,
    ///   so Hyper+⇧/ is indistinguishable from Hyper+/ — we treat `/` as help.
    static func handle(
        _ keyCode: CGKeyCode,
        enabledIDs: Set<String>?,
        shiftDown: Bool = false,
        hyperConsumesShift: Bool = false
    ) -> Bool {
        // Profile-level enable set (app overrides applied asynchronously via UI settings;
        // keep this path free of MainActor.assumeIsolated — it crashes under Swift 6).
        func allowed(_ id: String) -> Bool {
            HyperChordRouting.isAllowed(actionID: id, enabledIDs: enabledIDs)
        }

        // Explicit extra Shift (F18 Hyper + Shift) — not the same as 4-mod Hyper.
        let extraShift = HyperChordRouting.extraShift(
            shiftDown: shiftDown,
            hyperConsumesShift: hyperConsumesShift
        )

        switch keyCode {
        case KeyCode.leftArrow where allowed("win-left"):
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 0.5, h: 1) }
            return true
        case KeyCode.rightArrow where allowed("win-right"):
            onMain { WindowManager.shared.snap(x: 0.5, y: 0, w: 0.5, h: 1) }
            return true
        case KeyCode.upArrow where allowed("win-top"):
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 1, h: 0.5) }
            return true
        case KeyCode.downArrow where allowed("win-bottom"):
            onMain { WindowManager.shared.snap(x: 0, y: 0.5, w: 1, h: 0.5) }
            return true
        case KeyCode.return:
            if shiftDown, allowed("win-tile-all") {
                onMain { _ = WindowManager.shared.tileAllVisible() }
                return true
            }
            if allowed("win-max") {
                onMain { WindowManager.shared.snap(x: 0, y: 0, w: 1, h: 1) }
                return true
            }
            return false
        case KeyCode.six where allowed("win-tile-all"):
            onMain { _ = WindowManager.shared.tileAllVisible() }
            return true
        case KeyCode.c:
            if shiftDown, allowed("finder-copy-text") {
                onMain { FinderActions.copySelectedFileContents() }
                return true
            }
            if allowed("win-center") {
                onMain { WindowManager.shared.center() }
                return true
            }
            return false
        case KeyCode.m:
            if shiftDown, allowed("sys-copy-hostname") {
                DispatchQueue.global().async { SystemActions.copyHostname() }
                return true
            }
            if allowed("win-next-screen") {
                onMain { WindowManager.shared.moveToNextScreen() }
                return true
            }
            return false
        case KeyCode.z where allowed("win-undo"):
            onMain {
                if !WindowManager.shared.undo() {
                    Banner.show("No previous position saved")
                }
            }
            return true
        case KeyCode.seven where allowed("win-tl"):
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 0.5, h: 0.5) }
            return true
        case KeyCode.eight where allowed("win-tr"):
            onMain { WindowManager.shared.snap(x: 0.5, y: 0, w: 0.5, h: 0.5) }
            return true
        case KeyCode.nine where allowed("win-bl"):
            onMain { WindowManager.shared.snap(x: 0, y: 0.5, w: 0.5, h: 0.5) }
            return true
        case KeyCode.zero where allowed("win-br"):
            onMain { WindowManager.shared.snap(x: 0.5, y: 0.5, w: 0.5, h: 0.5) }
            return true

        case KeyCode.tab where allowed("app-toggle"):
            onMain { AppLauncher.shared.toggleLastApp() }
            return true

        case KeyCode.h where allowed("scroll-left"):
            EventSynthesizer.postScrollHorizontal(dx: 200)
            return true
        case KeyCode.j where allowed("scroll-down"):
            EventSynthesizer.postScroll(dy: -200)
            return true
        case KeyCode.k where allowed("prod-keepalive"):
            onMain { KeepAliveService.shared.toggle() }
            return true
        case KeyCode.l where allowed("scroll-right"):
            EventSynthesizer.postScrollHorizontal(dx: -200)
            return true

        case KeyCode.one where allowed("app-chrome"):
            onMain { AppLauncher.shared.launchFocusOrMinimize("Google Chrome") }
            return true
        case KeyCode.two where allowed("app-zed"):
            onMain { AppLauncher.shared.launchFocusOrMinimize("Zed") }
            return true
        case KeyCode.three where allowed("app-teams"):
            onMain { AppLauncher.shared.launchFocusOrMinimize("Microsoft Teams") }
            return true
        case KeyCode.four where allowed("app-vscode"):
            onMain { AppLauncher.shared.launchFocusOrMinimize("Visual Studio Code") }
            return true
        case KeyCode.five where allowed("app-zoom"):
            onMain { AppLauncher.shared.launchFocusOrMinimize("Zoom") }
            return true
        case KeyCode.t where allowed("app-iterm") || allowed("app-terminal-here"):
            // Hyper+T: new window · Hyper+⇧T: preferred terminal in Finder folder
            onMain { AppLauncher.shared.openTerminalSmart(inFinderFolder: shiftDown) }
            return true
        case KeyCode.f where allowed("app-finder"):
            if shiftDown, allowed("finder-open-editor") {
                onMain { FinderActions.openSelectionInEditor() }
            } else {
                onMain { AppLauncher.shared.openFinder() }
            }
            return true

        case KeyCode.s where allowed("prod-shell"):
            // Generic: focus preferred terminal (Settings → Apps)
            onMain { AppLauncher.shared.launchPreferredTerminal() }
            return true

        case KeyCode.n where allowed("prod-note"):
            DispatchQueue.global().async { QuickNote.capture() }
            return true

        case KeyCode.d where allowed("prod-today"):
            DispatchQueue.global().async { QuickNote.openToday() }
            return true

        case KeyCode.period where allowed("prod-date"):
            SystemActions.typeDateISO()
            return true

        case KeyCode.i where allowed("sys-net"):
            if shiftDown {
                DispatchQueue.global().async { SystemActions.copyPrimaryIP() }
            } else {
                DispatchQueue.global().async { SystemActions.showNetworkInfo() }
            }
            return true

        case KeyCode.u where allowed("clip-url"):
            SystemActions.openClipboardURL()
            return true

        case KeyCode.x where allowed("win-close"):
            // Post a full ⌘W chord; pass-through lets it reach the front app
            // even while Hyper (F18) is still held.
            EventSynthesizer.postCommandKey(KeyCode.w)
            return true

        case KeyCode.semicolon where allowed("sys-mic"):
            DispatchQueue.global().async { SystemActions.toggleMic() }
            return true

        case KeyCode.v where allowed("clip-nvim") || allowed("clip-paste-menu"):
            if shiftDown {
                // Hyper+⇧V — paste transform menu (AHK ^+!v)
                onMain { PasteTransformService.showMenu() }
            } else {
                DispatchQueue.global().async { SystemActions.openClipboardInNvim() }
            }
            return true

        case KeyCode.p where allowed("clip-image"):
            onMain { ClipboardImagePreview.shared.showManual() }
            return true

        case KeyCode.o where allowed("prod-pomodoro"):
            onMain { PomodoroService.shared.toggle() }
            return true

        case KeyCode.e where allowed("clip-plain"):
            onMain { ClipboardService.shared.pasteAsPlainText() }
            return true

        case KeyCode.g where allowed("prod-google"):
            DispatchQueue.global().async { SystemActions.googleSelection() }
            return true

        case KeyCode.escape where allowed("sys-lock"):
            SystemActions.lockScreen()
            return true

        case KeyCode.r where allowed("sys-reload"):
            Banner.show("HyperForge engine reloading…")
            DispatchQueue.main.async { HyperKeyEngine.shared.restart() }
            return true

        case KeyCode.space where allowed("sys-command-bar"):
            onMain {
                AppState.shared.commandBarVisible = true
                AppState.shared.openMainWindow()
            }
            return true

        // Hyper + , → show dashboard (also Karabiner → F20 for reliability)
        case KeyCode.comma where allowed("sys-dashboard"):
            onMain { AppState.shared.openMainWindow() }
            return true

        // Help / cheat sheet
        // - F18 Hyper + ⇧ + /  → cheat sheet (extraShift)
        // - 4-mod Hyper + /    → cheat sheet (shift is always part of Hyper)
        // - F18 Hyper + /      → link hints
        // - Hyper + `          → cheat sheet (always, any Hyper style)
        case KeyCode.slash:
            switch HyperChordRouting.slashAction(
                shiftDown: shiftDown,
                hyperConsumesShift: hyperConsumesShift,
                linkHintsAllowed: allowed("sys-link-hints")
            ) {
            case .cheatSheet, .cheatSheetFallback:
                onMain {
                    AppState.shared.showCheatSheet()
                    HyperLog.event(
                        "Cheat sheet via slash extraShift=\(extraShift) quad=\(hyperConsumesShift)"
                    )
                }
                return true
            case .linkHints:
                onMain { LinkHintService.shared.toggle() }
                return true
            }

        case KeyCode.grave:
            // Hyper + ` — reliable help chord for every Hyper style
            onMain {
                AppState.shared.showCheatSheet()
                HyperLog.event("Cheat sheet via Hyper+`")
            }
            return true

        case KeyCode.a where allowed("win-always-on-top"):
            onMain { WindowManager.shared.toggleAlwaysOnTop() }
            return true

        case KeyCode.b where allowed("win-minimize"):
            onMain { WindowManager.shared.minimizeFront() }
            return true

        case KeyCode.q where allowed("sys-quick-menu"):
            onMain { QuickMenuService.show() }
            return true

        case KeyCode.y where allowed("sys-recipes"):
            onMain { AXRecipeStore.shared.showMenu() }
            return true

        case KeyCode.w where shiftDown && allowed("sys-reverse-dns"):
            DispatchQueue.global().async { SystemActions.reverseDNSClipboard() }
            return true

        default:
            return false
        }
    }

    /// Fire an action by catalog id (dashboard live test / command bar).
    @MainActor
    static func perform(actionID: String) {
        // Synthetic meta-actions not always in catalog paths
        switch actionID {
        case "sys-command-bar":
            AppState.shared.commandBarVisible = true
            AppState.shared.openMainWindow()
            Banner.show("✓ Command Bar")
            return
        case "sys-link-hints":
            LinkHintService.shared.toggle()
            return
        case "sys-cheatsheet":
            AppState.shared.showCheatSheet()
            return
        case "clip-paste-menu":
            PasteTransformService.showMenu()
            return
        case "sys-quick-menu":
            QuickMenuService.show()
            return
        case "sys-recipes":
            AXRecipeStore.shared.showMenu()
            return
        case "win-always-on-top":
            WindowManager.shared.toggleAlwaysOnTop()
            return
        case "win-minimize":
            WindowManager.shared.minimizeFront()
            return
        case "win-tile-all":
            _ = WindowManager.shared.tileAllVisible()
            return
        case "app-terminal-here":
            FinderActions.terminalInFrontFolder()
            return
        case "finder-copy-text":
            FinderActions.copySelectedFileContents()
            return
        case "finder-open-editor":
            FinderActions.openSelectionInEditor()
            return
        case "sys-copy-ip":
            SystemActions.copyPrimaryIP()
            return
        case "sys-copy-hostname":
            SystemActions.copyHostname()
            return
        case "sys-reverse-dns":
            SystemActions.reverseDNSClipboard()
            return
        default:
            break
        }

        guard let action = ActionCatalog.defaults.first(where: { $0.id == actionID }) else {
            Banner.show("Unknown action")
            return
        }
        switch actionID {
        case "win-hide-others":
            AppLauncher.shared.hideOthers()
        case "scroll-up":
            EventSynthesizer.postScroll(dy: 200)
        case "prod-keepalive":
            KeepAliveService.shared.toggle()
        case "sys-link-hints":
            LinkHintService.shared.toggle()
        case "sys-command-bar":
            AppState.shared.commandBarVisible = true
            AppState.shared.openMainWindow()
        case "sys-cheatsheet":
            AppState.shared.showCheatSheet()
        case "clip-paste-menu":
            PasteTransformService.showMenu()
        case "sys-quick-menu":
            QuickMenuService.show()
        case "sys-recipes":
            AXRecipeStore.shared.showMenu()
        default:
            if action.mode == .hyper {
                _ = handle(CGKeyCode(action.keyCode), enabledIDs: nil)
            } else {
                let shift = action.mode == .vimShift
                let ctrl = action.mode == .vimCtrl
                VimNavigation.shared.setActive(true)
                _ = VimNavigation.shared.handle(
                    keyCode: CGKeyCode(action.keyCode),
                    shiftDown: shift,
                    ctrlDown: ctrl
                )
                VimNavigation.shared.setActive(false)
            }
        }
        Banner.show("✓ \(action.title)")
    }

    /// Hop to main without MainActor.assumeIsolated (crashes under MenuBarExtra / Swift 6).
    private static func onMain(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            Task { @MainActor in
                work()
            }
        }
    }
}
