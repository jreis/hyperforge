// HyperLog.swift
// Lightweight debug logging for the event-tap engine.

import Foundation

enum HyperLog {
    static var enabled: Bool = true
    static let path = "/tmp/hyperforge-events.log"

    static func event(_ message: String) {
        guard enabled else { return }
        let line = "\(Date()): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
