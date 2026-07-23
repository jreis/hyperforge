// SingleInstance.swift
// Only one HyperForge process should own the event tap / menu bar.

import AppKit
import Foundation

enum SingleInstance {
    /// Posted by a secondary launch so the primary instance can show the dashboard.
    static let reopenNotification = Notification.Name("app.hyperforge.HyperForge.reopenRequest")

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "app.hyperforge.HyperForge"
    }

    /// Other running copies of this app (not us).
    static func otherInstances() -> [NSRunningApplication] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != myPID
        }
    }

    /// If another instance is already running: activate it, ask it to open the
    /// dashboard, and return `false` (this process should exit).
    /// Returns `true` if this process is the primary instance.
    @discardableResult
    static func claimPrimaryOrHandOff() -> Bool {
        guard let existing = otherInstances().first else {
            return true
        }

        // Wake the live app and request dashboard (menu bar tools stay running there).
        existing.activate(options: [.activateAllWindows])
        DistributedNotificationCenter.default().postNotificationName(
            reopenNotification,
            object: bundleID,
            userInfo: nil,
            deliverImmediately: true
        )
        HyperLog.event(
            "SingleInstance: hand-off to pid=\(existing.processIdentifier), exiting secondary"
        )
        return false
    }

    /// Primary instance listens for secondary launches / Dock reopen.
    @MainActor
    static func installPrimaryHandlers() {
        DistributedNotificationCenter.default().addObserver(
            forName: reopenNotification,
            object: nil,
            queue: .main
        ) { note in
            // Optional filter: only react to our bundle id object string.
            if let obj = note.object as? String, !obj.isEmpty, obj != bundleID {
                return
            }
            Task { @MainActor in
                AppState.shared.openMainWindow()
                Banner.show(
                    "HyperForge",
                    subtitle: "Already running",
                    style: .info,
                    symbol: "flame.fill"
                )
            }
        }
    }
}
