; CapsHyper.ahk — Caps Lock as Hyper (#^!+).
; A bare tap sends Escape (macOS Karabiner to_if_alone). LWin is masked on the
; way up so that tap does not open the Start menu.

global HF_CapsHyperDown := false

InitCapsHyper() {
    ; The default mask is LCtrl, which injects a Ctrl keystroke into every Win release.
    A_MenuMaskKey := "vkE8"
    if !HFConfig.GetBool("general.caps_to_hyper", true)
        return
    SetCapsLockState "AlwaysOff"

    if HFConfig.GetBool("mute.caps_too", true)
        HotIf HyperAllowed
    Hotkey "*CapsLock", CapsHyperDown
    Hotkey "*CapsLock up", CapsHyperUp
    if HFConfig.GetBool("mute.caps_too", true)
        HotIf
}

CapsHyperDown(*) {
    global HF_CapsHyperDown
    if !HyperAllowed() {
        ; caps_too=0 while paused or muted: Caps Lock still toggles, once per hold.
        HF_CapsHyperDown := false
        Send "{CapsLock}"
        KeyWait "CapsLock"
        return
    }
    HF_CapsHyperDown := true
    SetKeyDelay -1
    Send "{Blind}{Ctrl Down}{Alt Down}{Shift Down}{LWin Down}"
    KeyWait "CapsLock"
}

CapsHyperUp(*) {
    global HF_CapsHyperDown
    if !HF_CapsHyperDown
        return
    HF_CapsHyperDown := false
    alone := (A_PriorKey = "CapsLock")
    SetKeyDelay -1
    ; vkE8 before LWin up marks the press as a chord, so Start stays closed.
    Send "{Blind}{vkE8}{Ctrl Up}{Alt Up}{Shift Up}{LWin Up}"
    if alone && HFConfig.GetBool("general.caps_tap_escape", true)
        Send "{Esc}"
}

; Drop the modifiers this script is holding. Physical 4-mod chords (caps_to_hyper=0)
; are left alone — those keys belong to the user.
ReleaseHyperModifiers() {
    global HF_CapsHyperDown
    if !HF_CapsHyperDown
        return
    SetKeyDelay -1
    Send "{Blind}{vkE8}{Ctrl Up}{Alt Up}{Shift Up}{LWin Up}"
}

RestoreHyperModifiers() {
    global HF_CapsHyperDown
    if !HF_CapsHyperDown || !GetKeyState("CapsLock", "P")
        return
    SetKeyDelay -1
    Send "{Blind}{Ctrl Down}{Alt Down}{Shift Down}{LWin Down}"
}

; mode:
;   snap — act now, swallow key-repeat, leave Hyper modifiers down for the next chord
;   send — wait until the trigger key is up, drop modifiers, act, then restore if Caps is held
;   ui   — same as send, but leave modifiers up until EndHyperUi (so the window can be typed in)
BindHyper(key, fn, mode := "snap") {
    ; A bound function is not a legal Hotkey callback on AHK v2.0. A fat arrow is.
    ; Clear HotIf even if registration throws, so later hotkeys are not stuck conditional.
    HotIf HyperAllowed
    try Hotkey "#^!+" key, (*) => HyperInvoke(fn, mode)
    finally HotIf
}

HyperInvoke(fn, mode, *) {
    if (mode != "snap") {
        HyperWaitTrigger()
        ReleaseHyperModifiers()
    }
    try fn.Call()
    finally {
        if (mode = "snap")
            HyperWaitTrigger()
        else if (mode != "ui")
            RestoreHyperModifiers()
    }
}

HyperWaitTrigger() {
    key := RegExReplace(A_ThisHotkey, "^#\^!\+")
    if (key = "" || key = A_ThisHotkey)
        return
    if GetKeyState(key, "P")
        KeyWait key
}

BeginHyperUi(g) {
    ReleaseHyperModifiers()
    g.OnEvent("Close", EndHyperUi)
}

EndHyperUi(g, *) {
    static busy := Map()
    if !IsObject(g)
        return
    id := 0
    try id := g.Hwnd
    if busy.Has(id)
        return
    busy[id] := true
    GuiNavDetach(g)
    try {
        if (id && WinExist("ahk_id " id))
            g.Destroy()
    }
    RestoreHyperModifiers()
    busy.Delete(id)
}
