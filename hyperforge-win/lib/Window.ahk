; Window.ahk — snaps, undo, next monitor, always-on-top, minimize, tile-all.
; Positions are the visible frame. DWM's invisible resize border is added back
; so a half-snap sits flush with the work area instead of leaving a shadow gap.

global HF_UndoStack := []
global HF_UndoMax := 8

RegisterWindowHotkeys() {
    Hotkey "^+Space", (*) => ToggleAlwaysOnTop()
    ; Off by default: XButton1 is the mouse Back button. Hyper+B still minimizes.
    if HFConfig.GetBool("general.xbutton1_minimize", false)
        Hotkey "*XButton1", (*) => MinimizeActive()

    BindHyper("Left", (*) => SnapActive(0, 0, 0.5, 1))
    BindHyper("Right", (*) => SnapActive(0.5, 0, 0.5, 1))
    BindHyper("Up", (*) => SnapActive(0, 0, 1, 0.5))
    BindHyper("Down", (*) => SnapActive(0, 0.5, 1, 0.5))
    BindHyper("Enter", (*) => SnapActive(0, 0, 1, 1))
    ; Top-row quarters (macOS main keyboard 7/8/9/0): TL TR BL BR
    BindHyper("7", (*) => SnapActive(0, 0, 0.5, 0.5))
    BindHyper("8", (*) => SnapActive(0.5, 0, 0.5, 0.5))
    BindHyper("9", (*) => SnapActive(0, 0.5, 0.5, 0.5))
    BindHyper("0", (*) => SnapActive(0.5, 0.5, 0.5, 0.5))
    BindHyper("6", (*) => TileAllVisible())
    ; Numpad spatial pad:
    ;   7 TL    8 Top    9 TR
    ;   4 Left  5 Max    6 Right
    ;   1 BL    2 Bot    3 BR
    ;   0 Center
    BindHyper("Numpad7", (*) => SnapActive(0, 0, 0.5, 0.5))
    BindHyper("Numpad8", (*) => SnapActive(0, 0, 1, 0.5))
    BindHyper("Numpad9", (*) => SnapActive(0.5, 0, 0.5, 0.5))
    BindHyper("Numpad4", (*) => SnapActive(0, 0, 0.5, 1))
    BindHyper("Numpad5", (*) => SnapActive(0, 0, 1, 1))
    BindHyper("Numpad6", (*) => SnapActive(0.5, 0, 0.5, 1))
    BindHyper("Numpad1", (*) => SnapActive(0, 0.5, 0.5, 0.5))
    BindHyper("Numpad2", (*) => SnapActive(0, 0.5, 1, 0.5))
    BindHyper("Numpad3", (*) => SnapActive(0.5, 0.5, 0.5, 0.5))
    BindHyper("Numpad0", (*) => CenterActive())
    BindHyper(".", (*) => CenterActive())
    ; Thirds / two-thirds / almost-max. Shift is already part of Hyper, so the
    ; 2/3 and almost-max chords are i / o / u rather than a Shift variant.
    BindHyper("-", (*) => SnapThird(0))
    BindHyper("=", (*) => SnapThird(2))
    BindHyper("\", (*) => SnapThird(1))
    BindHyper("i", (*) => SnapTwoThirds(true))
    BindHyper("o", (*) => SnapTwoThirds(false))
    BindHyper("u", (*) => AlmostMaximize())
    BindHyper("a", (*) => ToggleAlwaysOnTop())
    BindHyper("b", (*) => MinimizeActive())
    BindHyper("z", (*) => UndoSnap())
    BindHyper("]", (*) => MoveActiveToMonitor(1))
    BindHyper("[", (*) => MoveActiveToMonitor(-1))
}

MinimizeActive(*) {
    try WinMinimize("A")
}

CloseActive(*) {
    try WinClose("A")
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

; Newest batch at the end. Each batch is an array of placement maps.
; One snap is a batch of one; tile-all is a batch of every window it moved.
UndoPush(stack, batch, max := 8) {
    stack.Push(batch)
    while stack.Length > max
        stack.RemoveAt(1)
    return stack
}

CaptureWindowPlacement(hwnd) {
    state := 0
    try state := WinGetMinMax("ahk_id " hwnd)
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    return { hwnd: hwnd, x: x, y: y, w: w, h: h, state: state }
}

RememberWindow(hwnd) {
    global HF_UndoStack, HF_UndoMax
    try UndoPush(HF_UndoStack, [CaptureWindowPlacement(hwnd)], HF_UndoMax)
}

RememberWindows(placements) {
    global HF_UndoStack, HF_UndoMax
    if placements.Length
        UndoPush(HF_UndoStack, placements, HF_UndoMax)
}

RestorePlacement(entry) {
    if !WinExist("ahk_id " entry.hwnd)
        return false
    try {
        if (entry.state = 1)
            WinMaximize("ahk_id " entry.hwnd)
        else if (entry.state = -1)
            WinMinimize("ahk_id " entry.hwnd)
        else
            WinMove entry.x, entry.y, entry.w, entry.h, "ahk_id " entry.hwnd
        return true
    } catch {
        return false
    }
}

UndoSnap(*) {
    global HF_UndoStack
    if !HF_UndoStack.Length {
        ShowMsg("Nothing to undo")
        return
    }
    batch := HF_UndoStack.Pop()
    restored := 0
    for entry in batch {
        if RestorePlacement(entry)
            restored++
    }
    if !restored
        ShowMsg("Nothing to undo")
    else if (batch.Length > 1)
        ShowMsg("Undo tile layout")
    else
        ShowMsg("Undo snap")
}

TileAllVisible(*) {
    active := WinExist("A")
    if !active {
        ShowMsg("No window")
        return
    }
    GetWindowWorkArea(active, &L, &T, &R, &B)
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
            style := WinGetStyle("ahk_id " hwnd)
            if !(style & 0xC00000)  ; WS_CAPTION
                continue
            GetWindowWorkArea(hwnd, &wl, &wt, &wr, &wb)
            if (wl != L || wt != T)
                continue
            wins.Push(hwnd)
        }
    }
    n := wins.Length
    if (n < 1) {
        ShowMsg("Nothing to tile")
        return
    }

    placements := []
    for hwnd in wins {
        try placements.Push(CaptureWindowPlacement(hwnd))
    }
    RememberWindows(placements)

    cols := Ceil(Sqrt(n))
    rows := Ceil(n / cols)
    cellW := aw // cols
    cellH := ah // rows
    for i, hwnd in wins {
        idx := i - 1
        col := Mod(idx, cols)
        row := idx // cols
        nx := L + col * cellW
        ny := T + row * cellH
        MoveWindowVisible(hwnd, nx, ny, cellW, cellH)
    }
    ShowMsg("Tiled " n " windows")
}

