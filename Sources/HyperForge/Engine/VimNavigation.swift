// VimNavigation.swift
// System-wide Vim-style navigation while Right ⌘ is held.
// Ported from hyperkey.swift handleVimKey — thread-safe for CGEvent tap.

import CoreGraphics
import Foundation

final class VimNavigation: @unchecked Sendable {
    static let shared = VimNavigation()

    private let lock = NSLock()
    private var _isActive = false
    private var dWaiting = false
    private var ggWaiting = false
    private var zWaiting = false

    private let halfPage: Int32 = 300
    private let fullPage: Int32 = 600
    private let alignAmount: Int32 = 800

    private init() {}

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isActive
    }

    func setActive(_ active: Bool) {
        lock.lock()
        _isActive = active
        if !active {
            dWaiting = false
            ggWaiting = false
            zWaiting = false
        }
        lock.unlock()
    }

    /// Returns true if the key was consumed.
    @discardableResult
    func handle(keyCode: CGKeyCode, shiftDown: Bool, ctrlDown: Bool) -> Bool {
        guard isActive else { return false }

        if ctrlDown {
            switch keyCode {
            case KeyCode.d:
                EventSynthesizer.postScroll(dy: -halfPage)
                return true
            case KeyCode.u:
                EventSynthesizer.postScroll(dy: halfPage)
                return true
            case KeyCode.f:
                EventSynthesizer.postScroll(dy: -fullPage)
                return true
            case KeyCode.b:
                EventSynthesizer.postScroll(dy: fullPage)
                return true
            default:
                return false
            }
        }

        if shiftDown {
            switch keyCode {
            case KeyCode.h:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskShift)
                return true
            case KeyCode.j:
                EventSynthesizer.postKey(KeyCode.downArrow, flags: .maskShift)
                return true
            case KeyCode.k:
                EventSynthesizer.postKey(KeyCode.upArrow, flags: .maskShift)
                return true
            case KeyCode.l:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskShift)
                return true
            case KeyCode.b:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: [.maskAlternate, .maskShift])
                return true
            case KeyCode.e:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskAlternate, .maskShift])
                return true
            case KeyCode.zero:
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: [.maskCommand, .maskShift])
                return true
            case KeyCode.four:
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskCommand, .maskShift])
                return true
            case KeyCode.g:
                EventSynthesizer.postKey(KeyCode.downArrow, flags: .maskCommand)
                return true
            case KeyCode.x:
                EventSynthesizer.postKey(KeyCode.forwardDelete)
                return true
            default:
                return false
            }
        }

        switch keyCode {
        case KeyCode.h:
            EventSynthesizer.postKey(KeyCode.leftArrow)
            return true
        case KeyCode.j:
            EventSynthesizer.postKey(KeyCode.downArrow)
            return true
        case KeyCode.k:
            EventSynthesizer.postKey(KeyCode.upArrow)
            return true
        case KeyCode.l:
            EventSynthesizer.postKey(KeyCode.rightArrow)
            return true

        case KeyCode.semicolon:
            EventSynthesizer.postKey(KeyCode.t, flags: [.maskCommand, .maskAlternate])
            return true

        case KeyCode.e:
            if takeDWaiting() {
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskAlternate, .maskShift])
                EventSynthesizer.postKey(KeyCode.delete)
            } else {
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskAlternate)
            }
            return true

        case KeyCode.b:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: -alignAmount)
            } else if takeDWaiting() {
                EventSynthesizer.postKey(KeyCode.delete, flags: .maskAlternate)
            } else {
                EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskAlternate)
            }
            return true

        case KeyCode.zero:
            EventSynthesizer.postKey(KeyCode.leftArrow, flags: .maskCommand)
            return true
        case KeyCode.four:
            EventSynthesizer.postKey(KeyCode.rightArrow, flags: .maskCommand)
            return true
        case KeyCode.x:
            EventSynthesizer.postKey(KeyCode.delete)
            return true

        case KeyCode.d:
            setDWaiting()
            return true

        case KeyCode.w:
            if takeDWaiting() {
                EventSynthesizer.postKey(KeyCode.rightArrow, flags: [.maskControl, .maskShift])
                EventSynthesizer.postKey(KeyCode.delete)
            }
            return true

        case KeyCode.g:
            if takeGGWaiting() {
                EventSynthesizer.postKey(KeyCode.upArrow, flags: .maskCommand)
            } else {
                setGGWaiting()
            }
            return true

        case KeyCode.t:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: alignAmount)
                return true
            }
            DispatchQueue.main.async { AppLauncher.shared.launchPreferredTerminal() }
            return true

        case KeyCode.z:
            if takeZWaiting() {
                EventSynthesizer.postScroll(dy: alignAmount / 2)
            } else {
                setZWaiting()
            }
            return true

        default:
            return false
        }
    }

    // MARK: - Operator state (locked)

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
