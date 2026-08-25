// AppState.swift
// Root observable coordination for the SwiftUI shell.

import AppKit
import Foundation
import HyperForgeKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedSidebar: SidebarItem = .dashboard
    @Published var showOnboarding: Bool
    @Published var isAccessibilityTrusted: Bool = PermissionsService.isTrusted
    @Published var liveTestMode = false
    @Published var searchText = ""
    @Published var commandBarVisible = false
    @Published var cheatSheetVisible = false

    @AppStorage("hf.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hf.launchEngineOnStart") var launchEngineOnStart = true
    @AppStorage("hf.showDashboardOnStartup") var showDashboardOnStartup = false
    @AppStorage("hf.autoKeepAlive") var autoKeepAlive = false
    @AppStorage("hf.menuBarOnly") var menuBarOnly = true

    /// Re-read UserDefaults into @AppStorage after config import.
    func syncPrefsFromDefaults() {
        let d = UserDefaults.standard
        if d.object(forKey: "hf.launchEngineOnStart") != nil {
            launchEngineOnStart = d.bool(forKey: "hf.launchEngineOnStart")
        }
        if d.object(forKey: "hf.showDashboardOnStartup") != nil {
            showDashboardOnStartup = d.bool(forKey: "hf.showDashboardOnStartup")
        }
        if d.object(forKey: "hf.autoKeepAlive") != nil {
            autoKeepAlive = d.bool(forKey: "hf.autoKeepAlive")
        }
        if d.object(forKey: "hf.menuBarOnly") != nil {
            menuBarOnly = d.bool(forKey: "hf.menuBarOnly")
        }
        objectWillChange.send()
    }

    let engine = HyperKeyEngine.shared
    let profiles = ProfileStore.shared
    let karabiner = KarabinerService.shared
    let ollama = OllamaClient.shared
    let autoTriggers = AutoTriggerService.shared
    let appOverrides = AppOverrideStore.shared
    let demoExport = DemoExportService.shared
    let linkHints = LinkHintService.shared

    private var trustTimer: Timer?
    /// True only during cold-start; cleared when the user opens the dashboard.
    private var suppressingDashboardOnStartup = false
    /// Swallow the synthetic `applicationShouldHandleReopen` that accompanies launch.
    private var consumeLaunchReopen = false

    private init() {
        showOnboarding = !UserDefaults.standard.bool(forKey: "hf.hasCompletedOnboarding")
    }

    func bootstrap() {
        Self.logCatalogPolicyIfNeeded()
        EscapeCoordinator.shared.start()
        // Force-load snippets into SnippetEngine before any typing (UI visit used to be required).
        _ = SnippetStore.shared
        // Space-nav block list + frontmost tracking (TouchCursor layer).
        _ = SpaceNavStore.shared
        SpaceNavStore.shared.refreshFrontmost()
        profiles.applyToEngine()
        if launchEngineOnStart {
            engine.start()
        }
        if autoKeepAlive && !KeepAliveService.shared.isActive {
            KeepAliveService.shared.toggle()
        }
        autoTriggers.start()
        WindowMemoryStore.shared.start()
        Task { await ollama.ping() }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isAccessibilityTrusted = PermissionsService.isTrusted
            }
        }
        applyStartupWindowVisibility()
    }

    /// Honor “Show dashboard on startup”. Onboarding always shows the window.
    private func applyStartupWindowVisibility() {
        if showOnboarding || showDashboardOnStartup {
            suppressingDashboardOnStartup = false
            consumeLaunchReopen = false
            DashboardLaunchGate.allowShowing()
            openMainWindow()
            return
        }
        suppressingDashboardOnStartup = true
        consumeLaunchReopen = true
        // Dashboard is AppKit-hosted and is not created until openMainWindow().
    }

    /// Finder / Dock reopen of a running instance. Not the same as cold start.
    func handleReopenRequest() {
        if consumeLaunchReopen {
            consumeLaunchReopen = false
            return
        }
        if suppressingDashboardOnStartup { return }
        openMainWindow()
    }

    /// Soft guard: log if default catalog regresses (PII / missing core IDs).
    private static func logCatalogPolicyIfNeeded() {
        let ids = ActionCatalog.defaults.map(\.id)
        let blob = ActionCatalog.defaults
            .map { "\($0.id) \($0.title) \($0.detail)" }
            .joined(separator: "\n")
        let errors = CatalogPolicy.validate(actionIDs: ids, searchableBlob: blob)
        for err in errors {
            HyperLog.event("CatalogPolicy: \(err)")
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
        engine.start()
    }

    /// Bring the main dashboard forward (menu bar / Hyper+, / ⌘⇧D).
    func openMainWindow() {
        suppressingDashboardOnStartup = false
        DashboardLaunchGate.allowShowing()
        commandBarVisible = false
        selectedSidebar = .dashboard

        // Leave accessory-only mode so the window can become key.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DashboardWindowController.shared.show()
    }

    /// Hide the main dashboard (Esc). Keeps the engine / menu bar running.
    func closeMainWindow() {
        commandBarVisible = false
        DashboardWindowController.shared.hide()
        restoreAccessoryIfSafe()
        // Esc after startup dashboard left Caps Lock / menu flags sticky for some users
        // (Hyper+V then typed a capital V). Reset that state without killing a held Caps.
        HyperKeyEngine.shared.prepareAfterUIDismiss(reason: "closeMainWindow")
        Banner.show(
            "Dashboard hidden",
            subtitle: "Hyper + ,  to show again",
            style: .info,
            symbol: "eye.slash"
        )
    }

    /// Escape from dashboard context — goes through the global priority stack.
    func handleDashboardEscape() {
        if showOnboarding {
            // Don't skip onboarding with Esc — use Continue / Enter HyperForge
            return
        }
        _ = EscapeCoordinator.shared.handleEscape()
    }

    /// Tag the key dashboard window once SwiftUI has created it.
    func registerDashboardWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(
            DashboardWindowPolicy.dashboardIdentifier
        )
        if window.title.isEmpty || window.title == "main" {
            window.title = "HyperForge"
        }
        window.isReleasedWhenClosed = false
    }

    private func restoreAccessoryIfSafe() {
        guard menuBarOnly else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Don't drop to accessory while cheat sheet (or another UI) is up.
            if CheatSheetCommands.isVisible { return }
            if !Self.dashboardWindows().filter(\.isVisible).isEmpty { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Windows that look like the main HyperForge dashboard (not toasts / cheat sheet).
    /// Includes `orderOut` (hidden) windows so Esc-hide can reopen.
    static func dashboardWindows() -> [NSWindow] {
        // Prefer stable id first (set by registerDashboardWindow).
        let byID = NSApp.windows.filter {
            $0.identifier?.rawValue == DashboardWindowPolicy.dashboardIdentifier
        }
        if !byID.isEmpty { return byID }

        return NSApp.windows.filter { w in
            // Never treat the menu bar popover as the dashboard.
            if w.frame.width < 500 || w.frame.height < 300 { return false }
            let traits = WindowTraits(
                title: w.title,
                width: w.frame.width,
                height: w.frame.height,
                isBorderless: w.styleMask.contains(.borderless),
                isNormalOrFloatingLevel: w.level == .normal || w.level == .floating,
                identifier: w.identifier?.rawValue
            )
            return DashboardWindowPolicy.isDashboard(traits)
        }
    }

    /// Show/hide keybinding cheat sheet.
    /// Safe from MenuBarExtra buttons: only posts work to the main queue
    /// (does not use MainActor.assumeIsolated).
    nonisolated func showCheatSheet() {
        CheatSheetCommands.toggle()
    }

    nonisolated func hideCheatSheet() {
        CheatSheetCommands.hide()
    }

    /// Safe from any thread (event tap, MenuBarExtra). Prefer `AppCommands`.
    nonisolated func requestOpenMainWindow() {
        AppCommands.openMainWindow()
    }

    nonisolated func requestCloseMainWindow() {
        AppCommands.closeMainWindow()
    }
}

/// Nonisolated UI entry points — never touch `@MainActor` singletons from the
/// CGEvent tap or MenuBarExtra without hopping here first.
enum AppCommands {
    nonisolated static func openMainWindow() {
        DispatchQueue.main.async {
            Task { @MainActor in
                AppState.shared.openMainWindow()
            }
        }
    }

    nonisolated static func closeMainWindow() {
        DispatchQueue.main.async {
            Task { @MainActor in
                AppState.shared.closeMainWindow()
            }
        }
    }

    nonisolated static func showCheatSheet() {
        CheatSheetCommands.show()
    }

    nonisolated static func toggleCheatSheet() {
        CheatSheetCommands.toggle()
    }
}

extension Notification.Name {
    static let hfOpenMainWindow = Notification.Name("hfOpenMainWindow")
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Hyper Key"
    case doctor = "Doctor"
    case checklist = "Checklist"
    case profiles = "Profiles"
    case workspaces = "Workspaces"
    case snippets = "Snippets"
    case recipes = "AX Recipes"
    case scripts = "Scripts"
    case triggers = "Auto-Triggers"
    case overrides = "App Overrides"
    case karabiner = "Karabiner"
    case clipboard = "Clipboard"
    case demo = "Demo Export"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "keyboard.fill"
        case .doctor: return "stethoscope"
        case .checklist: return "checklist"
        case .profiles: return "person.2.crop.square.stack"
        case .workspaces: return "rectangle.3.group"
        case .snippets: return "text.badge.plus"
        case .recipes: return "wand.and.stars"
        case .scripts: return "curlybraces"
        case .triggers: return "bolt.badge.automatic"
        case .overrides: return "app.badge.checkmark"
        case .karabiner: return "switch.2"
        case .clipboard: return "doc.on.clipboard"
        case .demo: return "square.and.arrow.up.on.square"
        case .settings: return "gearshape"
        }
    }
}
