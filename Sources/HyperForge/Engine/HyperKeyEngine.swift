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
    /// Bumps on clear so a stale `setHyperActive(true)` async can’t re-light the UI.
    private var hyperUIGeneration: UInt64 = 0
    /// Clipboard history panel is visible (non-modal) — Esc must not lock.
    private var clipboardPanelVisible = false
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
    /// Hyper+V while Caps still held → show menu on Caps release (menus die if opened mid-hold).
    private var pendingClipboardMenu = false
    private var pendingClipboardTimeout: DispatchWorkItem?
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
        // Reset any leaked menu flags from a previous crash / bad session.
        menuSessionDepth = 0
        clipboardPanelVisible = false
        ClipboardHistoryPanel.setTracking(false)
        HyperDebug.log("engine.start useF18=\(useF18AsHyper)")
        // One-shot clear if Caps Lock LED is latched from a previous session.
        EventSynthesizer.clearCapsLockIfLatched()
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

        // With Caps→F18, Caps Lock LED should never stay on. If it latches (your logs
        // show alphaShift flip true with no CAPS/F18 event), clear it immediately so
        // the next key isn't a capital letter mistaken for Hyper.
        if useF18AsHyper,
           type == .keyDown,
           event.flags.contains(.maskAlphaShift),
           !EventSynthesizer.shouldPassThrough(event)
        {
            EventSynthesizer.clearCapsLockIfLatched()
        }

        // ── F18 / raw Caps as Hyper (keyUp must clear held state) ────────
        if keyCode == KeyCode.f18 || keyCode == KeyCode.hidF18 || keyCode == KeyCode.capsLock {
            if useF18AsHyper {
                if type == .keyDown {
                    f18Held = true
                    markHyperSeen(now)
                    setHyperActive(true)
                    setPhysicalHyperHold(true)
                    HyperDebug.log("CAPS/F18 down key=\(keyCode) f18Held=1")
                } else if type == .keyUp {
                    f18Held = false
                    setHyperActive(false)
                    setPhysicalHyperHold(false)
                    lastHyperTriggerTime = now
                    noteCapsAloneEscapeWindow(from: now)
                    flushPendingMenu(force: false)
                    // Hyper+V while Caps held: open clipboard only after release
                    // (NSMenu dismisses instantly if modifiers are still down).
                    flushPendingClipboardMenu()
                    HyperDebug.log("CAPS/F18 up key=\(keyCode) f18Held=0")
                }
            }
            // Swallow so Caps never toggles system Caps Lock while we own Hyper.
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

        // Clipboard panel Esc works even when Caps is released (panel not key).
        if keyCode == KeyCode.escape,
           clipboardPanelVisible || ClipboardHistoryPanel.isShowing
        {
            noteCapsAloneEscapeWindow(from: now)
            DispatchQueue.main.async {
                ClipboardHistoryPanel.hide()
            }
            return nil
        }

        // Physical Hyper still held? (not merely sticky/grace)
        // NOTE: Do NOT treat .maskAlphaShift (Caps Lock LED) as Hyper.
        let physicallyHeld =
            f18Held
            || looksLikeQuadHyper
            || looksLikeTripleHyper
            || flags.contains(hyperFlags)

        let withinGrace =
            now.timeIntervalSince(lastHyperSeenTime) < hyperGraceSeconds
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
                // Clipboard panel: always close on Esc even when the panel is not key
                // (user shouldn't need to click the window first).
                if clipboardPanelVisible || ClipboardHistoryPanel.isShowing {
                    noteCapsAloneEscapeWindow(from: now)
                    DispatchQueue.main.async {
                        ClipboardHistoryPanel.hide()
                    }
                    return nil
                }
                // Other NSMenus: pass Esc through so the menu dismisses; never lock.
                if shouldSuppressSysLock {
                    noteCapsAloneEscapeWindow(from: now)
                    if hasPendingMenu {
                        cancelPendingMenu()
                    }
                    return Unmanaged.passUnretained(event)
                }
                if !physicallyHeld {
                    noteCapsAloneEscapeWindow(from: now)
                    softClearHyperHold(reason: "esc-after-release")
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

            // Hyper+V / ⇧V → clipboard menu (swallow V). Open on Caps *release* so the
            // menu is not dismissed by the still-held Hyper modifiers (see debug log).
            if keyCode == KeyCode.v {
                HyperDebug.log(
                    "HYPER+V swallow f18Held=\(f18Held) physical=\(physicallyHeld) grace=\(withinGrace) → defer menu until Caps up"
                )
                HyperLog.event("HYPER+V → clipboard history (defer until Caps release)")
                SnippetEngine.shared.resetBuffer()
                scheduleClipboardMenuAfterCapsRelease()
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
        if !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskAlternate)
            && !VimNavigation.shared.isActive
        {
            let chars = event.keyboardGetUnicodeString()

            // ── Stuck Caps Lock LED + V (your debug log) ─────────────────
            // With Karabiner Caps→F18, Caps never toggles the LED. If the LED is
            // latched ON, users think "Hyper is on" and press ⇧V — but f18Held is
            // false, so V types as capital V. Treat that as Hyper+V: swallow V,
            // clear the LED, open the clipboard menu.
            if keyCode == KeyCode.v, type == .keyDown {
                let alpha = flags.contains(.maskAlphaShift)
                HyperDebug.log(
                    "V without Hyper f18Held=\(f18Held) hyperActive=\(isHyperActive) alphaShift=\(alpha) flags=\(flags.rawValue)"
                )
                // Stuck Caps Lock LED looks like Hyper is "on" but f18Held is false.
                // Real Hyper hold always logs CAPS/F18 down first — your logs never had that.
                if alpha {
                    EventSynthesizer.clearCapsLockIfLatched()
                    HyperDebug.log("V + stuck CapsLock LED → treat as Hyper+V")
                    SnippetEngine.shared.resetBuffer()
                    scheduleClipboardMenuAfterCapsRelease()
                    DispatchQueue.main.async {
                        Banner.show(
                            "Clipboard",
                            subtitle: "Caps Lock LED was on (not Hyper). Hold Caps, then V next time.",
                            style: .warning,
                            symbol: "list.clipboard",
                            duration: 2.6
                        )
                    }
                    return nil
                }
            }

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
            // Drop stale activations after softClearHyperHold.
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

    /// True while a HyperForge NSMenu / clipboard panel is up, or just closed.
    var shouldSuppressSysLock: Bool {
        lock.lock()
        defer { lock.unlock() }
        return menuSessionDepth > 0
            || clipboardPanelVisible
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

    /// Clipboard / Hyper menu open flag (suppresses Hyper+Esc → lock).
    func noteClipboardPanelVisible(_ visible: Bool) {
        lock.lock()
        clipboardPanelVisible = visible
        if visible {
            menuSessionDepth = max(menuSessionDepth, 1)
        } else {
            menuSessionDepth = 0
            suppressSysLockUntil = Date().addingTimeInterval(menuDismissLockSuppressSeconds)
        }
        lock.unlock()
        HyperLog.event("clipboardPanelVisible=\(visible)")
    }

    /// Hyper+V while Caps held: queue panel, open on Caps keyUp only.
    private func scheduleClipboardMenuAfterCapsRelease() {
        pendingClipboardTimeout?.cancel()
        pendingClipboardMenu = true
        HyperDebug.log("clipboard menu scheduled (waiting for Caps release)")

        // Caps already up → open next turn.
        if !f18Held {
            flushPendingClipboardMenu()
            return
        }

        // Fallback if Caps keyUp is lost.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingClipboardMenu else { return }
            HyperDebug.log("clipboard menu fallback timeout (Caps keyUp missing?)")
            self.flushPendingClipboardMenu()
        }
        pendingClipboardTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func flushPendingClipboardMenu() {
        guard pendingClipboardMenu else { return }
        pendingClipboardMenu = false
        pendingClipboardTimeout?.cancel()
        pendingClipboardTimeout = nil
        HyperDebug.log("clipboard menu flush → show")
        DispatchQueue.main.async {
            ClipboardHistoryPanel.show()
        }
    }

    /// After NSMenu.popUp returns: Caps keyUp was often eaten — treat Hyper as released.
    func resyncHyperAfterMenu() {
        lock.lock()
        f18Held = false
        _hyperActive = false
        lastHyperSeenTime = .distantPast
        clipboardPanelVisible = false
        menuSessionDepth = 0
        hyperUIGeneration &+= 1
        let gen = hyperUIGeneration
        lock.unlock()
        HyperLog.event("resyncHyperAfterMenu")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let g = self.hyperUIGeneration
            self.lock.unlock()
            guard g == gen else { return }
            self.hyperKeyActive = false
            HyperBindingsHUD.setHyperHeld(false)
        }
    }

    /// Call when dismissing dashboard / chrome with Esc so Hyper+V works afterwards.
    func prepareAfterUIDismiss(reason: String) {
        lock.lock()
        menuSessionDepth = 0
        clipboardPanelVisible = false
        pendingMenuOpener = nil
        lastHyperSeenTime = .distantPast
        lock.unlock()
        pendingMenuTimeout?.cancel()
        pendingMenuTimeout = nil
        ClipboardHistoryPanel.setTracking(false)

        // Debug log proved: after dashboard Esc, alphaShift was still true and the next
        // Shift+V leaked as capital V with no CAPS/F18 down. Clear latched Caps Lock LED
        // (user cannot toggle it via Caps while Karabiner owns Caps→F18).
        let alpha = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        HyperDebug.log("prepareAfterUIDismiss: \(reason) alphaShift=\(alpha)")
        if alpha {
            EventSynthesizer.clearCapsLockIfLatched()
            DispatchQueue.main.async {
                Banner.show(
                    "Caps Lock was on",
                    subtitle: "Cleared — hold Caps for Hyper, then V",
                    style: .warning,
                    symbol: "capslock",
                    duration: 2.2
                )
            }
        }
        HyperLog.event("prepareAfterUIDismiss: \(reason)")
    }

    /// Modal NSMenu session (quick menu / shortcuts / transforms).
    func beginMenuSession() {
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
            resyncHyperAfterMenu()
        }
    }

    /// Emergency recovery (menu bar).
    func resetHyperState() {
        lock.lock()
        menuSessionDepth = 0
        clipboardPanelVisible = false
        pendingMenuOpener = nil
        f18Held = false
        _hyperActive = false
        lastHyperSeenTime = .distantPast
        hyperUIGeneration &+= 1
        let gen = hyperUIGeneration
        lock.unlock()
        pendingMenuTimeout?.cancel()
        pendingMenuTimeout = nil
        EventSynthesizer.releaseStuckHyperKeys()
        EventSynthesizer.clearCapsLockIfLatched()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let g = self.hyperUIGeneration
            self.lock.unlock()
            if g == gen {
                self.hyperKeyActive = false
                HyperBindingsHUD.setHyperHeld(false)
            }
            ClipboardHistoryPanel.hide()
            Banner.show(
                "Hyper reset",
                subtitle: "Latch cleared",
                style: .success,
                symbol: "arrow.clockwise"
            )
        }
        HyperLog.event("resetHyperState")
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
        softClearHyperHold(reason: "menu-flush")
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

    /// Clear sticky grace only (not Caps/F18 physical hold).
    func softClearHyperHold(reason: String) {
        lock.lock()
        lastHyperSeenTime = .distantPast
        let held = f18Held
        if !held {
            _hyperActive = false
            hyperUIGeneration &+= 1
        }
        let gen = hyperUIGeneration
        lock.unlock()
        HyperLog.event("softClearHyperHold: \(reason) f18Held=\(held)")
        if !held {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let g = self.hyperUIGeneration
                self.lock.unlock()
                guard g == gen else { return }
                self.hyperKeyActive = false
                HyperBindingsHUD.setHyperHeld(false)
            }
        }
    }

    /// Drop sticky Hyper after a finished chord (Caps not held).
    private func endStickyHyper() {
        softClearHyperHold(reason: "end-sticky")
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
