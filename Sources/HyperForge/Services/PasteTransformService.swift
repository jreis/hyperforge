// PasteTransformService.swift
// Clipboard alchemy from the AHK paste menu — local transforms, then paste.

import AppKit
import Foundation

enum PasteTransform: String, CaseIterable, Identifiable {
    case linefeedsToCommas
    case linefeedsToQuotedCommas
    case linefeedsToSemicolons
    case linefeedsToSpaces
    case tabsToCommas
    case tabsToLinefeeds
    case plainText
    case collapseWhitespace
    case trim
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case unixTimestamp
    case typeAsKeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linefeedsToCommas: return "Linefeeds → commas"
        case .linefeedsToQuotedCommas: return "Linefeeds → \"quoted\", commas"
        case .linefeedsToSemicolons: return "Linefeeds → semicolons"
        case .linefeedsToSpaces: return "Linefeeds → spaces"
        case .tabsToCommas: return "Tabs → commas"
        case .tabsToLinefeeds: return "Tabs → linefeeds"
        case .plainText: return "Plain text"
        case .collapseWhitespace: return "Collapse whitespace"
        case .trim: return "Trim ends"
        case .base64Encode: return "Base64 encode"
        case .base64Decode: return "Base64 decode"
        case .urlEncode: return "URL encode"
        case .urlDecode: return "URL decode"
        case .unixTimestamp: return "Unix timestamp ↔ date"
        case .typeAsKeys: return "Type clipboard (keystrokes)"
        }
    }

    var symbol: String {
        switch self {
        case .plainText, .trim, .collapseWhitespace: return "doc.plaintext"
        case .base64Encode, .base64Decode: return "lock.doc"
        case .urlEncode, .urlDecode: return "link"
        case .unixTimestamp: return "clock"
        case .typeAsKeys: return "keyboard"
        default: return "arrow.triangle.2.circlepath"
        }
    }
}

enum PasteTransformService {
    static func clipboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func transform(_ kind: PasteTransform, input: String) -> String? {
        switch kind {
        case .linefeedsToCommas:
            return joinLines(input, separator: ",")
        case .linefeedsToQuotedCommas:
            let parts = lines(input).map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            return parts.joined(separator: ",")
        case .linefeedsToSemicolons:
            return joinLines(input, separator: ";")
        case .linefeedsToSpaces:
            return joinLines(input, separator: " ")
        case .tabsToCommas:
            return input.replacingOccurrences(of: "\t", with: ",")
        case .tabsToLinefeeds:
            return input.replacingOccurrences(of: "\t", with: "\n")
        case .plainText:
            return input
        case .collapseWhitespace:
            return input.replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        case .trim:
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let str = String(data: data, encoding: .utf8)
            else { return nil }
            return str
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode:
            return input.removingPercentEncoding
        case .unixTimestamp:
            return convertTimestamp(input)
        case .typeAsKeys:
            return input
        }
    }

    /// Transform clipboard and paste (⌘V), or type keys for typeAsKeys.
    @MainActor
    static func apply(_ kind: PasteTransform) {
        guard let raw = clipboardString(), !raw.isEmpty else {
            Banner.show("Clipboard empty")
            return
        }
        if kind == .typeAsKeys {
            EventSynthesizer.typeString(raw)
            Banner.show("Typed clipboard")
            return
        }
        guard let out = transform(kind, input: raw) else {
            Banner.show("Transform failed")
            return
        }
        setClipboard(out)
        // Small delay so the pasteboard settles, then ⌘V into the front app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EventSynthesizer.postCommandKey(KeyCode.v)
            Banner.show(kind.title)
        }
    }

    /// Show an NSMenu of transforms at the mouse (AHK paste menu energy).
    @MainActor
    static func showMenu() {
        let menu = NSMenu(title: "Paste transforms")
        for kind in PasteTransform.allCases {
            let item = NSMenuItem(
                title: kind.title,
                action: #selector(PasteMenuTarget.performTransform(_:)),
                keyEquivalent: ""
            )
            item.representedObject = kind.rawValue
            item.target = PasteMenuTarget.shared
            item.image = NSImage(
                systemSymbolName: kind.symbol,
                accessibilityDescription: kind.title
            )
            menu.addItem(item)
            if kind == .plainText || kind == .urlDecode || kind == .unixTimestamp {
                menu.addItem(.separator())
            }
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: loc, in: nil)
    }

    private static func lines(_ s: String) -> [String] {
        s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func joinLines(_ s: String, separator: String) -> String {
        lines(s).joined(separator: separator)
    }

    private static func convertTimestamp(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let epoch = Double(trimmed) {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1000.0 : epoch
            let date = Date(timeIntervalSince1970: seconds)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: date)
        }
        // Parse ISO-ish date → unix
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed) {
            return String(Int(date.timeIntervalSince1970))
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy HH:mm", "MM/dd/yyyy"] {
            df.dateFormat = format
            if let date = df.date(from: trimmed) {
                return String(Int(date.timeIntervalSince1970))
            }
        }
        return nil
    }
}

/// NSMenu target must be an NSObject.
@MainActor
final class PasteMenuTarget: NSObject {
    static let shared = PasteMenuTarget()

    @objc func performTransform(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = PasteTransform(rawValue: raw)
        else { return }
        PasteTransformService.apply(kind)
    }
}
