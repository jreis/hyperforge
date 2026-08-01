; Window.ahk — snaps, undo, next monitor, always-on-top, minimize, tile-all
; Muscle memory aligned with macOS HyperForge where keys don't fight app chords.

global HF_SnapUndo := Map()  ; hwnd string → array of {x,y,w,h}
global HF_SnapUndoMax := 8
global HF_TileLayout := []   ; array of {hwnd,x,y,w,h} for undo after tile-all

RegisterWindowHotkeys() {
    ; Non-Hyper (always available)
    Hotkey "^+Space", (*) => ToggleAlwaysOnTop()
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
    ; Top-row quarters (same as macOS main keyboard 7/8/9/0)
    Hotkey "#^!+7", (*) => SnapActive(0, 0, 0.5, 0.5)      ; top-left
    Hotkey "#^!+8", (*) => SnapActive(0.5, 0, 0.5, 0.5)    ; top-right
    Hotkey "#^!+9", (*) => SnapActive(0, 0.5, 0.5, 0.5)    ; bottom-left
    Hotkey "#^!+0", (*) => SnapActive(0.5, 0.5, 0.5, 0.5)  ; bottom-right
    ; Hyper + 6 = tile all (macOS parity)
    Hotkey "#^!+6", (*) => TileAllVisible()
    ; Full numpad spatial pad (macOS 0.4.x):
    ;   7 TL    8 Top    9 TR
    ;   4 Left  5 Max    6 Right
    ;   1 BL    2 Bot    3 BR
    ;   0 Center
    Hotkey "#^!+Numpad7", (*) => SnapActive(0, 0, 0.5, 0.5)
    Hotkey "#^!+Numpad8", (*) => SnapActive(0, 0, 1, 0.5)
    Hotkey "#^!+Numpad9", (*) => SnapActive(0.5, 0, 0.5, 0.5)
    Hotkey "#^!+Numpad4", (*) => SnapActive(0, 0, 0.5, 1)
    Hotkey "#^!+Numpad5", (*) => SnapActive(0, 0, 1, 1)
    Hotkey "#^!+Numpad6", (*) => SnapActive(0.5, 0, 0.5, 1)
    Hotkey "#^!+Numpad1", (*) => SnapActive(0, 0.5, 0.5, 0.5)
    Hotkey "#^!+Numpad2", (*) => SnapActive(0, 0.5, 1, 0.5)
    Hotkey "#^!+Numpad3", (*) => SnapActive(0.5, 0.5, 0.5, 0.5)
    Hotkey "#^!+Numpad0", (*) => CenterActive()
    ; Center (keep size) — period (legacy Win) also works
    Hotkey "#^!+.", (*) => CenterActive()
    ; Always on top / minimize — Mac Hyper+A / Hyper+B
    Hotkey "#^!+a", (*) => ToggleAlwaysOnTop()
    Hotkey "#^!+b", (*) => {
        try WinMinimize("A")
    }
    ; Undo last snap for this window (or last tile-all layout)
    Hotkey "#^!+z", (*) => UndoSnap()
    ; Next / previous monitor
    Hotkey "#^!+]", (*) => MoveActiveToMonitor(1)
    Hotkey "#^!+[", (*) => MoveActiveToMonitor(-1)
    HotIf
}

ToggleAlwaysOnTop(*) {
    static WS_EX_TOPMOST := 0x8
    try {
        WinSetAlwaysOnTop -1, "A"
        if WinGetExStyle("A") & WS_EX_TOPMOST
            ShowMsg("Always on top ON")
        else
            ShowMsg("Always on top OFF")
    }
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
    global HF_SnapUndo, HF_TileLayout
    ; Prefer restoring tile-all layout when present
    if IsSet(HF_TileLayout) && HF_TileLayout.Length {
        for entry in HF_TileLayout {
            try {
                if WinExist("ahk_id " entry.hwnd)
                    WinMove entry.x, entry.y, entry.w, entry.h, "ahk_id " entry.hwnd
            }
        }
        HF_TileLayout := []
        ShowMsg("Undo tile layout")
        return
    }
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

; Grid every visible (non-minimized) window on the active window's monitor.
TileAllVisible(*) {
    global HF_TileLayout
    active := WinExist("A")
    if !active {
        ShowMsg("No window")
        return
    }
    mon := GetWindowWorkArea(active, &L, &T, &R, &B)
    aw := R - L, ah := B - T
    if (aw < 50 || ah < 50)
        return

    wins := []
    for hwnd in WinGetList() {
        try {
            if !WinExist("ahk_id " hwnd)
                continue
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (title = "")
                continue
            class := WinGetClass("ahk_id " hwnd)
            if (class = "Progman" || class = "WorkerW" || class = "Shell_TrayWnd"
                || class = "Shell_SecondaryTrayWnd" || class = "Windows.UI.Core.CoreWindow")
                continue
            ; Prefer normal app windows (caption + size box)
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0xC00000)  ; WS_CAPTION
                continue
            ; Same monitor only
            GetWindowWorkArea(hwnd, &wl, &wt, &wr, &wb)
            if (wl != L || wt != T)
                continue
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            wins.Push({ hwnd: hwnd, x: x, y: y, w: w, h: h })
        }
    }
    n := wins.Length
    if (n < 1) {
        ShowMsg("Nothing to tile")
        return
    }

    HF_TileLayout := []
    for w in wins
        HF_TileLayout.Push({ hwnd: w.hwnd, x: w.x, y: w.y, w: w.w, h: w.h })

    cols := Ceil(Sqrt(n))
    rows := Ceil(n / cols)
    cellW := aw // cols
    cellH := ah // rows
    for i, w in wins {
        idx := i - 1
        col := Mod(idx, cols)
        row := idx // cols
        nx := L + col * cellW
        ny := T + row * cellH
        try WinRestore("ahk_id " w.hwnd)
        WinMove nx, ny, cellW, cellH, "ahk_id " w.hwnd
    }
    ShowMsg("Tiled " n " windows")
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
