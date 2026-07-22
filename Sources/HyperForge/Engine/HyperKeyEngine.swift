// HyperKeyEngine.swift
// Global CGEvent tap — the heart of HyperForge.
// F18 (Karabiner Caps→F18) is the Hyper trigger; Right ⌘ enables Vim mode.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation

private let hyperFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

final class HyperKeyEngine: ObservableObject, @unchecked Sendable {
    static let shared = HyperKeyEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var hyperKeyActive = false
    @Published private(set) var lastActionTitle: String?
    @Published private(set) var statusMessage = "Idle"

    var useF18AsHyper = true

    var enabledActionIDs: Set<String>? {
        didSet {
            lock.lock()
            enabledIDsCopy = enabledActionIDs
            lock.unlock()
        }
    }

    private let lock = NSLock()
    private var _hyperActive = false
    /// True only while F18/Caps physical hyper key is held (strict).
    private var f18Held = false
    private var lastF18KeyDownTime = Date.distantPast
    private var lastHyperTriggerTime = Date.distantPast
    /// Last time we observed Hyper-like modifier flags or F18.
    /// Used as a grace window: Karabiner 4-mod Caps often emits a brief
    /// “all modifiers up” flagsChanged before the actual keyDown arrives.
    private var lastHyperSeenTime = Date.distantPast
    private let hyperGraceSeconds: TimeInterval = 0.85
    private var enabledIDsCopy: Set<String>?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var clipboardTimer: Timer?
    private var appTrackTimer: Timer?
    private var didRequestAccessibility = false

    private init() {}

    // MARK: - Lifecycle

    @MainActor
    func start() {
        guard !isRunning else { return }
        statusMessage = "Starting…"
        startEventTap()
        startAuxTimers()
    }

