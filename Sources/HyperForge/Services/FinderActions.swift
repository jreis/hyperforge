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

    /// Whether Finder is the frontmost app (for Hyper+T “here if Finder”).
    static func isFinderFrontmost() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return bid == "com.apple.finder"
    }

    /// Target folder of frontmost Finder window (or desktop / selection parent).
    /// Tries several AppleScript strategies — modern Finder views often break `target of`.
    static func frontFolderPath() -> String? {
        // 1) Primary: front window target → insertion location → desktop
        let script = """
            tell application "Finder"
                try
                    if (count of Finder windows) is 0 then
                        return POSIX path of (path to desktop folder as alias)
                    end if
                    set w to front Finder window
                    try
                        return POSIX path of (target of w as alias)
                    end try
                    try
                        return POSIX path of (insertion location as alias)
                    end try
                    return POSIX path of (path to desktop folder as alias)
                on error errMsg
                    return "ERROR:" & errMsg
                end try
            end tell
            """
        if let raw = runOSAscriptString(script, captureError: true) {
            if raw.hasPrefix("ERROR:") {
                HyperLog.event("Finder folder script: \(raw)")
            } else if isUsableDirectory(raw) {
                return normalizeDirectory(raw)
            }
        }

        // 2) Simpler fallback (older systems / stricter Automation)
        let simple = """
            tell application "Finder"
                try
                    return POSIX path of (target of front window as text)
                on error
                    try
                        return POSIX path of (desktop as alias)
                    on error
                        return ""
                    end try
                end try
            end tell
            """
        if let raw = runOSAscriptString(simple, captureError: true), isUsableDirectory(raw) {
            return normalizeDirectory(raw)
        }

        // 3) If a folder is selected, use it; if a file, use its parent (no AppleScript)
        if let fromSel = directoryFromSelectionViaScript(), isUsableDirectory(fromSel) {
            return normalizeDirectory(fromSel)
        }

        return nil
    }

    /// Folder from selection: selected folder, or parent of selected file.
    private static func directoryFromSelectionViaScript() -> String? {
        let script = """
            tell application "Finder"
                try
                    set sel to selection as alias list
                    if (count of sel) is 0 then return ""
                    set p to item 1 of sel
                    set posixP to POSIX path of p
                    return posixP
                on error
                    return ""
                end try
            end tell
            """
        guard let path = runOSAscriptString(script), !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue { return path }
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        // Trailing slash folders sometimes reported without existing check edge cases
        if path.hasSuffix("/") { return path }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func isUsableDirectory(_ path: String) -> Bool {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !p.hasPrefix("ERROR:") else { return false }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) {
            return isDir.boolValue
        }
        // Desktop / volumes sometimes lag; accept POSIX-looking paths
        return p.hasPrefix("/")
    }

    private static func normalizeDirectory(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // POSIX path of folder usually ends with /
        if p.hasSuffix("/") && p.count > 1 {
            p = String(p.dropLast())
        }
        return p
    }

    @MainActor
    static func terminalInFrontFolder() {
        guard let folder = frontFolderPath() else {
            Banner.show(
                "No Finder folder",
                subtitle: "Open a Finder window · allow Automation if prompted",
                style: .warning,
                symbol: "folder.badge.questionmark"
            )
            HyperLog.event("terminalInFrontFolder: path resolution failed")
            return
        }
        HyperLog.event("terminalInFrontFolder → \(folder)")
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

    private static func runOSAscriptString(_ source: String, captureError: Bool = false) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // -e can break on complex scripts; use stdin
        task.arguments = []
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardInput = inPipe
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            if let data = source.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            try? inPipe.fileHandleForWriting.close()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if captureError, task.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let str, !str.isEmpty { return str }
            if !err.isEmpty { return "ERROR:\(err)" }
            return nil
        }
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
