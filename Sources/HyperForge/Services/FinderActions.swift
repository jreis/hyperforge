// FinderActions.swift
// Explorer-era power moves: terminal here, file text to clipboard, open in editor.

import AppKit
import Foundation

enum FinderActions {
    /// Selected paths in frontmost Finder window (AppleScript).
    static func selectedPaths() -> [String] {
        let script = """
            tell application "Finder"
                set theItems to selection as alias list
                set out to {}
                repeat with i in theItems
                    set end of out to POSIX path of (i as text)
                end repeat
                return out
            end tell
            """
        return runOSAscriptList(script)
    }

    /// Target folder of frontmost Finder window (or desktop).
    static func frontFolderPath() -> String? {
        let script = """
            tell application "Finder"
                if (count of windows) is 0 then
                    return POSIX path of (desktop as alias)
                end if
                try
                    return POSIX path of (target of front window as alias)
                on error
                    return POSIX path of (desktop as alias)
                end try
            end tell
            """
        return runOSAscriptString(script)
    }

    @MainActor
    static func terminalInFrontFolder() {
        guard let folder = frontFolderPath() else {
            Banner.show(
                "No Finder folder",
                style: .warning,
                symbol: "folder.badge.questionmark"
            )
            return
        }
        TerminalPreference.shared.openInDirectory(folder)
    }

    @MainActor
    static func copySelectedFileContents() {
        let paths = selectedPaths()
        guard let path = paths.first else {
            Banner.show("Select a file in Finder")
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue
        else {
            Banner.show("Select a file (not a folder)")
            return
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            Banner.show("Couldn't read file as text")
            return
        }
        let capped = text.count > 500_000 ? String(text.prefix(500_000)) + "\n…(truncated)" : text
        PasteTransformService.setClipboard(capped)
        Banner.show("Copied \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    @MainActor
    static func previewSelectedFile() {
        let paths = selectedPaths()
        guard let path = paths.first,
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            Banner.show("Select a text file in Finder")
            return
        }
        let lines = text.components(separatedBy: .newlines).prefix(40).joined(separator: "\n")
        let preview = lines.count > 800 ? String(lines.prefix(800)) + "…" : lines
        Banner.show(preview.isEmpty ? "(empty file)" : preview, duration: 4)
    }

    @MainActor
    static func openSelectionInEditor() {
        let paths = selectedPaths()
        guard !paths.isEmpty else {
            Banner.show("Select item(s) in Finder")
            return
        }
        let editors = [
            "dev.zed.Zed",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.sublimetext.4",
        ]
        var appURL: URL?
        for bid in editors {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                appURL = url
                break
            }
        }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        if let appURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, _ in }
            Banner.show("Opened in editor")
        } else {
            for url in urls { NSWorkspace.shared.open(url) }
            Banner.show("Opened with default app")
        }
    }

    private static func runOSAscriptString(_ source: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (str?.isEmpty == false) ? str : nil
    }

    private static func runOSAscriptList(_ source: String) -> [String] {
        guard let raw = runOSAscriptString(source) else { return [] }
        if raw.contains(", ") {
            return raw.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        return raw.isEmpty ? [] : [raw]
    }
}
