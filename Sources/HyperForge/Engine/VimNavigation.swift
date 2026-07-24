// VimNavigation.swift
// TouchCursor-style navigation: hold Space as a layer, then vim motions.
// Space alone still types a space (emitted on key-up if no layer key was used).
// Replaces the old Right-⌘ hold mode.

import CoreGraphics
import Foundation

final class VimNavigation: @unchecked Sendable {
    static let shared = VimNavigation()

    private let lock = NSLock()
    /// We swallowed Space keyDown (pending or armed).
    private var spaceDown = false
    /// Layer accepts nav keys only after hold threshold (never on early key rollover).
    private var layerArmed = false
    /// True if nav mapping ran, or we already emitted a typing space (suppress second space).
    private var layerUsed = false
    /// Space held but a letter arrived before arm — pass keys until Space up.
    private var typingRollover = false
    /// Master enable — Settings / defaults.
    private var _enabled = true
    private var armWorkItem: DispatchWorkItem?
    private var spaceDownAt: Date?
    private var layerArmedAt: Date?
    /// Last time a non-Space key was typed (for inter-word hold boost).
    private var lastTypingKeyAt: Date?
    /// Ignore next N Space edges from our own synthetic posts (backup if pass-through races).
    private var ignoreSyntheticSpaceEdges = 0

    private var dWaiting = false
    private var ggWaiting = false
    private var zWaiting = false

