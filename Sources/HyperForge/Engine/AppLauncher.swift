// AppLauncher.swift
// Launch / focus / minimize cycle (AHK RunOrActivateOrMinimizeProgram) + app tracking.

import AppKit
import Foundation

@MainActor
final class AppLauncher {
    static let shared = AppLauncher()

    private(set) var lastActiveApp: NSRunningApplication?
    private(set) var secondLastActiveApp: NSRunningApplication?

    private init() {}

    /// Three-state cycle: launch → focus → minimize if already frontmost.
    func launchFocusOrMinimize(_ bundleIDOrName: String) {
        let running = NSWorkspace.shared.runningApplications
        let match: NSRunningApplication? =
            running.first(where: { $0.localizedName == bundleIDOrName })
            ?? (bundleIDOrName.contains(".")
                ? running.first(where: { $0.bundleIdentifier == bundleIDOrName })
                : nil)

        if let app = match {
            if app.isActive {
                app.hide()
                Banner.show("Minimized \(app.localizedName ?? bundleIDOrName)")
            } else {
                app.activate(options: [.activateAllWindows])
            }
            return
        }

        launchOrFocus(bundleIDOrName)
    }

    func launchOrFocus(_ bundleIDOrName: String) {
        let running = NSWorkspace.shared.runningApplications
        if let app = running.first(where: { $0.localizedName == bundleIDOrName }) {
            app.activate(options: [.activateAllWindows])
            return
        }
        if bundleIDOrName.contains("."),
           let app = running.first(where: { $0.bundleIdentifier == bundleIDOrName })
        {
            app.activate(options: [.activateAllWindows])
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        if bundleIDOrName.contains("."),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIDOrName)
        {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
            return
        }

        let fm = FileManager.default
        let appBundleName =
            bundleIDOrName.hasSuffix(".app") ? bundleIDOrName : "\(bundleIDOrName).app"
        let candidates = [
            "/Applications/\(appBundleName)",
            NSHomeDirectory() + "/Applications/\(appBundleName)",
        ]
        if let path = candidates.first(where: { fm.fileExists(atPath: $0) }) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: config
            ) { _, _ in }
        }
    }

    /// Preferred terminal (Ghostty / iTerm / Terminal / …).
    func launchPreferredTerminal() {
        TerminalPreference.shared.launchOrFocus()
    }

    func openPreferredTerminalWindow() {
        TerminalPreference.shared.openSmart()
    }

    /// Hyper+T: smart tab/window · Hyper+⇧T: terminal in Finder folder.
    func openTerminalSmart(inFinderFolder: Bool) {
        if inFinderFolder {
            FinderActions.terminalInFrontFolder()
        } else {
            TerminalPreference.shared.openSmart()
        }
    }

    // MARK: - Back-compat aliases

    func launchITerm2() { launchPreferredTerminal() }
    func openITermWindow() { openPreferredTerminalWindow() }
    func openITermSmart(inFinderFolder: Bool) { openTerminalSmart(inFinderFolder: inFinderFolder) }

    func openFinder() {
        if let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Finder"
        ).first {
            finder.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                EventSynthesizer.postKey(KeyCode.n, flags: .maskCommand)
            }
        } else if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Finder"
        ) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
    }

    func toggleLastApp() {
        guard let secondLast = secondLastActiveApp else {
            Banner.show("No previous app to switch to")
            return
        }
        secondLast.activate()
        swap(&lastActiveApp, &secondLastActiveApp)
    }

    func trackAppSwitch() {
        let current = NSWorkspace.shared.frontmostApplication
        if let current, current.bundleIdentifier != "com.apple.finder" {
            if lastActiveApp?.bundleIdentifier != current.bundleIdentifier {
                secondLastActiveApp = lastActiveApp
                lastActiveApp = current
            }
        }
    }

    func hideOthers() {
        for app in NSWorkspace.shared.runningApplications
        where app.isActive == false && app.activationPolicy == .regular {
            app.hide()
        }
    }
}
