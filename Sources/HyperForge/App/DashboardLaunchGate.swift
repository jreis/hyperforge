// DashboardLaunchGate.swift
// Hide the dashboard before the first paint when startup-show is off.

import AppKit

/// Process-wide, readable from NSView without hopping to MainActor.
enum DashboardLaunchGate {
    /// True until the user (or startup setting) asks to show the dashboard.
    static var suppressVisibleDashboard: Bool = {
        let d = UserDefaults.standard
        let onboarded = d.bool(forKey: "hf.hasCompletedOnboarding")
        let show = d.object(forKey: "hf.showDashboardOnStartup") as? Bool ?? false
        return onboarded && !show
    }()

    static func allowShowing() {
        suppressVisibleDashboard = false
    }

    @discardableResult
    static func hideIfNeeded(_ window: NSWindow) -> Bool {
        guard suppressVisibleDashboard else { return false }
        let frame = window.frame
        guard frame.width >= 500, frame.height >= 300 else { return false }
        if window.styleMask.contains(.borderless) { return false }
        window.animationBehavior = .none
        window.alphaValue = 0
        window.orderOut(nil)
        return true
    }

    static func restoreAlpha(_ window: NSWindow) {
        window.alphaValue = 1
        window.animationBehavior = .default
    }
}
