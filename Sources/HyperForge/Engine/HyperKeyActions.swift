// HyperKeyActions.swift
// Hyper (F18 / Caps) + key dispatch. Routing is pure (`HyperBindingResolver`);
// this file only performs side effects.

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
        let route = HyperBindingResolver.resolve(
            keyCode: UInt16(keyCode),
            shiftDown: shiftDown,
            hyperConsumesShift: hyperConsumesShift,
            enabledIDs: enabledIDs
        )
        switch route {
        case .unhandled:
            return false
        case .action(let id):
            executeRouted(actionID: id)
            return true
        }
    }

    /// Side effects for a resolved Hyper action id (engine path).
    static func executeRouted(actionID: String) {
        switch actionID {
        case "win-left":
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 0.5, h: 1) }
        case "win-right":
            onMain { WindowManager.shared.snap(x: 0.5, y: 0, w: 0.5, h: 1) }
        case "win-top":
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 1, h: 0.5) }
        case "win-bottom":
            onMain { WindowManager.shared.snap(x: 0, y: 0.5, w: 1, h: 0.5) }
        case "win-max":
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 1, h: 1) }
        case "win-tile-all":
            onMain { _ = WindowManager.shared.tileAllVisible() }
        case "win-center":
            onMain { WindowManager.shared.center() }
        case "win-next-screen":
            onMain { WindowManager.shared.moveToNextScreen() }
        case "win-undo":
            // undo() always shows its own rich HUD (success or empty)
            onMain { _ = WindowManager.shared.undo() }
        case "win-tl":
            onMain { WindowManager.shared.snap(x: 0, y: 0, w: 0.5, h: 0.5) }
        case "win-tr":
            onMain { WindowManager.shared.snap(x: 0.5, y: 0, w: 0.5, h: 0.5) }
        case "win-bl":
            onMain { WindowManager.shared.snap(x: 0, y: 0.5, w: 0.5, h: 0.5) }
        case "win-br":
            onMain { WindowManager.shared.snap(x: 0.5, y: 0.5, w: 0.5, h: 0.5) }
        case "win-close":
            EventSynthesizer.postCommandKey(KeyCode.w)
        case "win-always-on-top":
            onMain { WindowManager.shared.toggleAlwaysOnTop() }
        case "win-minimize":
            onMain { WindowManager.shared.minimizeFront() }
        case "scroll-left":
            EventSynthesizer.postScrollHorizontal(dx: 200)
        case "scroll-down":
            EventSynthesizer.postScroll(dy: -200)
        case "scroll-right":
            EventSynthesizer.postScrollHorizontal(dx: -200)
        case "prod-keepalive":
            onMain { KeepAliveService.shared.toggle() }
        case "app-chrome":
            onMain { AppLauncher.shared.launchFocusOrMinimize("Google Chrome") }
        case "app-zed":
            onMain { AppLauncher.shared.launchFocusOrMinimize("Zed") }
        case "app-teams":
            onMain { AppLauncher.shared.launchFocusOrMinimize("Microsoft Teams") }
        case "app-vscode":
            onMain { AppLauncher.shared.launchFocusOrMinimize("Visual Studio Code") }
        case "app-zoom":
            onMain { AppLauncher.shared.launchFocusOrMinimize("Zoom") }
        case "app-iterm":
            onMain { AppLauncher.shared.openTerminalSmart(inFinderFolder: false) }
        case "app-terminal-here":
            onMain { AppLauncher.shared.openTerminalSmart(inFinderFolder: true) }
        case "app-finder":
            onMain { AppLauncher.shared.openFinder() }
        case "finder-open-editor":
            onMain { FinderActions.openSelectionInEditor() }
        case "finder-copy-text":
            onMain { FinderActions.copySelectedFileContents() }
        case "app-toggle":
            onMain { AppLauncher.shared.toggleLastApp() }
        case "prod-shell":
            onMain { AppLauncher.shared.launchPreferredTerminal() }
        case "prod-note":
            DispatchQueue.global().async { QuickNote.capture() }
        case "prod-today":
            DispatchQueue.global().async { QuickNote.openToday() }
        case "prod-date":
            SystemActions.typeDateISO()
        case "prod-pomodoro":
            onMain { PomodoroService.shared.toggle() }
        case "prod-google":
            DispatchQueue.global().async { SystemActions.googleSelection() }
        case "sys-net":
            DispatchQueue.global().async { SystemActions.showNetworkInfo() }
        case "sys-copy-ip":
            DispatchQueue.global().async { SystemActions.copyPrimaryIP() }
        case "sys-copy-hostname":
            DispatchQueue.global().async { SystemActions.copyHostname() }
        case "sys-reverse-dns":
            DispatchQueue.global().async { SystemActions.reverseDNSClipboard() }
        case "clip-url":
            SystemActions.openClipboardURL()
        case "clip-plain":
            onMain { ClipboardService.shared.pasteAsPlainText() }
        case "clip-nvim":
            DispatchQueue.global().async { SystemActions.openClipboardInNvim() }
        case "clip-paste-menu":
            onMain { PasteTransformService.showMenu() }
        case "clip-region-pin":
            onMain { RegionPinService.shared.beginSelection() }
        case "clip-image":
            onMain { ClipboardImagePreview.shared.showManual() }
        case "sys-mic":
            DispatchQueue.global().async { SystemActions.toggleMic() }
        case "sys-lock":
            SystemActions.lockScreen()
        case "sys-reload":
            Banner.show("HyperForge engine reloading…")
            DispatchQueue.main.async { HyperKeyEngine.shared.restart() }
        case "sys-command-bar":
            onMain {
                AppState.shared.commandBarVisible = true
                AppState.shared.openMainWindow()
            }
        case "sys-dashboard":
            onMain { AppState.shared.openMainWindow() }
        case "sys-cheatsheet":
            onMain {
                AppState.shared.showCheatSheet()
                HyperLog.event("Cheat sheet via routed binding")
            }
        case "sys-link-hints":
            onMain { LinkHintService.shared.toggle() }
        case "sys-quick-menu":
            onMain { QuickMenuService.show() }
        case "sys-recipes":
            onMain { AXRecipeStore.shared.showMenu() }
        case "sys-shortcuts":
            onMain { ShortcutsService.showMenu() }
        default:
            HyperLog.event("executeRouted unknown id=\(actionID)")
        }
    }

    /// Fire an action by catalog id (dashboard live test / command bar / checklist).
    @MainActor
    static func perform(actionID: String) {
        // Prefer explicit side-effect path when we know the id.
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
        case "clip-region-pin":
            RegionPinService.shared.beginSelection()
            return
        case "clip-image":
            ClipboardImagePreview.shared.showManual()
            return
        case "sys-quick-menu":
            QuickMenuService.show()
            return
        case "sys-recipes":
            AXRecipeStore.shared.showMenu()
            return
        case "sys-shortcuts":
            ShortcutsService.showMenu()
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
        case "win-hide-others":
            AppLauncher.shared.hideOthers()
            Banner.show("✓ Hide Other Apps")
            return
        case "scroll-up":
            EventSynthesizer.postScroll(dy: 200)
            Banner.show("✓ Scroll Up")
            return
        default:
            break
        }

        guard let action = ActionCatalog.defaults.first(where: { $0.id == actionID }) else {
            Banner.show("Unknown action")
            return
        }

        // Actions that already show a rich HUD — avoid a second toast.
        let hasOwnBanner: Set<String> = [
            "win-next-screen", "win-tile-all", "win-undo", "win-always-on-top",
            "win-minimize", "prod-keepalive", "clip-region-pin", "clip-image",
            "sys-dashboard", "sys-cheatsheet", "sys-command-bar", "sys-shortcuts",
        ]

        if action.mode == .hyper {
            // Direct execute avoids re-resolving keys that share a keycode with shift variants.
            if HyperBindingResolver.routedActionIDs.contains(actionID) {
                executeRouted(actionID: actionID)
            } else {
                _ = handle(CGKeyCode(action.keyCode), enabledIDs: nil)
            }
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
        if !hasOwnBanner.contains(actionID) {
            Banner.show(
                action.title,
                subtitle: action.shortcutDisplay,
                style: .success,
                symbol: action.symbol
            )
        }
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
