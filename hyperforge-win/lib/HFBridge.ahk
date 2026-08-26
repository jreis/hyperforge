; HFBridge.ahk — `HF_*` verbs for user Scripts (Hyper + Y), mirrors macOS HyperForge's
; `HF.*` JavaScript bridge (ScriptStore.swift) one-for-one where a Windows equivalent
; exists. Each Scripts\*.ahk file runs as its own AutoHotkey process (see Scripts.ahk),
; so this is a plain #Include, not a shared-state API — every call re-resolves the
; active window / clipboard / config fresh.
;
;   #Include "%A_ScriptDir%\..\lib\HFBridge.ahk"   (or the absolute path Scripts.ahk seeds)
;
; HF_Snap(position)       — "left" "right" "top" "bottom" "max" "center"
;                            "tl" "tr" "bl" "br" "thirdLeft" "thirdCenter" "thirdRight"
;                            "twoThirdsLeft" "twoThirdsRight" "almostMax"
; HF_Notify(message)      — toast (respects general.toasts like the rest of HyperForge)
; HF_Log(message)         — appends to scripts.log under %APPDATA%\HyperForge
; HF_ClipboardGet()       — current clipboard text
; HF_ClipboardSet(text)   — replace clipboard text
; HF_PasteText(text)      — set clipboard then send Ctrl+V
; HF_PressKey(chord)      — Send() a chord verbatim, AHK syntax (e.g. "^!4", "{F5}")
; HF_LaunchApp(pathOrExe) — run / focus / minimize-cycle, same as Hyper app-launch chords
; HF_RunShortcut(name)    — run "<shortcuts_dir>\<name>.ps1" (Windows has no Shortcuts.app;
;                            named PowerShell scripts are the closest reusable-action analog)
; HF_Sleep(ms)

HF_Snap(position) {
    hwnd := WinExist("A")
    if !hwnd
        return false
    if (position = "center") {
        MonitorGetWorkArea(, &L, &T, &R, &B)
        HF_CenterActiveWindow(hwnd, L, T, R, B)
        return true
    }
    rect := HF_SnapRect(position)
    if !IsObject(rect)
        return false
    MonitorGetWorkArea(, &L, &T, &R, &B)
    w := R - L, h := B - T
    x := L + Round(w * rect.rx), y := T + Round(h * rect.ry)
    nw := Round(w * rect.rw), nh := Round(h * rect.rh)
    try WinRestore("ahk_id " hwnd)
    WinMove x, y, nw, nh, "ahk_id " hwnd
    return true
}

; rx/ry/rw/rh are fractions of the work area (0..1) — same layout as macOS WindowManager.
HF_SnapRect(position) {
    switch position {
        case "left":           return { rx: 0,   ry: 0,   rw: 0.5, rh: 1 }
        case "right":          return { rx: 0.5, ry: 0,   rw: 0.5, rh: 1 }
        case "top":            return { rx: 0,   ry: 0,   rw: 1,   rh: 0.5 }
        case "bottom":         return { rx: 0,   ry: 0.5, rw: 1,   rh: 0.5 }
        case "max":            return { rx: 0,   ry: 0,   rw: 1,   rh: 1 }
        case "tl":             return { rx: 0,   ry: 0,   rw: 0.5, rh: 0.5 }
        case "tr":             return { rx: 0.5, ry: 0,   rw: 0.5, rh: 0.5 }
        case "bl":             return { rx: 0,   ry: 0.5, rw: 0.5, rh: 0.5 }
        case "br":             return { rx: 0.5, ry: 0.5, rw: 0.5, rh: 0.5 }
        case "thirdLeft":       return { rx: 0,   ry: 0, rw: 1/3, rh: 1 }
        case "thirdCenter":     return { rx: 1/3, ry: 0, rw: 1/3, rh: 1 }
        case "thirdRight":      return { rx: 2/3, ry: 0, rw: 1/3, rh: 1 }
        case "twoThirdsLeft":   return { rx: 0,   ry: 0, rw: 2/3, rh: 1 }
        case "twoThirdsRight":  return { rx: 1/3, ry: 0, rw: 2/3, rh: 1 }
        case "almostMax":       return { rx: 0.05, ry: 0.05, rw: 0.9, rh: 0.9 }
        default:                return false
    }
}

HF_CenterActiveWindow(hwnd, L, T, R, B) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    aw := R - L, ah := B - T
    nx := L + (aw - w) // 2
    ny := T + (ah - h) // 2
    try WinRestore("ahk_id " hwnd)
    WinMove nx, ny, w, h, "ahk_id " hwnd
}

HF_Notify(message) {
    g := Gui("+AlwaysOnTop +ToolWindow -Caption")
    g.SetFont("s11")
    g.AddText("w260 Center", message)
    g.Show("x0 y0 NoActivate")
    SetTimer(() => (g.Hide(), g.Destroy()), -1200)
}

HF_Log(message) {
    dir := A_AppData "\HyperForge"
    if !DirExist(dir)
        DirCreate(dir)
    FileAppend(FormatTime() " " message "`n", dir "\scripts.log", "UTF-8")
}

HF_ClipboardGet() {
    return A_Clipboard
}

HF_ClipboardSet(text) {
    A_Clipboard := text
}

HF_PasteText(text) {
    A_Clipboard := text
    Sleep 50
    Send "^v"
}

HF_PressKey(chord) {
    Send chord
}

HF_LaunchApp(pathOrExe) {
    exeOnly := pathOrExe
    if RegExMatch(pathOrExe, 'i)^("[^"]+"|[^ ]+\.exe)', &m)
        exeOnly := Trim(m[1], '"')
    SplitPath exeOnly, &exeFile
    if (exeFile = "") {
        Run pathOrExe
        return
    }
    pid := ProcessExist(exeFile)
    if (pid = 0) {
        Run pathOrExe
        return
    }
    SetTitleMatchMode 2
    DetectHiddenWindows false
    if WinActive("ahk_pid " pid)
        WinMinimize "ahk_pid " pid
    else if WinExist("ahk_pid " pid)
        WinActivate "ahk_pid " pid
}

HF_RunShortcut(name) {
    dir := A_ScriptDir "\..\shortcuts"
    ps1 := dir "\" name ".ps1"
    if !FileExist(ps1) {
        HF_Notify('No shortcut "' name '" — add ' ps1)
        return
    }
    Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '"'
}

HF_Sleep(ms) {
    Sleep Max(0, ms)
}
