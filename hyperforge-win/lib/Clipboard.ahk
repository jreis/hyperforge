; Clipboard.ahk — paste transform menu (generic)

RegisterClipboardHotkeys() {
    Hotkey "^+!v", ShowPasteMenu
}

ShowPasteMenu(*) {
    m := Menu()
    m.Add("Linefeeds → commas", PasteLinefeedsToCommas)
    m.Add('Linefeeds → "quoted", commas', PasteLinefeedsToQuotedCommas)
    m.Add("Linefeeds → semicolons", PasteLinefeedsToSemicolons)
    m.Add("Linefeeds → spaces", PasteLinefeedsToSpaces)
    m.Add("Tabs → commas", PasteTabsToCommas)
    m.Add("Tabs → linefeeds", PasteTabsToLinefeeds)
    m.Add()
    m.Add("Plain text", PastePlainText)
    m.Add("Base64 encode", PasteBase64)
    m.Add("Base64 decode", PasteBase64Dec)
    m.Add("URL encode", PasteUrlEncode)
    m.Add("URL decode", PasteUrlDecode)
    m.Add("Replace chars…", PasteReplaceChars)
    m.Add("Values → search OR list", PasteValuesToSearch)
    m.Add("Unix timestamp ↔ date", PasteUnixTimestamp)
    m.Add("Google clipboard", PasteGoogle)
    m.Show()
}

_pasteTransformed(newText) {
    A_Clipboard := newText
    Sleep 50
    Send "^v"
}

PasteLinefeedsToCommas(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`r`n", ","))
}
PasteLinefeedsToQuotedCommas(*) {
    parts := []
    for line in StrSplit(A_Clipboard, "`n", "`r") {
        if (line != "")
            parts.Push('"' StrReplace(line, '"', '\"') '"')
    }
    _pasteTransformed(Join(parts, ","))
}
PasteLinefeedsToSemicolons(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`r`n", ";"))
}
PasteLinefeedsToSpaces(*) {
    t := StrReplace(A_Clipboard, "`r`n", " ")
    t := StrReplace(t, "`n", " ")
    _pasteTransformed(t)
}
PasteTabsToCommas(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`t", ","))
}
PasteTabsToLinefeeds(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`t", "`r`n"))
}
PastePlainText(*) {
    t := A_Clipboard
    A_Clipboard := t
    Sleep 30
    Send "^v"
}
PasteBase64(*) {
    _pasteTransformed(Base64Encode(A_Clipboard))
}
PasteBase64Dec(*) {
    _pasteTransformed(Base64Decode(A_Clipboard))
}
PasteUrlEncode(*) {
    _pasteTransformed(UrlEncode(A_Clipboard))
}
PasteUrlDecode(*) {
    _pasteTransformed(UrlDecode(A_Clipboard))
}
PasteGoogle(*) {
    Run ChromeCmd() ' "https://www.google.com/search?q=' UrlEncode(A_Clipboard) '"'
}
PasteReplaceChars(*) {
    ib := InputBox("Replace char / string (find)", "Paste replace", , ",")
    if ib.Result != "OK"
        return
    find := ib.Value
    ib2 := InputBox("Replace with", "Paste replace", , ";")
    if ib2.Result != "OK"
        return
    _pasteTransformed(StrReplace(A_Clipboard, find, ib2.Value))
}
PasteValuesToSearch(*) {
    lines := []
    for line in StrSplit(A_Clipboard, "`n", "`r") {
        line := Trim(line)
        if (line != "")
            lines.Push(line)
    }
    if !lines.Length {
        ShowMsg("Clipboard empty")
        return
    }
    ; Splunk-ish OR list without product lock-in
    out := "("
    for i, v in lines {
        out .= '"' v '"'
        if i < lines.Length
            out .= " OR "
    }
    out .= ")"
    _pasteTransformed(out)
}
PasteUnixTimestamp(*) {
    t := Trim(A_Clipboard)
    if RegExMatch(t, "^\d{10,13}$") {
        sec := Integer(t)
        if sec > 1000000000000
            sec := sec // 1000
        local := DateAdd("19700101000000", sec, "Seconds")
        _pasteTransformed(FormatTime(local, "yyyy-MM-dd HH:mm:ss"))
        return
    }
    ShowMsg("Clipboard needs a unix epoch (10–13 digits)")
}

Join(arr, sep) {
    s := ""
    for i, v in arr {
        s .= v
        if i < arr.Length
            s .= sep
    }
    return s
}