    @MainActor
    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        appTrackTimer?.invalidate()
        appTrackTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        setHyperActive(false)
        statusMessage = "Stopped"
    }

    @MainActor
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
            Banner.show("HyperForge ready")
        }
    }

    private func startAuxTimers() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in ClipboardService.shared.poll() }
        }
        appTrackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in AppLauncher.shared.trackAppSwitch() }
        }
    }

    @MainActor
    private func startEventTap() {
        if !PermissionsService.isTrusted, !didRequestAccessibility {
            PermissionsService.requestTrust()
            didRequestAccessibility = true
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let unmanaged = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else {
                        return Unmanaged.passUnretained(event)
                    }
                    let engine = Unmanaged<HyperKeyEngine>.fromOpaque(refcon).takeUnretainedValue()
                    return engine.handleEvent(type: type, event: event)
                },
                userInfo: unmanaged
            )
        else {
            statusMessage = "Waiting for Accessibility…"
            scheduleRetry()
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        statusMessage = "Engine live · F18 / 4-mod Hyper · Right ⌘ Vim"
        HyperLog.event("Event tap started")
    }

    @MainActor
    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            DispatchQueue.main.async {
                guard let self else { return }
                if PermissionsService.isTrusted {
                    timer.invalidate()
                    self.retryTimer = nil
                    self.startEventTap()
                    Banner.show("HyperForge enabled")
                }
            }
        }
    }

    // MARK: - Tap callback

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Let our own injected keystrokes through. Without this, Hyper+X → ⌘W is
        // swallowed because F18 is still held and unbound Hyper keys are blocked.
        if type == .keyDown || type == .keyUp {
            if EventSynthesizer.consumePassThroughIfNeeded() {
                HyperLog.event("pass-through synthetic key=\(keyCode) type=\(type.rawValue)")
                return Unmanaged.passUnretained(event)
            }
        }

        if type == .keyDown || type == .flagsChanged {
            HyperLog.event(
                "type=\(type.rawValue) key=\(keyCode) flags=\(flags.rawValue) hyper=\(isHyperActive)"
            )
        }

        // ── Dedicated keys from Karabiner (bypass sticky-Hyper) ─────────
        // F19 = Hyper+/ cheat sheet · F20 = Hyper+, show dashboard
        if type == .keyDown {
            if keyCode == KeyCode.f19 || keyCode == 0x50 {
                HyperLog.event("F19 → cheat sheet")
                CheatSheetCommands.show()
                return nil
            }
            if keyCode == KeyCode.f20 || keyCode == 0x5A {
                HyperLog.event("F20 → open dashboard")
                AppCommands.openMainWindow()
                return nil
            }
        }

        let now = Date()
        let looksLikeQuadHyper =
            flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskControl)
            && flags.contains(.maskShift)
        let looksLikeTripleHyper =
            flags.contains(.maskControl)
            && flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)

        // ── F18 / raw Caps as Hyper ──────────────────────────────────────
        if keyCode == KeyCode.f18 || keyCode == KeyCode.hidF18 || keyCode == KeyCode.capsLock {
            if useF18AsHyper {
                if type == .keyDown {
                    f18Held = true
                    markHyperSeen(now)
                    setHyperActive(true)
                    HyperLog.event("F18 down → hyper ON")
                } else if type == .keyUp {
                    f18Held = false
                    setHyperActive(false)
                    lastHyperTriggerTime = now
                    HyperLog.event("F18 up → hyper OFF")
                } else if type == .flagsChanged {
                    // Some stacks emit F18 only as flagsChanged
                    f18Held.toggle()
                    if f18Held {
                        markHyperSeen(now)
                        setHyperActive(true)
                    } else {
                        setHyperActive(false)
                    }
                }
            }
            return nil
        }

        if keyCode == KeyCode.rightCommand {
            if type == .keyDown || (type == .flagsChanged && flags.contains(.maskCommand)) {
                VimNavigation.shared.setActive(true)
            } else if type == .keyUp
                || (type == .flagsChanged && !flags.contains(.maskCommand))
            {
                VimNavigation.shared.setActive(false)
            }
            return nil
        }

        if keyCode == KeyCode.rightControl {
            if type == .keyDown || (type == .flagsChanged && flags.contains(.maskControl)) {
                markHyperSeen(now)
                setHyperActive(true)
            } else if type == .keyUp
                || (type == .flagsChanged && !flags.contains(.maskControl))
            {
                setHyperActive(false)
                lastHyperTriggerTime = now
            }
            return nil
        }

        // ── 4-mod / 3-mod Hyper via flagsChanged (Karabiner Caps→mods) ──
        // IMPORTANT: do NOT clear hyper on the intermediate “flags=256” blip
        // that Karabiner emits before the actual keyDown. Use grace period.
        if type == .flagsChanged {
            if looksLikeQuadHyper || looksLikeTripleHyper {
                markHyperSeen(now)
                setHyperActive(true)
                HyperLog.event(
                    "mod-hyper ON quad=\(looksLikeQuadHyper) triple=\(looksLikeTripleHyper)"
                )
                return nil
            }
            // Mods released — schedule sticky clear via grace, don't kill instantly
            if isHyperActive && !f18Held {
                let noHyperMods =
                    !flags.contains(.maskControl)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskShift)
                if noHyperMods {
                    // Leave sticky true until grace expires (checked on keyDown)
                    HyperLog.event("mod-hyper soft-release (grace \(hyperGraceSeconds)s)")
                }
            }
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Sticky hyper if: F18 held, mods look like hyper, or within grace after last hyper sighting
        let withinGrace =
            Date().timeIntervalSince(lastHyperSeenTime) < hyperGraceSeconds
        let shouldTreatAsHyper =
            f18Held
            || looksLikeQuadHyper
            || looksLikeTripleHyper
            || (isHyperActive && withinGrace)
            || flags.contains(hyperFlags)
            || (useF18AsHyper && flags.contains(.maskAlphaShift))

        if !shouldTreatAsHyper, isHyperActive, !f18Held, !withinGrace {
            setHyperActive(false)
        }

        if shouldTreatAsHyper {
            markHyperSeen(now)
            setHyperActive(true)

            HyperLog.event(
                "HYPER keyDown key=\(keyCode) f18=\(f18Held) quad=\(looksLikeQuadHyper) grace=\(withinGrace) flags=\(flags.rawValue)"
            )

            // Help / cheat sheet — always show() (not toggle) so a partial open still works
            let isHelpKey =
                keyCode == KeyCode.slash
                || keyCode == KeyCode.grave
                || keyCode == 0x2C  // slash
                || keyCode == 0x32  // grave
                || helpCharacter(from: event) != nil
            if isHelpKey {
                let ch = helpCharacter(from: event) ?? "key\(keyCode)"
                HyperLog.event("HYPER help SHOW char=\(ch) key=\(keyCode)")
                CheatSheetCommands.show()  // always show, never toggle-off by accident
                DispatchQueue.main.async { SnippetStore.shared.resetBuffer() }
                return nil
            }

            let ids = enabledIDsSnapshot()
            let shiftDown = flags.contains(.maskShift)
            let hyperConsumesShift = looksLikeQuadHyper || (isHyperActive && withinGrace)
            if HyperKeyActions.handle(
                keyCode,
                enabledIDs: ids,
                shiftDown: shiftDown,
                hyperConsumesShift: hyperConsumesShift
            ) {
                HyperLog.event(
                    "HYPER handled key=\(keyCode) shift=\(shiftDown) quad=\(hyperConsumesShift)"
                )
                DispatchQueue.main.async { SnippetStore.shared.resetBuffer() }
                return nil
            }
            // Swallow unbound hyper keys so they don't leak into apps
            return nil
        }

        if VimNavigation.shared.isActive {
            let shiftDown = flags.contains(.maskShift)
            let ctrlDown = flags.contains(.maskControl)
            if VimNavigation.shared.handle(
                keyCode: keyCode,
                shiftDown: shiftDown,
                ctrlDown: ctrlDown
            ) {
                DispatchQueue.main.async { SnippetStore.shared.resetBuffer() }
                return nil
            }
        }

        // Text expansions (hotstrings) — only when not in Hyper/Vim.
        // Always hop via main queue (never MainActor.assumeIsolated — crashes under MenuBarExtra / Swift 6).
        if !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
        {
            let chars = event.keyboardGetUnicodeString()
            var expanded = false
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                expanded = SnippetStore.shared.handleTypedKey(
                    character: chars,
                    keyCode: keyCode
                )
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 0.15)
            if expanded {
                return nil  // swallow trigger key; expansion already deleted trigger + typed
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private var isHyperActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _hyperActive
    }

    private func setHyperActive(_ value: Bool) {
        lock.lock()
        _hyperActive = value
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.hyperKeyActive = value
        }
    }

    private func markHyperSeen(_ date: Date = Date()) {
        lastHyperSeenTime = date
        lastHyperTriggerTime = date
        lastF18KeyDownTime = date
    }

    private func enabledIDsSnapshot() -> Set<String>? {
        lock.lock(); defer { lock.unlock() }
        return enabledIDsCopy
    }

    /// "/" or "?" or "`" under Hyper → open cheat sheet (any keyboard layout).
    private func helpCharacter(from event: CGEvent) -> String? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        let raw = (nsEvent.charactersIgnoringModifiers ?? nsEvent.characters ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = raw.first else { return nil }
        switch ch {
        case "/", "?", "`", "~":
            return String(ch)
        default:
            return nil
        }
    }
}

// MARK: - Unicode helper

private extension CGEvent {
    func keyboardGetUnicodeString() -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: Int(length))
    }
}