SnapActive(rx, ry, rw, rh) {
    hwnd := WinExist("A")
    if !hwnd
        return
    RememberWindow(hwnd)
    GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    w := R - L, h := B - T
    MoveWindowVisible(hwnd, L + Round(w * rx), T + Round(h * ry), Round(w * rw), Round(h * rh))
}

SnapThird(column) {
    col := Max(0, Min(2, column))
    SnapActive(col / 3, 0, 1 / 3, 1)
    labels := ["Left third", "Center third", "Right third"]
    ShowMsg(labels[col + 1])
}

SnapTwoThirds(leading) {
    if leading {
        SnapActive(0, 0, 2 / 3, 1)
        ShowMsg("Left two-thirds")
    } else {
        SnapActive(1 / 3, 0, 2 / 3, 1)
        ShowMsg("Right two-thirds")
    }
}

AlmostMaximize(inset := 0.05) {
    m := Max(0.02, Min(0.2, inset))
    SnapActive(m, m, 1 - 2 * m, 1 - 2 * m)
    ShowMsg("Almost maximize (" Round((1 - 2 * m) * 100) "% centered)")
}

CenterActive() {
    hwnd := WinExist("A")
    if !hwnd
        return
    RememberWindow(hwnd)
    try if (WinGetMinMax("ahk_id " hwnd) != 0) {
        WinRestore("ahk_id " hwnd)
        Sleep 30
    }
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    m := WindowFrameMargins(hwnd)
    visW := Max(40, w - m.l - m.r)
    visH := Max(40, h - m.t - m.b)
    GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    aw := R - L, ah := B - T
    MoveWindowVisible(hwnd, L + (aw - visW) // 2, T + (ah - visH) // 2, visW, visH)
    ShowMsg("Centered")
}

; margins.l/t/r/b: how far the Win32 window rect extends past the visible frame.
; Positive left means the window rect starts that many pixels left of the visible edge.
FrameMarginsFromRects(wx, wy, ww, wh, vl, vt, vr, vb) {
    return { l: vl - wx, t: vt - wy, r: (wx + ww) - vr, b: (wy + wh) - vb }
}

VisibleMoveRect(x, y, w, h, m) {
    return { x: x - m.l, y: y - m.t, w: w + m.l + m.r, h: h + m.t + m.b }
}

ClampFrameMargin(v) {
    if (v < -40 || v > 80)
        return 0
    return v
}

WindowFrameMargins(hwnd) {
    zero := { l: 0, t: 0, r: 0, b: 0 }
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        buf := Buffer(16, 0)
        ; DWMWA_EXTENDED_FRAME_BOUNDS = 9. Same coordinate space as WinGetPos
        ; because AHK v2 is per-monitor DPI aware.
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 9, "ptr", buf, "uint", 16, "int")
        if (hr != 0)
            return zero
        m := FrameMarginsFromRects(wx, wy, ww, wh, NumGet(buf, 0, "Int"), NumGet(buf, 4, "Int"), NumGet(buf, 8, "Int"), NumGet(buf, 12, "Int"))
        return {
            l: ClampFrameMargin(m.l),
            t: ClampFrameMargin(m.t),
            r: ClampFrameMargin(m.r),
            b: ClampFrameMargin(m.b)
        }
    } catch {
        return zero
    }
}

