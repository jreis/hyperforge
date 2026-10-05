; Utils.ahk — toasts, encoding, small helpers

; One toast, bottom-center of the monitor under the pointer. A new toast
; replaces the previous one so rapid snaps don't stack windows in the corner.
ShowMsg(text) {
    global HF_Toast, HF_ToastGen
    if !HFConfig.GetBool("general.toasts", true)
        return
    HF_ToastGen++
    mine := HF_ToastGen
    if IsObject(HF_Toast) {
        try HF_Toast.Destroy()
        HF_Toast := 0
    }
    g := Gui("+AlwaysOnTop +ToolWindow -Caption")
    HF_Toast := g
    g.MarginX := 16
    g.MarginY := 10
    g.BackColor := "1c1c1c"
    g.SetFont("s11 cEEEEEE", "Segoe UI")
    g.AddText("w340 Center Background1c1c1c", text)
    g.Show("AutoSize Hide")
    tw := 360, th := 48
    try WinGetPos(, , &tw, &th, "ahk_id " g.Hwnd)
    mx := 0, my := 0
    try MouseGetPos(&mx, &my)
    mon := MonitorGetPrimary()
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (mx >= l && mx < r && my >= t && my < b) {
            mon := A_Index
            break
        }
    }
    MonitorGetWorkArea(mon, &L, &T, &R, &B)
    x := L + (R - L - tw) // 2
    y := B - th - 28
    g.Show("x" x " y" y " NoActivate")
    SetTimer(DismissToast.Bind(mine), -1400)
}

DismissToast(expected, *) {
    global HF_Toast, HF_ToastGen
    if (expected != HF_ToastGen)
        return
    if IsObject(HF_Toast) {
        try HF_Toast.Destroy()
        HF_Toast := 0
    }
}

UrlEncode(str, sExcepts := "-_.", enc := "UTF-8") {
    hex := "00", func := "msvcrt\swprintf"
    buff := Buffer(StrPut(str, enc)), StrPut(str, buff, enc)
    encoded := ""
    Loop {
        if (!b := NumGet(buff, A_Index - 1, "UChar"))
            break
        if (b >= 0x41 && b <= 0x5A
            || b >= 0x61 && b <= 0x7A
            || b >= 0x30 && b <= 0x39
            || InStr(sExcepts, Chr(b), true))
            encoded .= Chr(b)
        else {
            DllCall(func, "Str", hex, "Str", "%%%02X", "UChar", b, "Cdecl")
            encoded .= hex
        }
    }
    return encoded
}

UrlDecode(Url, Enc := "UTF-8") {
    Pos := 1
    Loop {
        Pos := RegExMatch(Url, "i)(?:%[\da-f]{2})+", &code, Pos++)
        if (Pos = 0)
            break
        code := code[0]
        var := Buffer(StrLen(code) // 3, 0)
        code := SubStr(code, 2)
        loop Parse code, "`%"
            NumPut("UChar", Integer("0x" . A_LoopField), var, A_Index - 1)
        Url := StrReplace(Url, "`%" code, StrGet(var, Enc))
    }
    return Url
}

GenerateFileName() {
    return FormatTime(, "yyyyMMddHHmmss") Random(1000, 9999)
}

RandomStr(len := 12) {
    s := ""
    Loop len
        s .= Chr(Random(0x61, 0x7A))
    return s
}

Base64Encode(str) {
    ; CRYPT_STRING_BASE64 alone inserts a CRLF every 64 characters, which splits
    ; clipboard-history lines and corrupts anything longer than ~48 bytes on reload.
    n := StrPut(str, "UTF-8") - 1
    if (n <= 0)
        return ""
    buf := Buffer(n)
    StrPut(str, buf, "UTF-8")
    flags := 0x40000001  ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size,
        "UInt", flags, "Ptr", 0, "UInt*", &cch := 0)
        return ""
    out := Buffer(cch * 2)
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size,
        "UInt", flags, "Ptr", out, "UInt*", &cch)
        return ""
    return Trim(StrGet(out, "UTF-16"), "`r`n")
}

Base64Decode(b64) {
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1,
        "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        return ""
    buf := Buffer(size)
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 0x1,
        "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        return ""
    return StrGet(buf, size, "UTF-8")
}

NormalizeNewlines(text) {
    text := StrReplace(text, "`r`n", "`n")
    return StrReplace(text, "`r", "`n")
}

; Arrow keys move the list while the filter edit keeps focus.
global HF_NavHwnd := 0
global HF_NavList := 0
global HF_NavCount := 0
global HF_NavOnDelete := ""
global HF_Toast := 0
global HF_ToastGen := 0

InstallGuiNav() {
    static ready := false
    if ready
        return
    ready := true
    HotIf (*) => HF_NavHwnd && WinActive("ahk_id " HF_NavHwnd)
    Hotkey "Up", (*) => GuiNavMove(-1)
    Hotkey "Down", (*) => GuiNavMove(1)
    Hotkey "^Del", (*) => GuiNavDelete()
    HotIf
}

GuiNavAttach(gui, list, onDelete := "") {
    global HF_NavHwnd, HF_NavList, HF_NavOnDelete
    InstallGuiNav()
    HF_NavHwnd := gui.Hwnd
    HF_NavList := list
    HF_NavOnDelete := onDelete
}

GuiNavDetach(gui) {
    global HF_NavHwnd, HF_NavList, HF_NavCount, HF_NavOnDelete
    id := 0
    try id := gui.Hwnd
    if (id && HF_NavHwnd = id) {
        HF_NavHwnd := 0
        HF_NavList := 0
        HF_NavCount := 0
        HF_NavOnDelete := ""
    }
}

GuiNavSetCount(n) {
    global HF_NavCount
    HF_NavCount := n
}

GuiNavMove(delta) {
    global HF_NavList, HF_NavCount
    if !IsObject(HF_NavList) || HF_NavCount < 1
        return
    cur := HF_NavList.Value
    if (cur < 1)
        cur := 1
    next := cur + delta
    if (next < 1)
        next := 1
    if (next > HF_NavCount)
        next := HF_NavCount
    HF_NavList.Choose(next)
}

GuiNavDelete() {
    global HF_NavOnDelete
    if HasMethod(HF_NavOnDelete, "Call")
        HF_NavOnDelete.Call()
}

CredRead(name) {
    pCred := 0
    DllCall("Advapi32.dll\CredReadW", "Str", name, "UInt", 1, "UInt", 0, "Ptr*", &pCred, "UInt")
    if !pCred
        return
    name := StrGet(NumGet(pCred, 8 + A_PtrSize * 0, "UPtr"), 256, "UTF-16")
    username := StrGet(NumGet(pCred, 24 + A_PtrSize * 6, "UPtr"), 256, "UTF-16")
    len := NumGet(pCred, 16 + A_PtrSize * 2, "UInt")
    password := StrGet(NumGet(pCred, 16 + A_PtrSize * 3, "UPtr"), len / 2, "UTF-16")
    DllCall("Advapi32.dll\CredFree", "Ptr", pCred)
    return { name: name, username: username, password: password }
}
