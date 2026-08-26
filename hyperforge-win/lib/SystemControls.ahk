; SystemControls.ahk — volume / brightness / mute (native OS HUD via media-key Send),
; Focus toggle, and virtual-desktop (Space) switching. Wired into the XButton2 Quick
; Menu only — mirrors macOS HyperForge, which also exposes these via Quick Menu /
; Command Bar rather than a dedicated Hyper chord (both platforms already have native
; hardware volume/brightness keys, so a chord would just be a second way to do the
; same thing).

VolumeUp(*) {
    Send "{Volume_Up}"
}

VolumeDown(*) {
    Send "{Volume_Down}"
}

ToggleMute(*) {
    Send "{Volume_Mute}"
}

; Best-effort — WMI brightness control only reaches the internal panel on most
; laptops (no DDC/CI for external monitors without a third-party tool).
BrightnessUp(*) {
    _adjustBrightness(10)
}

BrightnessDown(*) {
    _adjustBrightness(-10)
}

_adjustBrightness(delta) {
    try {
        wmi := ComObjGet("winmgmts:\\.\root\wmi")
        for m in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightness") {
            target := Max(0, Min(100, m.CurrentBrightness + delta))
            for method in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods") {
                method.WmiSetBrightness(1, target)
            }
            ShowMsg("Brightness " target "%")
            return
        }
    } catch {
        ; fall through to the not-supported message below
    }
    ShowMsg("Brightness control not supported on this display")
}

; Runs shortcuts\Toggle Focus.ps1 if present — same named-script convention as
; HF_RunShortcut() in Scripts (HFBridge.ahk); Windows has no public Focus/DND API
; either, so a user-authored script is the sanctioned escape hatch here too.
ToggleFocus(*) {
    dir := A_ScriptDir "\shortcuts"
    ps1 := dir "\Toggle Focus.ps1"
    if FileExist(ps1) {
        Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '"'
    } else {
        ShowMsg('No "Toggle Focus" shortcut — add ' ps1)
    }
}

NextSpace(*) {
    Send "^#{Right}"
    ShowMsg("Next Space")
}

PreviousSpace(*) {
    Send "^#{Left}"
    ShowMsg("Previous Space")
}