    private let halfPage: Int32 = 300
    private let fullPage: Int32 = 600
    private let alignAmount: Int32 = 800
    /// After rapid typing, require this much extra hold before Space becomes a layer.
    private let interWordBoostMs = 80
    /// If the first key after arm arrives within this window, treat as typing not nav
    /// (finger still finishing a long space tap).
    private let postArmTypingGraceMs = 90.0

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            _enabled = true
        } else {
            _enabled = defaults.bool(forKey: Self.enabledKey)
        }
    }

    static let enabledKey = "hf.spaceNavEnabled"

    /// True while we own the Space keyDown (pending, armed, or typing rollover).
    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return spaceDown
    }

    /// Layer is ready for navigation chords (hold threshold elapsed).
    var isLayerArmed: Bool {
        lock.lock(); defer { lock.unlock() }
        return spaceDown && layerArmed && !typingRollover
    }

    var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _enabled
    }

    func setEnabled(_ enabled: Bool, persist: Bool = true) {
        lock.lock()
        _enabled = enabled
        if !enabled {
            resetSpaceStateUnlocked()
        }
        lock.unlock()
        if persist {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        }
    }

    /// Live-test path: temporarily force layer active for a single handle() call.
    func setActive(_ active: Bool) {
        lock.lock()
        cancelArmTimerUnlocked()
        spaceDown = active
        layerArmed = active
        typingRollover = false
        spaceDownAt = active ? Date() : nil
        layerArmedAt = active ? Date() : nil
        if !active {
            layerUsed = false
            clearOperatorsUnlocked()
        }
        lock.unlock()
    }

    // MARK: - Space key (typing-safe SpaceFN protocol)

    /// - Returns: `true` if the event should be swallowed by the tap.
    @discardableResult
    func handleSpaceKeyDown(
        shiftOnlyOrNone: Bool,
        hyperActive: Bool
    ) -> Bool {
        lock.lock()
        if ignoreSyntheticSpaceEdges > 0 {
            ignoreSyntheticSpaceEdges -= 1
            lock.unlock()
            return false
        }
        lock.unlock()

        guard isEnabled, !hyperActive, shiftOnlyOrNone else { return false }
        // Per-app block list / App Override (terminals, Vim, …).
        guard SpaceNavRuntime.shared.shouldCaptureSpace() else { return false }

        // Hold threshold: 0 = arm immediately (power mode). Default ~200ms for typing.
        var holdMs = SpaceNavRuntime.shared.holdMilliseconds
        lock.lock()
        // Mid-word / inter-word: recent key → need a longer intentional hold to arm nav.
        if holdMs > 0, let last = lastTypingKeyAt,
           Date().timeIntervalSince(last) < 0.14
        {
            holdMs += interWordBoostMs
        }
        cancelArmTimerUnlocked()
        spaceDown = true
        layerUsed = false
        typingRollover = false
        spaceDownAt = Date()
        layerArmedAt = nil
        clearOperatorsUnlocked()
        if holdMs <= 0 {
            layerArmed = true
            layerArmedAt = Date()
        } else {
            layerArmed = false
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.spaceDown, !self.typingRollover, !self.layerUsed {
                    self.layerArmed = true
                    self.layerArmedAt = Date()
                }
                self.lock.unlock()
            }
            armWorkItem = work
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(holdMs),
                execute: work
            )
        }
        lock.unlock()
        return true
    }

    /// - Returns: `true` if the keyUp should be swallowed (always when we owned the down).
    @discardableResult
    func handleSpaceKeyUp() -> Bool {
        lock.lock()
        if ignoreSyntheticSpaceEdges > 0 {
            ignoreSyntheticSpaceEdges -= 1
            lock.unlock()
            return false
        }
        cancelArmTimerUnlocked()
        let owned = spaceDown
        // Emit a typed space only if we never navigated and never flushed for rollover typing
        // (rollover already emitted one space when the next key arrived).
        let emitSpace = owned && !layerUsed && !typingRollover
        let swallow = owned
        resetSpaceStateUnlocked()
        lock.unlock()

        guard swallow else { return false }
        if emitSpace {
            emitTypedSpace()
        }
        return true
    }

    /// Cancel pending space without emitting (e.g. engine stop).
    func cancelSpaceLayer() {
        lock.lock()
        resetSpaceStateUnlocked()
        lock.unlock()
    }

    /// Mark that something used the layer so Space will not type a character.
    func markLayerUsed() {
        lock.lock()
        layerUsed = true
        typingRollover = false
        cancelArmTimerUnlocked()
        lock.unlock()
    }

    private func resetSpaceStateUnlocked() {
        cancelArmTimerUnlocked()
        spaceDown = false
        layerArmed = false
        layerUsed = false
        typingRollover = false
        spaceDownAt = nil
        layerArmedAt = nil
        clearOperatorsUnlocked()
    }

    private func cancelArmTimerUnlocked() {
        armWorkItem?.cancel()
        armWorkItem = nil
    }

    /// Inject a real space character; ignore re-entry on the event tap.
    private func emitTypedSpace() {
        lock.lock()
        ignoreSyntheticSpaceEdges += 2
        lock.unlock()
        EventSynthesizer.postKey(KeyCode.space)
    }

    /// Convert pending/armed Space into normal typing: one space, then pass the key.
    private func beginTypingRolloverUnlocked() {
        cancelArmTimerUnlocked()
        typingRollover = true
        layerUsed = true
        layerArmed = false
        clearOperatorsUnlocked()
    }

    // MARK: - Layer keys

    /// Returns true if the key was consumed as a navigation action.
    /// Before the hold threshold, returns false after flushing a typed space (fast-typist safe).
    @discardableResult
    func handle(keyCode: CGKeyCode, shiftDown: Bool, ctrlDown: Bool) -> Bool {
        lock.lock()
        guard spaceDown else {
            lastTypingKeyAt = Date()
            lock.unlock()
            return false
        }

        // Already decided this Space is part of normal typing — don't steal keys.
        if typingRollover {
            lastTypingKeyAt = Date()
            lock.unlock()
            return false
        }

        // Fast typing: next key while Space still in the hold window → type space + letter.
        if !layerArmed {
            beginTypingRolloverUnlocked()
            lock.unlock()
            emitTypedSpace()
            return false
        }

        // Barely armed (long space tap that just crossed threshold) + first key → still typing.
        if !layerUsed, let armedAt = layerArmedAt,
           Date().timeIntervalSince(armedAt) * 1000 < postArmTypingGraceMs
        {
            beginTypingRolloverUnlocked()
            lock.unlock()
            emitTypedSpace()
            return false
        }

        lock.unlock()

        if ctrlDown {
            switch keyCode {
            case KeyCode.d:
                EventSynthesizer.postScroll(dy: -halfPage)
                markLayerUsed()
                return true
            case KeyCode.u:
                EventSynthesizer.postScroll(dy: halfPage)
                markLayerUsed()
                return true
            case KeyCode.f:
                EventSynthesizer.postScroll(dy: -fullPage)
                markLayerUsed()
                return true
            case KeyCode.b:
                EventSynthesizer.postScroll(dy: fullPage)
                markLayerUsed()
                return true
            default:
                return false
            }
        }

        if shiftDown {
            switch keyCode {
            case KeyCode.h:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskShift)
                markLayerUsed()
                return true
            case KeyCode.j:
                EventSynthesizer.postKey(KeyCode.downArrow, flags: .maskShift)
                markLayerUsed()
                return true
            case KeyCode.k:
                EventSynthesizer.postKey(KeyCode.upArrow, flags: .maskShift)
                markLayerUsed()
                return true
            case KeyCode.l:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskShift)
                markLayerUsed()
                return true
            case KeyCode.b:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: [.maskAlternate, .maskShift])
                markLayerUsed()
                return true
            case KeyCode.e:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskAlternate, .maskShift])
                markLayerUsed()
                return true
            case KeyCode.zero:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: [.maskCommand, .maskShift])
                markLayerUsed()
                return true
            case KeyCode.four:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskCommand, .maskShift])
                markLayerUsed()
                return true
            case KeyCode.g:
                EventSynthesizer.postKey(KeyCode.downArrow, flags: .maskCommand)
                markLayerUsed()
                return true
            case KeyCode.x:
                // Kill to start of line (mirror of Space+X → EOL).
                Self.killToStartOfLine()
                markLayerUsed()
                return true
            case KeyCode.y:
                Self.copyLine()
                markLayerUsed()
                return true
            case KeyCode.n:
                // Find previous
                EventSynthesizer.postKey(KeyCode.g, flags: [.maskCommand, .maskShift])
                markLayerUsed()
                return true
            case KeyCode.p:
                // Paste and match style (common Mac)
                EventSynthesizer.postKey(KeyCode.v, flags: [.maskCommand, .maskShift, .maskAlternate])
                markLayerUsed()
                return true
            default:
                return false
            }
        }

        switch keyCode {
        case KeyCode.h:
            EventSynthesizer.postKey(KeyCode.leftArrow)
            markLayerUsed()
            return true
        case KeyCode.j:
            EventSynthesizer.postKey(KeyCode.downArrow)
            markLayerUsed()
            return true
        case KeyCode.k:
            EventSynthesizer.postKey(KeyCode.upArrow)
            markLayerUsed()
            return true
        case KeyCode.l:
            EventSynthesizer.postKey(KeyCode.rightArrow)
            markLayerUsed()
            return true

        case KeyCode.semicolon:
            EventSynthesizer.postKey(KeyCode.t, flags: [.maskCommand, .maskAlternate])
            markLayerUsed()
            return true

        case KeyCode.e:
            if takeDWaiting() {
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskAlternate, .maskShift])
                EventSynthesizer.postKey(KeyCode.delete)
            } else {
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskAlternate)
            }
            markLayerUsed()
            return true

        case KeyCode.b:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: -alignAmount)
            } else if takeDWaiting() {
                EventSynthesizer.postKey(KeyCode.delete, flags: .maskAlternate)
            } else {
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskAlternate)
            }
            markLayerUsed()
            return true

        case KeyCode.zero, KeyCode.i:
            // 0 / i → line start (i ≈ “insert at home”)
            EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskCommand)
            markLayerUsed()
            return true
        case KeyCode.four, KeyCode.o:
            // 4 / o → line end (TouchCursor-style O)
            EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskCommand)
            markLayerUsed()
            return true

        case KeyCode.x:
            // Kill to end of line (vim D / readline ⌃K)
            Self.killToEndOfLine()
            markLayerUsed()
            return true

        case KeyCode.d:
            if takeDWaiting() {
                // dd → kill whole line
                Self.killLine()
            } else {
                setDWaiting()
            }
            markLayerUsed()
            return true

        case KeyCode.w:
            if takeDWaiting() {
                // dw → delete word forward
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskAlternate, .maskShift])
                EventSynthesizer.postKey(KeyCode.delete)
            } else {
                // Word forward
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskAlternate)
            }
            markLayerUsed()
            return true

        case KeyCode.g:
            if takeGGWaiting() {
                EventSynthesizer.postKey(KeyCode.upArrow, flags: .maskCommand)
            } else {
                setGGWaiting()
            }
            markLayerUsed()
            return true

        case KeyCode.t:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: alignAmount)
                markLayerUsed()
                return true
            }
            DispatchQueue.main.async { AppLauncher.shared.launchPreferredTerminal() }
            markLayerUsed()
            return true

        case KeyCode.z:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: alignAmount / 2)
            } else {
                setZWaiting()
            }
            markLayerUsed()
            return true

        // ── Editing / system (TouchCursor extras) ──────────────────────
        case KeyCode.u:
            EventSynthesizer.postKey(KeyCode.z, flags: .maskCommand) // Undo
            markLayerUsed()
            return true
        case KeyCode.r:
            EventSynthesizer.postKey(KeyCode.z, flags: [.maskCommand, .maskShift]) // Redo
            markLayerUsed()
            return true
        case KeyCode.y:
            EventSynthesizer.postKey(KeyCode.c, flags: .maskCommand) // Yank / copy
            markLayerUsed()
            return true
        case KeyCode.p:
            EventSynthesizer.postKey(KeyCode.v, flags: .maskCommand) // Paste
            markLayerUsed()
            return true
        case KeyCode.c:
            EventSynthesizer.postKey(KeyCode.x, flags: .maskCommand) // Cut
            markLayerUsed()
            return true
        case KeyCode.a:
            Self.selectLine()
            markLayerUsed()
            return true
        case KeyCode.s:
            EventSynthesizer.postKey(KeyCode.s, flags: .maskCommand) // Save
            markLayerUsed()
            return true
        case KeyCode.f:
            EventSynthesizer.postKey(KeyCode.f, flags: .maskCommand) // Find
            markLayerUsed()
            return true
        case KeyCode.n:
            EventSynthesizer.postKey(KeyCode.g, flags: .maskCommand) // Find next
            markLayerUsed()
            return true
        case KeyCode.q, KeyCode.escape:
            EventSynthesizer.postKey(KeyCode.escape)
            markLayerUsed()
            return true
        case KeyCode.m, KeyCode.return:
            EventSynthesizer.postKey(KeyCode.return)
            markLayerUsed()
            return true
        case KeyCode.tab:
            EventSynthesizer.postKey(KeyCode.tab)
            markLayerUsed()
            return true
        case KeyCode.delete:
            // Space + ⌫ → backspace (char left)
            EventSynthesizer.postKey(KeyCode.delete)
            markLayerUsed()
            return true
        case KeyCode.forwardDelete:
            EventSynthesizer.postKey(KeyCode.forwardDelete)
            markLayerUsed()
            return true
        case KeyCode.comma:
            EventSynthesizer.postKey(KeyCode.pageUp)
            markLayerUsed()
            return true
        case KeyCode.period:
            EventSynthesizer.postKey(KeyCode.pageDown)
            markLayerUsed()
            return true
        case KeyCode.home:
            EventSynthesizer.postKey(KeyCode.home)
            markLayerUsed()
            return true
        case KeyCode.end:
            EventSynthesizer.postKey(KeyCode.end)
            markLayerUsed()
            return true

        default:
            // Unmapped key while layer armed: treat as typing (don't drop the space).
            lock.lock()
            if !layerUsed {
                beginTypingRolloverUnlocked()
                lock.unlock()
                emitTypedSpace()
            } else {
                lastTypingKeyAt = Date()
                lock.unlock()
            }
            return false
        }
    }

    // MARK: - Line / kill helpers (macOS-universal key chords)

    private static func killToEndOfLine() {
        EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskCommand, .maskShift])
        EventSynthesizer.postKey(KeyCode.delete)
    }

    private static func killToStartOfLine() {
        EventSynthesizer.postKey(KeyCode.leftArrow, flags: [.maskCommand, .maskShift])
        EventSynthesizer.postKey(KeyCode.delete)
    }

    private static func killLine() {
        EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskCommand)
        EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskCommand, .maskShift])
        EventSynthesizer.postKey(KeyCode.delete)
        // Drop the leftover newline when the app leaves one behind.
        EventSynthesizer.postKey(KeyCode.forwardDelete)
    }

    private static func selectLine() {
        EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskCommand)
        EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskCommand, .maskShift])
    }

    private static func copyLine() {
        selectLine()
        EventSynthesizer.postKey(KeyCode.c, flags: .maskCommand)
    }

    // MARK: - Operator state

    private func clearOperatorsUnlocked() {
        dWaiting = false
        ggWaiting = false
        zWaiting = false
    }

    private func setDWaiting() {
        lock.lock(); dWaiting = true; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.lock.lock(); self?.dWaiting = false; self?.lock.unlock()
        }
    }

    private func takeDWaiting() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if dWaiting { dWaiting = false; return true }
        return false
    }

    private func setGGWaiting() {
        lock.lock(); ggWaiting = true; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.lock.lock(); self?.ggWaiting = false; self?.lock.unlock()
        }
    }

    private func takeGGWaiting() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if ggWaiting { ggWaiting = false; return true }
        return false
    }

    private func setZWaiting() {
        lock.lock(); zWaiting = true; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.lock.lock(); self?.zWaiting = false; self?.lock.unlock()
        }
    }

    private func takeZWaiting() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if zWaiting { zWaiting = false; return true }
        return false
    }
}
