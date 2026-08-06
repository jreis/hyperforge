// AXRecipeRecorder.swift
// Records real clicks/keystrokes into AX recipe steps — an alternate authoring path
// into AXRecipeStore, alongside the hand-authored quick-add form in RecipesView.
//
// Follows RegionPinService's capture pattern (passive NSEvent monitors) rather than a
// second CGEventTap: materially lower risk than touching the main Hyper tap, at the
// cost of not being able to suppress recorded keys from reaching the frontmost app.

import AppKit
import ApplicationServices
import Foundation
import HyperForgeKit

@MainActor
final class AXRecipeRecorder: ObservableObject {
    static let shared = AXRecipeRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var draftSteps: [RecordedStepDraft] = []
    @Published private(set) var recordedBundleID: String?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var clicks: [RecordedClickEvent] = []
    private var keys: [RecordedKeyEvent] = []
    private var startTime: Date?

    private init() {}

    func start() {
        guard !isRecording, PermissionsService.isTrusted else {
            if !PermissionsService.isTrusted {
                Banner.show("Accessibility needed", subtitle: "Enable in Settings → Privacy", style: .warning)
            }
            return
        }
        clicks = []
        keys = []
        draftSteps = []
        startTime = Date()
        recordedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        isRecording = true

        HyperKeyEngine.shared.beginMenuSession()
        EscapeCoordinator.shared.setHandler(.axRecording) { [weak self] in
            guard let self, self.isRecording else { return false }
            _ = self.stop()
            return true
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) {
            [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) {
            [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        Banner.show("Recording recipe…", subtitle: "Esc to stop", style: .info, symbol: "record.circle")
    }

    /// Stops recording and returns a ready-to-save recipe, or `nil` if nothing was captured.
    @discardableResult
    func stop() -> AXRecipe? {
        guard isRecording else { return nil }
        isRecording = false

        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        EscapeCoordinator.shared.setHandler(.axRecording, handler: nil)
        HyperKeyEngine.shared.endMenuSession()

        let steps = RecordingCoalescer.toSteps(clicks: clicks, keys: keys)
        draftSteps = steps
        guard !steps.isEmpty else {
            Banner.show("No steps recorded", style: .neutral, symbol: "record.circle")
            return nil
        }

        let fragileCount = steps.count { $0.isFragile }
        Banner.show(
            "Recording stopped",
            subtitle: fragileCount > 0
                ? "\(steps.count) step(s) · \(fragileCount) fragile"
                : "\(steps.count) step(s)",
            style: fragileCount > 0 ? .warning : .success,
            symbol: "record.circle"
        )

        return AXRecipe(
            name: "Recorded \(Self.timeLabel())",
            bundleID: recordedBundleID ?? "",
            steps: steps.map {
                AXRecipeStep(kind: AXRecipeStep.Kind(rawValue: $0.kind.rawValue) ?? .clickNamed, value: $0.value)
            }
        )
    }

    private func handle(_ event: NSEvent) {
        guard isRecording, let start = startTime else { return }
        let ts = Date().timeIntervalSince(start) * 1000

        switch event.type {
        case .leftMouseDown:
            let (label, isFragile) = Self.resolveElement(at: NSEvent.mouseLocation)
            clicks.append(RecordedClickEvent(label: label, isFragile: isFragile, timestampMs: ts))
        case .keyDown:
            // Esc terminates the session via EscapeCoordinator — never record it as input.
            guard event.keyCode != KeyCode.escape else { return }
            if let keyName = Self.chordName(for: event) {
                keys.append(RecordedKeyEvent(character: nil, keyName: keyName, timestampMs: ts))
            } else if let chars = event.characters, !chars.isEmpty {
                keys.append(RecordedKeyEvent(character: chars, keyName: nil, timestampMs: ts))
            }
        default:
            break
        }
    }

    /// Non-nil only for modifier chords (⌘/⌥/⌃ held) — plain typing (including bare Shift)
    /// stays as running typed text instead of a discrete `pressKey` step.
    private static func chordName(for event: NSEvent) -> String? {
        let chordMods = event.modifierFlags.intersection([.command, .option, .control])
        guard !chordMods.isEmpty,
              let char = event.charactersIgnoringModifiers?.lowercased(), !char.isEmpty
        else { return nil }

        var parts: [String] = []
        if event.modifierFlags.contains(.control) { parts.append("ctrl") }
        if event.modifierFlags.contains(.option) { parts.append("alt") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        parts.append(char)
        return parts.joined(separator: "+")
    }

    /// Resolves the AX element under `point` (bottom-left screen coordinates, as returned
    /// by `NSEvent.mouseLocation`) to a stable label. Falls back to the element's role
    /// when no title/description/value is found — callers must treat that as fragile,
    /// since a role-only label is unlikely to re-match a specific control on replay.
    private static func resolveElement(at point: NSPoint) -> (label: String, isFragile: Bool) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        else { return ("Unlabeled", true) }

        // AX position queries use top-left-origin screen coordinates.
        let axPoint = CGPoint(x: point.x, y: screen.frame.height - point.y)
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(
            systemWide, Float(axPoint.x), Float(axPoint.y), &elementRef
        )
        guard err == .success, let element = elementRef else { return ("Unlabeled", true) }

        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        var descRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        var valueRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let label = [titleRef as? String, descRef as? String, valueRef as? String]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
        {
            return (label, false)
        }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        return ((roleRef as? String) ?? "Unlabeled", true)
    }

    private static func timeLabel() -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: Date())
    }
}