; x,y,w,h are the visible rectangle we want on screen.
MoveWindowVisible(hwnd, x, y, w, h) {
    if (w < 40 || h < 40)
        return
    try {
        if (WinGetMinMax("ahk_id " hwnd) != 0) {
            WinRestore("ahk_id " hwnd)
            Sleep 30
        }
    }
    rect := VisibleMoveRect(x, y, w, h, WindowFrameMargins(hwnd))
    try WinMove rect.x, rect.y, rect.w, rect.h, "ahk_id " hwnd
    catch
        ShowMsg("Can't move this window")
}

GetWindowWorkArea(hwnd, &L, &T, &R, &B) {
    primary := MonitorGetPrimary()
    MonitorGetWorkArea(primary, &L, &T, &R, &B)
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
    return primary
}

MoveActiveToMonitor(delta) {
    hwnd := WinExist("A")
    if !hwnd
        return
    count := MonitorGetCount()
    if (count < 2) {
        ShowMsg("One monitor only")
        return
    }
    RememberWindow(hwnd)
    wasMax := false
    try wasMax := (WinGetMinMax("ahk_id " hwnd) = 1)
    cur := GetWindowWorkArea(hwnd, &L, &T, &R, &B)
    next := cur + delta
    if (next > count)
        next := 1
    if (next < 1)
        next := count
    MonitorGetWorkArea(next, &nl, &nt, &nr, &nb)
    if wasMax {
        try WinRestore("ahk_id " hwnd)
        WinMove nl + 20, nt + 20, Max(200, (nr - nl) // 2), Max(150, (nb - nt) // 2), "ahk_id " hwnd
        try WinMaximize("ahk_id " hwnd)
        ShowMsg("Monitor " next "/" count)
        return
    }
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    m := WindowFrameMargins(hwnd)
    visW := Max(40, ww - m.l - m.r)
    visH := Max(40, wh - m.t - m.b)
    visX := wx + m.l
    visY := wy + m.t
    relX := (visX - L) / Max(R - L, 1)
    relY := (visY - T) / Max(B - T, 1)
    visW := Min(visW, nr - nl)
    visH := Min(visH, nb - nt)
    nx := nl + Round(relX * Max(nr - nl - visW, 0))
    ny := nt + Round(relY * Max(nb - nt - visH, 0))
    nx := Max(nl, Min(nx, nr - visW))
    ny := Max(nt, Min(ny, nb - visH))
    MoveWindowVisible(hwnd, nx, ny, visW, visH)
    ShowMsg("Monitor " next "/" count)
}
