// QuickMenuService.swift
// Cursor-local power menu — AHK XButton2 / ShowQuickMenu energy.

import AppKit
import Foundation

@MainActor
enum QuickMenuService {
    static func show() {
        let menu = NSMenu(title: "HyperForge Quick Menu")

        func item(_ title: String, _ symbol: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = QuickMenuTarget.shared
            i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return i
        }

        menu.addItem(item("Paste transforms…", "doc.on.clipboard", #selector(QuickMenuTarget.pasteTransforms)))
        menu.addItem(item("Run Shortcut…", "sparkles.rectangle.stack", #selector(QuickMenuTarget.shortcuts)))
        menu.addItem(item("AX Recipes…", "wand.and.stars", #selector(QuickMenuTarget.recipes)))
        menu.addItem(item("Command bar", "sparkles", #selector(QuickMenuTarget.commandBar)))
        menu.addItem(item("Cheat sheet", "keyboard", #selector(QuickMenuTarget.cheatSheet)))
        menu.addItem(.separator())
        menu.addItem(item("Tile all windows", "rectangle.split.3x3", #selector(QuickMenuTarget.tileAll)))
        menu.addItem(item("Always on top", "pin", #selector(QuickMenuTarget.alwaysOnTop)))
        menu.addItem(item("Minimize window", "minus.rectangle", #selector(QuickMenuTarget.minimize)))
        menu.addItem(item("Terminal here (Finder)", "terminal", #selector(QuickMenuTarget.terminalHere)))
        menu.addItem(item("Copy Finder file text", "doc.text", #selector(QuickMenuTarget.copyFileText)))
        menu.addItem(item("Open selection in editor", "chevron.left.forwardslash.chevron.right", #selector(QuickMenuTarget.openInEditor)))
        menu.addItem(.separator())
        menu.addItem(item("Copy IP address", "network", #selector(QuickMenuTarget.copyIP)))
        menu.addItem(item("Copy hostname", "desktopcomputer", #selector(QuickMenuTarget.copyHostname)))
        menu.addItem(item("Link hints", "link.circle", #selector(QuickMenuTarget.linkHints)))
        menu.addItem(item("Pin screen region", "crop", #selector(QuickMenuTarget.regionPin)))
        menu.addItem(item("Copy top pin image", "doc.on.clipboard", #selector(QuickMenuTarget.copyTopPin)))
        menu.addItem(item("Clipboard image pin", "photo", #selector(QuickMenuTarget.clipboardImage)))
        menu.addItem(.separator())
        menu.addItem(item("Open dashboard", "rectangle.center.inset.filled", #selector(QuickMenuTarget.dashboard)))

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

@MainActor
final class QuickMenuTarget: NSObject {
    static let shared = QuickMenuTarget()

    @objc func pasteTransforms() { PasteTransformService.showMenu() }
    @objc func shortcuts() { ShortcutsService.showMenu() }
    @objc func recipes() { AXRecipeStore.shared.showMenu() }
    @objc func commandBar() {
        AppState.shared.commandBarVisible = true
        AppState.shared.openMainWindow()
    }
    @objc func cheatSheet() { CheatSheetCommands.toggle() }
    @objc func tileAll() { _ = WindowManager.shared.tileAllVisible() }
    @objc func alwaysOnTop() { WindowManager.shared.toggleAlwaysOnTop() }
    @objc func minimize() { WindowManager.shared.minimizeFront() }
    @objc func terminalHere() { FinderActions.terminalInFrontFolder() }
    @objc func copyFileText() { FinderActions.copySelectedFileContents() }
    @objc func openInEditor() { FinderActions.openSelectionInEditor() }
    @objc func copyIP() { SystemActions.copyPrimaryIP() }
    @objc func copyHostname() { SystemActions.copyHostname() }
    @objc func linkHints() { LinkHintService.shared.toggle() }
    @objc func regionPin() { RegionPinService.shared.beginSelection() }
    @objc func copyTopPin() {
        if RegionPinService.shared.copyTopPinToClipboard() { return }
        Banner.show(
            "No pin to copy",
            subtitle: "Hyper+P to pin a region first",
            style: .warning,
            symbol: "crop"
        )
    }
    @objc func clipboardImage() { ClipboardImagePreview.shared.showManual() }
    @objc func dashboard() { AppState.shared.openMainWindow() }
}
