// HyperLog.swift
// Lightweight debug logging for the event-tap engine.

import Foundation

enum HyperLog {
    /// Off by default — logging every keystroke is a major source of typing lag.
    /// Enable under Settings → Privacy when debugging.
    static var enabled: Bool = UserDefaults.standard.bool(forKey: "hf.eventLog") {
        didSet { UserDefaults.standard.set(enabled, forKey: "hf.eventLog") }
    }

    static let path = "/tmp/hyperforge-events.log"

    /// Never block the event tap or main thread on disk I/O.
    private static let queue = DispatchQueue(label: "app.hyperforge.log", qos: .utility)

    static func event(_ message: String) {
        guard enabled else { return }
        let line = "\(Date()): \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}
