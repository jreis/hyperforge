; Utils.ahk — toasts, encoding, small helpers

ShowMsg(text) {
    if !HFConfig.GetBool("general.toasts", true)
        return
    g := Gui("+AlwaysOnTop +ToolWindow -Caption")
    g.SetFont("s11")
    g.AddText("w260 Center", text)
    g.Show("x0 y0 NoActivate")
    SetTimer(() => (g.Hide(), g.Destroy()), -1200)
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
    buf := Buffer(StrPut(str, "UTF-8") - 1)
    StrPut(str, buf, "UTF-8")
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size,
        "UInt", 0x1, "Ptr", 0, "UInt*", &cch := 0)
        return ""
    out := Buffer(cch * 2)
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size,
        "UInt", 0x1, "Ptr", out, "UInt*", &cch)
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
