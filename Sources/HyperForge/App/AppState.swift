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
    @AppStorage("hf.autoKeepAlive") var autoKeepAlive = false
    @AppStorage("hf.menuBarOnly") var menuBarOnly = true

    let engine = HyperKeyEngine.shared
    let profiles = ProfileStore.shared
    let karabiner = KarabinerService.shared
    let ollama = OllamaClient.shared
    let autoTriggers = AutoTriggerService.shared
    let appOverrides = AppOverrideStore.shared
    let demoExport = DemoExportService.shared
    let linkHints = LinkHintService.shared

    private var trustTimer: Timer?
    /// Retries after posting openWindow when the dashboard was fully destroyed.
    private var openRetryWorkItems: [DispatchWorkItem] = []

    private init() {
        showOnboarding = !UserDefaults.standard.bool(forKey: "hf.hasCompletedOnboarding")
    }

    func bootstrap() {
        Self.logCatalogPolicyIfNeeded()
        profiles.applyToEngine()
        if launchEngineOnStart {
            engine.start()
        }
        if autoKeepAlive && !KeepAliveService.shared.isActive {
            KeepAliveService.shared.toggle()
        }
        autoTriggers.start()
        Task { await ollama.ping() }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isAccessibilityTrusted = PermissionsService.isTrusted
            }
        }
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
        cancelOpenRetries()
        commandBarVisible = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if presentExistingDashboard() {
            return
        }

        // Window was fully closed — ask the App scene to recreate it.
        NotificationCenter.default.post(name: .hfOpenMainWindow, object: nil)

        // SwiftUI openWindow can take a beat; retry a few times rather than one 150ms hope.
        scheduleOpenRetries(delays: [0.05, 0.15, 0.35, 0.7, 1.2])
    }

    /// Hide the main dashboard (Esc). Keeps the engine / menu bar running.
    func closeMainWindow() {
        cancelOpenRetries()
        commandBarVisible = false
        for window in Self.dashboardWindows() {
            // Prefer hide over close so SwiftUI WindowGroup state is easier to re-show.
            window.orderOut(nil)
        }
        restoreAccessoryIfSafe()
        Banner.show(
            "Dashboard hidden",
            subtitle: "Hyper + ,  to show again",
            style: .info,
            symbol: "eye.slash"
        )
    }

    /// Handle Escape when the dashboard is key.
    func handleDashboardEscape() {
        if commandBarVisible {
            commandBarVisible = false
            return
        }
        if showOnboarding {
            // Don't skip onboarding with Esc — use Continue / Enter HyperForge
            return
        }
        closeMainWindow()
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

    // MARK: - Window presentation

    @discardableResult
    private func presentExistingDashboard() -> Bool {
        let windows = Self.dashboardWindows()
        guard let window = windows.first else { return false }
        // If we somehow have multiples after openWindow spam, keep one frontmost.
        for extra in windows.dropFirst() {
            extra.orderOut(nil)
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func scheduleOpenRetries(delays: [TimeInterval]) {
        for delay in delays {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.presentExistingDashboard() {
                    self.cancelOpenRetries()
                } else {
                    // Nudge SwiftUI again if still missing.
                    NotificationCenter.default.post(name: .hfOpenMainWindow, object: nil)
                }
            }
            openRetryWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelOpenRetries() {
        openRetryWorkItems.forEach { $0.cancel() }
        openRetryWorkItems.removeAll()
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
    static func dashboardWindows() -> [NSWindow] {
        NSApp.windows.filter { w in
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
    case profiles = "Profiles"
    case workspaces = "Workspaces"
    case snippets = "Snippets"
    case recipes = "AX Recipes"
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
        case .profiles: return "person.2.crop.square.stack"
        case .workspaces: return "rectangle.3.group"
        case .snippets: return "text.badge.plus"
        case .recipes: return "wand.and.stars"
        case .triggers: return "bolt.badge.automatic"
        case .overrides: return "app.badge.checkmark"
        case .karabiner: return "switch.2"
        case .clipboard: return "doc.on.clipboard"
        case .demo: return "square.and.arrow.up.on.square"
        case .settings: return "gearshape"
        }
    }
}
