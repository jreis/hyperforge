// HyperDebug.swift
// Optional local file log for Hyper/Caps diagnosis (no network).
// Enable: defaults write app.hyperforge.HyperForge hf.debugLog -bool true
// Log:    /tmp/hyperforge-debug.log

import Foundation

enum HyperDebug {
    private static let path = "/tmp/hyperforge-debug.log"
    private static let lock = NSLock()
    private static let enabledKey = "hf.debugLog"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }
}
