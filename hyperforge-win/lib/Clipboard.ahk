; Clipboard.ahk — paste transform menu + clipboard history (macOS Hyper+V parity)

global HF_ClipHistory := []  ; newest-first array of {text, pinned}

RegisterClipboardHotkeys() {
    Hotkey "^+!v", ShowPasteMenu
    ClipHistory_Load()
    OnClipboardChange(ClipHistory_OnChange)
    HotIf HyperAllowed
    Hotkey "#^!+p", (*) => ShowClipboardHistory()
    HotIf
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

; ── Clipboard history (Hyper+P) ──────────────────────────────────────────
; Persisted, pinned-first, searchable — same shape as macOS ClipboardService
; (pin survives eviction; unpinned entries capped at clipboard.max_items, default 20).

ClipHistoryFile() {
    dir := A_AppData "\HyperForge"
    if !DirExist(dir)
        DirCreate(dir)
    return dir "\clipboard-history.dat"
}

ClipHistory_Load() {
    global HF_ClipHistory
    HF_ClipHistory := []
    file := ClipHistoryFile()
    if !FileExist(file)
        return
    for line in StrSplit(FileRead(file), "`n") {
        line := Trim(line, "`r`n")
        if (line = "")
            continue
        parts := StrSplit(line, "`t", , 2)
        if (parts.Length < 2)
            continue
        text := Base64Decode(parts[2])
        if (text != "")
            HF_ClipHistory.Push({ text: text, pinned: parts[1] = "1" })
    }
}

ClipHistory_Save() {
    global HF_ClipHistory
    out := ""
    for entry in HF_ClipHistory
        out .= (entry.pinned ? "1" : "0") "`t" Base64Encode(entry.text) "`n"
    try FileDelete(ClipHistoryFile())
    if (out != "")
        FileAppend(out, ClipHistoryFile())
}

ClipHistory_OnChange(dataType) {
    if (dataType != 1)  ; 1 = text
        return
    ClipHistory_Record(A_Clipboard)
}

; Insert at front (deduped, pin preserved); trim unpinned beyond the cap; persist.
ClipHistory_Record(text) {
    global HF_ClipHistory
    trimmed := Trim(text)
    if (trimmed = "")
        return
    if (StrLen(text) > 8000)
        text := SubStr(text, 1, 8000)
    wasPinned := false
    for i, entry in HF_ClipHistory {
        if (entry.text = text) {
            wasPinned := entry.pinned
            HF_ClipHistory.RemoveAt(i)
            break
        }
    }
    HF_ClipHistory.InsertAt(1, { text: text, pinned: wasPinned })
    ClipHistory_TrimUnpinned()
    ClipHistory_Save()
}

ClipHistory_TrimUnpinned() {
    global HF_ClipHistory
    max := HFConfig.GetInt("clipboard.max_items", 20)
    kept := []
    unpinnedSeen := 0
    for entry in HF_ClipHistory {
        if entry.pinned {
            kept.Push(entry)
        } else if (++unpinnedSeen <= max) {
            kept.Push(entry)
        }
    }
    HF_ClipHistory := kept
}

; Pinned first, stable within each group (matches macOS `pinnedFirst`).
ClipHistory_PinnedFirst() {
    global HF_ClipHistory
    pinned := []
    rest := []
    for entry in HF_ClipHistory
        (entry.pinned ? pinned : rest).Push(entry)
    for entry in rest
        pinned.Push(entry)
    return pinned
}

ClipHistory_Preview(text, maxLen := 70) {
    one := StrReplace(StrReplace(text, "`r`n", " "), "`n", " ")
    if (StrLen(one) > maxLen)
        return SubStr(one, 1, maxLen - 1) "…"
    return one
}

global HF_ClipGui := ""
global HF_ClipGuiEntries := []

ShowClipboardHistory(*) {
    global HF_ClipGui, HF_ClipGuiEntries
    ; Capture whatever is on the pasteboard right now too (e.g. copied before HyperForge started).
    if (A_Clipboard != "")
        ClipHistory_Record(A_Clipboard)

    if IsObject(HF_ClipGui) {
        try HF_ClipGui.Destroy()
    }

    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge — Clipboard")
    HF_ClipGui := g
    g.SetFont("s10")
    g.AddText("w440", "Clipboard history")
    filterEdit := g.AddEdit("w340 vFilterText")
    pasteBtn := g.AddButton("x+8 w90 Default", "Paste ⏎")
    list := g.AddListBox("w440 r9 vClipList")
    pinBtn := g.AddButton("w120", "Pin / unpin")
    g.AddText("x+8 yp+4", "Esc close · dbl-click paste · type to filter")

    _clipRefresh := (*) => ClipHistory_RefreshList(list, filterEdit.Value)
    filterEdit.OnEvent("Change", _clipRefresh)
    list.OnEvent("DoubleClick", (*) => ClipHistory_PasteSelected(g, list))
    pasteBtn.OnEvent("Click", (*) => ClipHistory_PasteSelected(g, list))
    pinBtn.OnEvent("Click", (*) => (ClipHistory_ToggleSelectedPin(list), _clipRefresh()))
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())

    ClipHistory_RefreshList(list, "")
    g.Show()
    filterEdit.Focus()
}

ClipHistory_RefreshList(list, filter) {
    global HF_ClipGuiEntries
    items := ClipHistory_PinnedFirst()
    if (filter != "")
        items := ClipHistory_Filter(items, filter)
    items := ClipHistory_Cap(items, 9)
    HF_ClipGuiEntries := items

    list.Delete()
    if !items.Length {
        msg := filter != "" ? "No matches for “" filter "”" : "Nothing saved yet — copy some text"
        list.Add([msg])
        return
    }
    rows := []
    for entry in items {
        prefix := entry.pinned ? "★ " : "   "
        rows.Push(prefix ClipHistory_Preview(entry.text))
    }
    list.Add(rows)
    list.Choose(1)
}

ClipHistory_Filter(items, filter) {
    out := []
    for entry in items {
        if InStr(entry.text, filter, false)
            out.Push(entry)
    }
    return out
}

ClipHistory_Cap(items, n) {
    out := []
    for entry in items {
        if (out.Length >= n)
            break
        out.Push(entry)
    }
    return out
}

ClipHistory_PasteSelected(g, list) {
    global HF_ClipGuiEntries
    idx := list.Value
    if (idx = 0)
        idx := 1
    if !HF_ClipGuiEntries.Length
        return
    entry := HF_ClipGuiEntries[Min(idx, HF_ClipGuiEntries.Length)]
    g.Destroy()
    A_Clipboard := entry.text
    Sleep 50
    Send "^v"
}

ClipHistory_ToggleSelectedPin(list) {
    global HF_ClipHistory, HF_ClipGuiEntries
    idx := list.Value
    if (idx = 0 || !HF_ClipGuiEntries.Length)
        return
    target := HF_ClipGuiEntries[Min(idx, HF_ClipGuiEntries.Length)]
    for entry in HF_ClipHistory {
        if (entry.text = target.text) {
            entry.pinned := !entry.pinned
            break
        }
    }
    ClipHistory_Save()
}
