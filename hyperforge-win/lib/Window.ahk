; Window.ahk — always-on-top, minimize, optional snaps

RegisterWindowHotkeys() {
    ; Ctrl+Shift+Space — toggle always on top (from your original)
    Hotkey "^+Space", (*) => {
        static WS_EX_TOPMOST := 0x8
        WinSetAlwaysOnTop -1, "A"
        if WinGetExStyle("A") & WS_EX_TOPMOST
            ShowMsg("Always on top ON")
        else
            ShowMsg("Always on top OFF")
    }

    ; XButton1 — minimize active (from your original)
    Hotkey "*XButton1", (*) => {
        try WinMinimize("A")
    }

    ; Optional Hyper snaps (Mac muscle memory) — Hyper+Left/Right/Up/Down
    Hotkey "#^!+Left", (*) => SnapActive(0, 0, 0.5, 1)
    Hotkey "#^!+Right", (*) => SnapActive(0.5, 0, 0.5, 1)
    Hotkey "#^!+Up", (*) => SnapActive(0, 0, 1, 0.5)
    Hotkey "#^!+Down", (*) => SnapActive(0, 0.5, 1, 0.5)
    Hotkey "#^!+Enter", (*) => SnapActive(0, 0, 1, 1)
}

SnapActive(rx, ry, rw, rh) {
    hwnd := WinExist("A")
    if !hwnd
        return
    mon := MonitorGetWorkArea(, &L, &T, &R, &B)
    ; Use monitor of window
    try {
        WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        ; find monitor containing center
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            cx := wx + ww // 2, cy := wy + wh // 2
            if (cx >= l && cx < r && cy >= t && cy < b) {
                L := l, T := t, R := r, B := b
                break
            }
        }
    }
    w := R - L, h := B - T
    x := L + Round(w * rx)
    y := T + Round(h * ry)
    nw := Round(w * rw)
    nh := Round(h * rh)
    WinMove x, y, nw, nh, hwnd
}
