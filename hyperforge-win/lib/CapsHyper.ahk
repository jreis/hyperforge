; CapsHyper.ahk — Caps Lock as Hyper (#^!+), alone can still be remapped by other tools

InitCapsHyper() {
    if !HFConfig.GetBool("general.caps_to_hyper", true)
        return
    SetCapsLockState "AlwaysOff"

    ; Optionally suspend Caps→Hyper in muted apps (games-friendly)
    if HFConfig.GetBool("mute.caps_too", true)
        HotIf HyperAllowed
    Hotkey "*CapsLock", CapsHyperDown
    Hotkey "*CapsLock up", CapsHyperUp
    if HFConfig.GetBool("mute.caps_too", true)
        HotIf
}

CapsHyperDown(*) {
    SetKeyDelay -1
    Send "{Blind}{Ctrl Down}{Alt Down}{Shift Down}{LWin Down}"
    KeyWait "CapsLock"
}

CapsHyperUp(*) {
    SetKeyDelay -1
    Send "{Blind}{Ctrl Up}{Alt Up}{Shift Up}{LWin Up}"
}
