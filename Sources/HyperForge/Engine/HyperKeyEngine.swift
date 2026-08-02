// HyperKeyEngine.swift
// Global CGEvent tap — the heart of HyperForge.
// F18 (Karabiner Caps→F18) is the Hyper trigger; Space hold enables TouchCursor-style nav.

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
    /// Space key is owned (pending hold, armed, or typing rollover).
    @Published private(set) var spaceLayerHeld = false
    /// Space layer accepts nav keys (hold threshold met).
    @Published private(set) var spaceLayerArmed = false
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
    /// After force-clear while Caps may still be down, ignore F18 keyDown until a keyUp.
    /// Prevents “Hyper stuck on” when we clear latch mid-hold (clipboard Esc, menus).
    private var blockHyperUntilKeyUp = false
    /// Bumps on force-clear so a stale `setHyperActive(true)` async can’t re-light the UI.
    private var hyperUIGeneration: UInt64 = 0
    private var lastF18KeyDownTime = Date.distantPast
    private var lastHyperTriggerTime = Date.distantPast
    /// Last time we observed Hyper-like modifier flags or F18.
    /// Short grace only: Karabiner 4-mod Caps can emit a brief “all modifiers up”
    /// flagsChanged before the chord’s keyDown. Must stay tight — a long grace
    /// made bare keys after Hyper+← (e.g. 7 / Num7) fire as Hyper+7 → top-left.
    private var lastHyperSeenTime = Date.distantPast
    private let hyperGraceSeconds: TimeInterval = 0.18
    /// After Caps/F18/4-mod physical release, Karabiner often posts Escape via
    /// `to_if_alone`. That must not dismiss HyperForge UI (dashboard, etc.).
    private var suppressUIEscapeUntil = Date.distantPast
    private let capsAloneEscapeSuppressSeconds: TimeInterval = 0.45
    /// While an NSMenu (clipboard history, transforms, quick menu, …) is open,
    /// Hyper+Esc must not lock the screen — Esc only dismisses the menu.
    private var menuSessionDepth = 0
    /// Grace after menu closes so Esc that closes the menu can't still lock.
    private var suppressSysLockUntil = Date.distantPast
    private let menuDismissLockSuppressSeconds: TimeInterval = 0.55
    /// Open popup menus only after Caps/Hyper is released (avoids stuck latch).
    private var pendingMenuOpener: (() -> Void)?
    private var pendingMenuTimeout: DispatchWorkItem?
    private let pendingMenuTimeoutSeconds: TimeInterval = 0.40
    private var enabledIDsCopy: Set<String>?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
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
        // Keep Space-nav per-app gate in sync with the frontmost app.
        Task { @MainActor in
            _ = SpaceNavStore.shared
            SpaceNavStore.shared.refreshFrontmost()
        }
    }

    @MainActor
    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
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
        setPhysicalHyperHold(false)
        VimNavigation.shared.cancelSpaceLayer()
        applySpaceLayerUI(held: false, armed: false)
        statusMessage = "Stopped"
    }

    /// Called from VimNavigation on main-queue edges (never from the tap directly).
    @MainActor
    func applySpaceLayerUI(held: Bool, armed: Bool) {
        spaceLayerHeld = held
        spaceLayerArmed = armed
        let hudOn = UserDefaults.standard.object(forKey: "hf.showSpaceLayerHUD") as? Bool ?? true
        SpaceLayerHUD.setArmed(armed && hudOn)
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
        // Clipboard history is on-demand (Clipboard panel) — no background pasteboard poll.
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
        statusMessage = "Engine live · F18 / 4-mod Hyper · Space nav"
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
        // Prefer eventSourceUserData marker (reliable); counter is a fallback.
        if type == .keyDown || type == .keyUp {
            if EventSynthesizer.shouldPassThrough(event) {
                return Unmanaged.passUnretained(event)
            }
        }

        let now = Date()

        // ── F18 / raw Caps as Hyper (keyUp must clear held state) ────────
        // Only keyDown/keyUp latch Hyper. flagsChanged+toggle used to leave Caps/Hyper
        // stuck ON after NSMenu dismiss (Esc) when a keyUp was missed or reordered.
        if keyCode == KeyCode.f18 || keyCode == KeyCode.hidF18 || keyCode == KeyCode.capsLock {
            if useF18AsHyper {
                if type == .keyDown {
                    // While a menu/panel is open, ignore new Hyper latch.
                    if isInMenuSession {
                        HyperLog.event("F18/Caps keyDown ignored during menu session")
                        return nil
                    }
                    // Mid-hold force-clear (Esc on clipboard panel): Caps may still be down.
                    // Do not re-arm Hyper until the user fully releases and presses again.
                    if blockHyperUntilKeyUp {
                        HyperLog.event("F18/Caps keyDown ignored (awaiting keyUp after force-clear)")
                        return nil
                    }
                    f18Held = true
                    markHyperSeen(now)
                    setHyperActive(true)
                    setPhysicalHyperHold(true)
                } else if type == .keyUp {
                    // Always honor keyUp — clears latch and arms the next press.
                    blockHyperUntilKeyUp = false
                    f18Held = false
                    setHyperActive(false)
                    setPhysicalHyperHold(false)
                    lastHyperTriggerTime = now
                    // Caps-alone → Escape follows this keyUp; don't treat it as UI Esc.
                    noteCapsAloneEscapeWindow(from: now)
                    // Deferred menus (clipboard history, etc.) open on real Caps release.
                    flushPendingMenu(force: false)
                }
                // flagsChanged: intentionally ignored for latch state (toggle caused stuck-on)
            }
            return nil
        }

        // TouchCursor layer: Space is swallowed on keyDown; plain Space types on keyUp.
        if keyCode == KeyCode.space {
            let looksLikeQuad =
                flags.contains(.maskCommand)
                && flags.contains(.maskAlternate)
                && flags.contains(.maskControl)
                && flags.contains(.maskShift)
            let looksLikeTriple =
                flags.contains(.maskControl)
                && flags.contains(.maskCommand)
                && flags.contains(.maskAlternate)
            // Only block Space-layer for *physical* Hyper / real mod chords (Hyper+Space
            // command bar, Spotlight, etc.). Sticky Hyper grace alone must NOT disable
            // Space nav — that broke HJKL in browsers right after a Hyper chord.
            let physicalHyperOnSpace =
                f18Held
                || looksLikeQuad
                || looksLikeTriple
                || flags.contains(hyperFlags)
            let shiftOnlyOrNone =
                !flags.contains(.maskCommand)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
            if type == .keyDown {
                // Ignore key-repeat while holding Space for the layer.
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                   VimNavigation.shared.isActive
                {
                    return nil
                }
                if VimNavigation.shared.handleSpaceKeyDown(
                    shiftOnlyOrNone: shiftOnlyOrNone,
                    hyperActive: physicalHyperOnSpace
                ) {
                    return nil
                }
            } else if type == .keyUp {
                if VimNavigation.shared.handleSpaceKeyUp() {
                    return nil
                }
            }
            // Cmd/Ctrl/Opt+Space or Hyper+Space fall through to normal/Hyper handling.
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
                noteCapsAloneEscapeWindow(from: now)
            }
            return nil
        }

        // Most keyUps: pass through immediately (no snippet / Hyper work).
        // (Space keyUp is handled above for the nav layer.)
        if type == .keyUp {
            return Unmanaged.passUnretained(event)
        }

        // ── Dedicated keys from Karabiner (bypass sticky-Hyper) ─────────
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

        let looksLikeQuadHyper =
            flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskControl)
            && flags.contains(.maskShift)
        let looksLikeTripleHyper =
            flags.contains(.maskControl)
            && flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)

        // ── 4-mod / 3-mod Hyper via flagsChanged (Karabiner Caps→mods) ──
        if type == .flagsChanged {
            if looksLikeQuadHyper || looksLikeTripleHyper {
                markHyperSeen(now)
                setHyperActive(true)
                setPhysicalHyperHold(true)
                return nil
            }
            // Physical 4-mod release (Caps up) often precedes Caps-alone Escape.
            if isHyperActive, !f18Held {
                noteCapsAloneEscapeWindow(from: now)
                setPhysicalHyperHold(false)
                // Caps released (mods dropped) → open deferred menu if any.
                flushPendingMenu(force: false)
            }
            // Soft release via grace (checked on keyDown) — no logging on every blip.
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Physical Hyper still held? (not merely sticky/grace)
        // NOTE: Do NOT treat .maskAlphaShift (Caps Lock LED) as Hyper. A latched Caps Lock
        // toggle made every key act as Hyper forever after Esc / bad recovery synthesis.
        let physicallyHeld: Bool = {
            if blockHyperUntilKeyUp { return false }
            if f18Held { return true }
            if looksLikeQuadHyper || looksLikeTripleHyper { return true }
            if flags.contains(hyperFlags) { return true }
            return false
        }()

        // Sticky hyper if: physically held, or brief grace after last physical Hyper sighting
        let withinGrace =
            !blockHyperUntilKeyUp
            && now.timeIntervalSince(lastHyperSeenTime) < hyperGraceSeconds
        let shouldTreatAsHyper =
            physicallyHeld
            || (isHyperActive && withinGrace)

        if !shouldTreatAsHyper, isHyperActive, !physicallyHeld, !withinGrace {
            setHyperActive(false)
        }

        // Space-layer (TouchCursor) must win over sticky/grace Hyper — otherwise HJKL is
        // swallowed as unbound Hyper while coding in Chrome/CodeSignal after a recent chord.
        // Physical Hyper hold still wins when Caps/F18/4-mod is actually down.
        let spaceLayerActive = VimNavigation.shared.isActive
        if spaceLayerActive, !physicallyHeld {
            let shiftDown = flags.contains(.maskShift)
            let ctrlDown = flags.contains(.maskControl)
            if VimNavigation.shared.handle(
                keyCode: keyCode,
                shiftDown: shiftDown,
                ctrlDown: ctrlDown
            ) {
                SnippetEngine.shared.resetBuffer()
                return nil
            }
            // Unmapped key while Space held: let it through (typing mid-hold).
        } else if shouldTreatAsHyper {
            // Handle Esc for panels/menus *before* re-asserting Hyper active / grace.
            // (Previously setHyperActive(true) ran first and could race the UI clear.)
            if keyCode == KeyCode.escape {
                if ClipboardHistoryPanel.isShowing {
                    HyperLog.event("Hyper+Esc → close clipboard panel (no lock)")
                    noteCapsAloneEscapeWindow(from: now)
                    forceClearHyperHold(reason: "esc-clipboard-panel", releaseHardware: true)
                    DispatchQueue.main.async {
                        ClipboardHistoryPanel.hide(clearHyper: true)
                    }
                    return nil
                }
                if shouldSuppressSysLock {
                    HyperLog.event(
                        "Hyper+Esc suppressed (menu / pending menu) — clear Hyper, cancel menu"
                    )
                    noteCapsAloneEscapeWindow(from: now)
                    if hasPendingMenu {
                        cancelPendingMenu()
                        suppressSysLockUntil = Date().addingTimeInterval(
                            menuDismissLockSuppressSeconds
                        )
                    }
                    forceClearHyperHold(reason: "esc-during-menu", releaseHardware: true)
                    return Unmanaged.passUnretained(event)
                }
                if !physicallyHeld {
                    HyperLog.event("Escape after Hyper release → pass through (not lock)")
                    noteCapsAloneEscapeWindow(from: now)
                    endStickyHyper()
                    return Unmanaged.passUnretained(event)
                }
            }

            // Only extend grace from real Hyper hold — not from every chord keyDown.
            // Extending on each key made a following bare “7” into Hyper+7 (top-left).
            if physicallyHeld {
                markHyperSeen(now)
            }
            setHyperActive(true)

            // Ignore key-repeat while Hyper is held (avoids double snaps / odd overrides).
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return nil
            }

            // Help keys by keycode first (avoid NSEvent conversion on every Hyper key).
            let isHelpKey =
                keyCode == KeyCode.slash
                || keyCode == KeyCode.grave
                || keyCode == 0x2C
                || keyCode == 0x32
            if isHelpKey {
                HyperLog.event("HYPER help SHOW key=\(keyCode)")
                CheatSheetCommands.show()
                SnippetEngine.shared.resetBuffer()
                if !physicallyHeld { endStickyHyper() }
                return nil
            }

            let ids = enabledIDsSnapshot()
            let shiftDown = flags.contains(.maskShift)
            // Shift is only “part of Hyper” while 4-mod is physically held (not grace-only).
            let hyperConsumesShift = looksLikeQuadHyper || flags.contains(hyperFlags)
            if HyperKeyActions.handle(
                keyCode,
                enabledIDs: ids,
                shiftDown: shiftDown,
                hyperConsumesShift: hyperConsumesShift,
                physicallyHyperHeld: physicallyHeld
            ) {
                HyperLog.event(
                    "HYPER handled key=\(keyCode) physical=\(physicallyHeld) grace=\(withinGrace)"
                )
                SnippetEngine.shared.resetBuffer()
                // Chord done and Caps/F18 not held → drop sticky immediately so the
                // next normal key (often near-num pad or top-row 7) is not Hyper+key.
                if !physicallyHeld {
                    endStickyHyper()
                }
                return nil
            }
            // Swallow unbound hyper keys so they don't leak into apps
            if !physicallyHeld {
                endStickyHyper()
            }
            return nil
        } else if spaceLayerActive {
            // Physical Hyper was also held — still allow Space layer if Hyper didn't claim above.
            let shiftDown = flags.contains(.maskShift)
            let ctrlDown = flags.contains(.maskControl)
            if VimNavigation.shared.handle(
                keyCode: keyCode,
                shiftDown: shiftDown,
                ctrlDown: ctrlDown
            ) {
                SnippetEngine.shared.resetBuffer()
                return nil
            }
        }

        // Text expansions — lock-based matcher, never block the tap waiting for MainActor.
        // (Previously: main.async + semaphore.wait up to 150ms *per keystroke* → system-wide lag.)
        if !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
            && !VimNavigation.shared.isActive
        {
            let chars = event.keyboardGetUnicodeString()
            if SnippetEngine.shared.handleTypedKey(
                character: chars,
                keyCode: keyCode,
                hyperActive: false,
                vimActive: false
            ) {
                return nil
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
        let changed = _hyperActive != value
        _hyperActive = value
        let gen = hyperUIGeneration
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Drop stale activations after forceClearHyperHold.
            self.lock.lock()
            let currentGen = self.hyperUIGeneration
            self.lock.unlock()
            guard gen == currentGen else { return }
            self.hyperKeyActive = value
            if value {
                FirstRunChallengeStore.shared.noteHyper()
            }
        }
    }

    /// Hold-Hyper live bindings HUD (physical F18 / 4-mod only — not sticky grace).
    private func setPhysicalHyperHold(_ held: Bool) {
        DispatchQueue.main.async {
            HyperBindingsHUD.setHyperHeld(held)
        }
    }

    private func markHyperSeen(_ date: Date = Date()) {
        lastHyperSeenTime = date
        lastHyperTriggerTime = date
        lastF18KeyDownTime = date
    }

    /// Karabiner `to_if_alone` Escape arrives just after Hyper release — ignore for UI.
    private func noteCapsAloneEscapeWindow(from date: Date = Date()) {
        lock.lock()
        suppressUIEscapeUntil = date.addingTimeInterval(capsAloneEscapeSuppressSeconds)
        lock.unlock()
    }

    /// True while Caps-alone → Escape (or immediate post-Hyper Escape) should not
    /// dismiss HyperForge chrome. Real Esc key presses outside this window still work.
    var shouldSuppressEscapeForUI: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() < suppressUIEscapeUntil
    }

    /// True while a HyperForge NSMenu is tracking, waiting to open, or just closed.
    /// Prevents Hyper+⇧V → Esc from becoming Hyper+Esc (lock) + stuck Caps.
    var shouldSuppressSysLock: Bool {
        lock.lock()
        defer { lock.unlock() }
        return menuSessionDepth > 0
            || pendingMenuOpener != nil
            || Date() < suppressSysLockUntil
    }

    private var isInMenuSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return menuSessionDepth > 0
    }

    private var hasPendingMenu: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingMenuOpener != nil
    }

    /// Modal NSMenu session (quick menu / shortcuts / transforms only).
    func beginMenuSession() {
        forceClearHyperHold(reason: "menu-begin", releaseHardware: true)
        lock.lock()
        menuSessionDepth += 1
        let depth = menuSessionDepth
        lock.unlock()
        HyperLog.event("menu session begin depth=\(depth)")
    }

    func endMenuSession() {
        lock.lock()
        menuSessionDepth = max(0, menuSessionDepth - 1)
        suppressSysLockUntil = Date().addingTimeInterval(menuDismissLockSuppressSeconds)
        let depth = menuSessionDepth
        lock.unlock()
        HyperLog.event("menu session end depth=\(depth)")
        if depth == 0 {
            forceClearHyperHold(reason: "menu-end", releaseHardware: true)
        }
    }

    /// Non-modal panel session (clipboard history). Suppresses Hyper+Esc lock while open.
    func beginNonModalUISession() {
        lock.lock()
        menuSessionDepth += 1
        let depth = menuSessionDepth
        lock.unlock()
        HyperLog.event("non-modal UI session begin depth=\(depth)")
    }

    func endNonModalUISession() {
        lock.lock()
        menuSessionDepth = max(0, menuSessionDepth - 1)
        suppressSysLockUntil = Date().addingTimeInterval(menuDismissLockSuppressSeconds)
        let depth = menuSessionDepth
        lock.unlock()
        HyperLog.event("non-modal UI session end depth=\(depth)")
    }

    /// Schedule an NSMenu to open only after Caps/Hyper is released.
    /// Opening a modal menu *while* Caps is still down is what sticks Hyper/Caps.
    func openMenuAfterHyperRelease(_ open: @escaping () -> Void) {
        cancelPendingMenu()
        lock.lock()
        pendingMenuOpener = open
        lock.unlock()
        HyperLog.event("menu deferred until Hyper release")

        // If already released (sticky-only chord), open on next run-loop turn.
        if !f18Held, !systemLooksLikeHyperHeld() {
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingMenu(force: false)
            }
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingMenu(force: true)
        }
        pendingMenuTimeout = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + pendingMenuTimeoutSeconds,
            execute: work
        )
    }

    private func cancelPendingMenu() {
        pendingMenuTimeout?.cancel()
        pendingMenuTimeout = nil
        lock.lock()
        pendingMenuOpener = nil
        lock.unlock()
    }

    /// Open deferred menu (on Caps keyUp, 4-mod release, or timeout).
    private func flushPendingMenu(force: Bool) {
        lock.lock()
        let open = pendingMenuOpener
        pendingMenuOpener = nil
        lock.unlock()
        pendingMenuTimeout?.cancel()
        pendingMenuTimeout = nil
        guard let open else { return }

        if force {
            HyperLog.event("menu flush forced (timeout) — releasing stuck keys")
        } else {
            HyperLog.event("menu flush on Hyper release")
        }
        forceClearHyperHold(reason: "menu-flush", releaseHardware: true)
        // One more turn so key-ups settle before popUp steals the run loop.
        DispatchQueue.main.async {
            open()
        }
    }

    /// OS-level check: 4-mod still down (not Caps Lock LED — that is not Hyper).
    private func systemLooksLikeHyperHeld() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        let quad =
            flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskControl)
            && flags.contains(.maskShift)
        let triple =
            flags.contains(.maskCommand)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskControl)
        return quad || triple
    }

    /// Hard reset Hyper latch + sticky grace + hold HUD (safe after menus / Esc).
    /// - Parameter releaseHardware: also synthesize key-ups for stuck ⌘⌥⌃⇧ / F18.
    func forceClearHyperHold(reason: String, releaseHardware: Bool = false) {
        lock.lock()
        f18Held = false
        _hyperActive = false
        // Caps may still be physically down — ignore keyDown until a real keyUp.
        blockHyperUntilKeyUp = true
        lastHyperSeenTime = .distantPast
        lastHyperTriggerTime = Date()
        hyperUIGeneration &+= 1
        let gen = hyperUIGeneration
        lock.unlock()
        HyperLog.event(
            "forceClearHyperHold: \(reason) hardware=\(releaseHardware) blockUntilKeyUp=true"
        )
        if releaseHardware {
            EventSynthesizer.releaseStuckHyperKeys()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let currentGen = self.hyperUIGeneration
            self.lock.unlock()
            guard gen == currentGen else { return }
            self.hyperKeyActive = false
            HyperBindingsHUD.setHyperHeld(false)
        }
    }

    /// Drop sticky Hyper without waiting for grace (after a finished chord).
    private func endStickyHyper() {
        // Soft end: do not block next press or blast hardware key-ups.
        lock.lock()
        f18Held = false
        _hyperActive = false
        lastHyperSeenTime = .distantPast
        hyperUIGeneration &+= 1
        let gen = hyperUIGeneration
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let currentGen = self.hyperUIGeneration
            self.lock.unlock()
            guard gen == currentGen else { return }
            self.hyperKeyActive = false
            HyperBindingsHUD.setHyperHeld(false)
        }
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
