; Window.ahk — snaps, undo, next monitor, always-on-top, minimize

global HF_SnapUndo := Map()  ; hwnd string → array of {x,y,w,h}
global HF_SnapUndoMax := 8

RegisterWindowHotkeys() {
    ; Non-Hyper (always available)
    Hotkey "^+Space", (*) => {
        static WS_EX_TOPMOST := 0x8
        WinSetAlwaysOnTop -1, "A"
        if WinGetExStyle("A") & WS_EX_TOPMOST
            ShowMsg("Always on top ON")
        else
            ShowMsg("Always on top OFF")
    }
    Hotkey "*XButton1", (*) => {
        try WinMinimize("A")
    }

    ; Hyper chords — respect per-app mute
    HotIf HyperAllowed
    Hotkey "#^!+Left", (*) => SnapActive(0, 0, 0.5, 1)
    Hotkey "#^!+Right", (*) => SnapActive(0.5, 0, 0.5, 1)
    Hotkey "#^!+Up", (*) => SnapActive(0, 0, 1, 0.5)
    Hotkey "#^!+Down", (*) => SnapActive(0, 0.5, 1, 0.5)
    Hotkey "#^!+Enter", (*) => SnapActive(0, 0, 1, 1)
    ; Quarters (Mac-style 7/8/9/0)
    Hotkey "#^!+7", (*) => SnapActive(0, 0, 0.5, 0.5)      ; top-left
    Hotkey "#^!+8", (*) => SnapActive(0.5, 0, 0.5, 0.5)    ; top-right
    Hotkey "#^!+9", (*) => SnapActive(0, 0.5, 0.5, 0.5)    ; bottom-left
    Hotkey "#^!+0", (*) => SnapActive(0.5, 0.5, 0.5, 0.5)  ; bottom-right
    ; Center (keep size)
    Hotkey "#^!+.", (*) => CenterActive()
    ; Undo last snap for this window
    Hotkey "#^!+z", (*) => UndoSnap()
    ; Next / previous monitor
    Hotkey "#^!+]", (*) => MoveActiveToMonitor(1)
    Hotkey "#^!+[", (*) => MoveActiveToMonitor(-1)
    HotIf
}

PushUndo(hwnd) {
    global HF_SnapUndo, HF_SnapUndoMax
    key := String(hwnd)
    try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch
        return
    if !HF_SnapUndo.Has(key)
        HF_SnapUndo[key] := []
    stack := HF_SnapUndo[key]
    stack.Push({ x: x, y: y, w: w, h: h })
    while stack.Length > HF_SnapUndoMax
        stack.RemoveAt(1)
    HF_SnapUndo[key] := stack
}

UndoSnap(*) {
    global HF_SnapUndo
    hwnd := WinExist("A")
    if !hwnd {
        ShowMsg("No window")
        return
    }
    key := String(hwnd)
    if !HF_SnapUndo.Has(key) || !HF_SnapUndo[key].Length {
        ShowMsg("Nothing to undo")
        return
    }
    stack := HF_SnapUndo[key]
    pos := stack.Pop()
    HF_SnapUndo[key] := stack
    WinMove pos.x, pos.y, pos.w, pos.h, "ahk_id " hwnd
    ShowMsg("Undo snap")
}

SnapActive(rx, ry, rw, rh) {
    hwnd := WinExist("A")
    if !hwnd
        return
    PushUndo(hwnd)
    GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    w := R - L, h := B - T
    x := L + Round(w * rx)
    y := T + Round(h * ry)
    nw := Round(w * rw)
    nh := Round(h * rh)
    try WinRestore("ahk_id " hwnd)
    WinMove x, y, nw, nh, "ahk_id " hwnd
}

CenterActive() {
    hwnd := WinExist("A")
    if !hwnd
        return
    PushUndo(hwnd)
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    aw := R - L, ah := B - T
    nx := L + (aw - w) // 2
    ny := T + (ah - h) // 2
    try WinRestore("ahk_id " hwnd)
    WinMove nx, ny, w, h, "ahk_id " hwnd
    ShowMsg("Centered")
}

GetWindowWorkArea(hwnd, &L, &T, &R, &B) {
    MonitorGetWorkArea(, &L, &T, &R, &B)
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        cx := wx + ww // 2, cy := wy + wh // 2
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if (cx >= l && cx < r && cy >= t && cy < b) {
                L := l, T := t, R := r, B := b
                return A_Index
            }
        }
    }
    return 1
}

; delta +1 = next monitor, -1 = previous
MoveActiveToMonitor(delta) {
    hwnd := WinExist("A")
    if !hwnd
        return
    count := MonitorGetCount()
    if (count < 2) {
        ShowMsg("One monitor only")
        return
    }
    PushUndo(hwnd)
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    cur := GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    next := cur + delta
    if (next > count)
        next := 1
    if (next < 1)
        next := count
    MonitorGetWorkArea(next, &nl, &nt, &nr, &nb)
    MonitorGetWorkArea(cur, &cl, &ct, &cr, &cb)
    ; Preserve relative position within work area
    relX := (wx - cl) / Max(cr - cl, 1)
    relY := (wy - ct) / Max(cb - ct, 1)
    nw := Min(ww, nr - nl)
    nh := Min(wh, nb - nt)
    nx := nl + Round(relX * (nr - nl - nw))
    ny := nt + Round(relY * (nb - nt - nh))
    ; Clamp
    nx := Max(nl, Min(nx, nr - nw))
    ny := Max(nt, Min(ny, nb - nh))
    try WinRestore("ahk_id " hwnd)
    WinMove nx, ny, nw, nh, "ahk_id " hwnd
    ShowMsg("Monitor " next "/" count)
}
