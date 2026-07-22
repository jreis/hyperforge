// PermissionsService.swift
// Accessibility trust checks for the event tap.

import ApplicationServices
import AppKit
import Foundation

enum PermissionsService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        let opts =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
