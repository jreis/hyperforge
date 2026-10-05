; Clipboard.ahk — paste transform menu + clipboard history (macOS Hyper+V parity)

global HF_ClipHistory := []  ; newest-first array of {text, pinned}
global HF_ClipFile := ""
global HF_ClipGui := ""
global HF_ClipGuiEntries := []
global HF_ClipFilter := ""

RegisterClipboardHotkeys() {
    Hotkey "^+!v", ShowPasteMenu
    ClipHistory_Load()
    OnClipboardChange(ClipHistory_OnChange)
    BindHyper("p", (*) => ShowClipboardHistory(), "ui")
}

ShowPasteMenu(*) {
    ReleaseHyperModifiers()
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
    RestoreHyperModifiers()
}

SendPlain(keys) {
    ReleaseHyperModifiers()
    Sleep 30
    Send keys
    RestoreHyperModifiers()
}

_pasteTransformed(newText) {
    A_Clipboard := newText
    SendPlain("^v")
}

PasteLinefeedsToCommas(*) {
    _pasteTransformed(StrReplace(NormalizeNewlines(A_Clipboard), "`n", ","))
}
PasteLinefeedsToQuotedCommas(*) {
    parts := []
    for line in StrSplit(NormalizeNewlines(A_Clipboard), "`n") {
        if (line != "")
            parts.Push('"' StrReplace(line, '"', '\"') '"')
    }
    _pasteTransformed(Join(parts, ","))
}
PasteLinefeedsToSemicolons(*) {
    _pasteTransformed(StrReplace(NormalizeNewlines(A_Clipboard), "`n", ";"))
}
PasteLinefeedsToSpaces(*) {
    _pasteTransformed(StrReplace(NormalizeNewlines(A_Clipboard), "`n", " "))
}
PasteTabsToCommas(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`t", ","))
}
PasteTabsToLinefeeds(*) {
    _pasteTransformed(StrReplace(A_Clipboard, "`t", "`r`n"))
}
PastePlainText(*) {
    _pasteTransformed(A_Clipboard)
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
    ChromeLaunch("https://www.google.com/search?q=" UrlEncode(A_Clipboard))
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
    for line in StrSplit(NormalizeNewlines(A_Clipboard), "`n") {
        line := Trim(line)
        if (line != "")
            lines.Push(line)
    }
    if !lines.Length {
        ShowMsg("Clipboard empty")
        return
    }
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
        stamp := DateAdd("19700101000000", sec, "Seconds")
        _pasteTransformed(FormatTime(stamp, "yyyy-MM-dd HH:mm:ss"))
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
; Persisted, pinned-first, searchable. Unpinned entries cap at clipboard.max_items.
; The on-disk line is "pin<TAB>base64". Older builds wrapped base64 every 64
; characters; the parser joins those continuation lines.

ClipHistoryFile() {
    global HF_ClipFile
    if (HF_ClipFile != "")
        return HF_ClipFile
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
    HF_ClipHistory := ClipHistory_Parse(FileRead(file, "UTF-8"))
}

ClipHistory_Parse(content) {
    if (content != "" && SubStr(content, 1, 1) = Chr(0xFEFF))
        content := SubStr(content, 2)
    items := []
    buf := ""
    for line in StrSplit(content, "`n", "`r") {
        if (line = "")
            continue
        if InStr(line, "`t") {
            parsed := ClipHistory_ParseLine(buf)
            if IsObject(parsed)
                items.Push(parsed)
            buf := line
        } else {
            buf .= line
        }
    }
    parsed := ClipHistory_ParseLine(buf)
    if IsObject(parsed)
        items.Push(parsed)
    return items
}

ClipHistory_ParseLine(line) {
    if (line = "" || !InStr(line, "`t"))
        return ""
    parts := StrSplit(line, "`t", , 2)
    if (parts.Length < 2)
        return ""
    text := Base64Decode(parts[2])
    if (text = "")
        return ""
    return { text: text, pinned: parts[1] = "1" }
}

ClipHistory_Save() {
    global HF_ClipHistory
    out := ""
    for entry in HF_ClipHistory
        out .= (entry.pinned ? "1" : "0") "`t" Base64Encode(entry.text) "`n"
    path := ClipHistoryFile()
    SplitPath path, , &dir
    if (dir != "" && !DirExist(dir))
        DirCreate(dir)
    tmp := path ".tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    if !f
        return
    f.Write(out)
    f.Close()
    FileMove(tmp, path, 1)
}

ClipHistory_OnChange(dataType) {
    if (dataType != 1)
        return
    ClipHistory_Record(A_Clipboard)
}

ClipHistory_Record(text) {
    global HF_ClipHistory
    if (Trim(text) = "")
        return
    if (StrLen(text) > 8000)
        text := SubStr(text, 1, 8000)
    if (HF_ClipHistory.Length && HF_ClipHistory[1].text = text)
        return
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
    if (max < 1)
        max := 1
    kept := []
    unpinnedSeen := 0
    for entry in HF_ClipHistory {
        if entry.pinned
            kept.Push(entry)
        else if (++unpinnedSeen <= max)
            kept.Push(entry)
    }
    HF_ClipHistory := kept
}

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

ClipHistory_Preview(text, maxLen := 80) {
    one := StrReplace(StrReplace(text, "`r`n", " "), "`n", " ")
    if (StrLen(one) > maxLen)
        return SubStr(one, 1, maxLen - 1) "…"
    return one
}

ShowClipboardHistory(*) {
    global HF_ClipGui, HF_ClipFilter
    if (A_Clipboard != "")
        ClipHistory_Record(A_Clipboard)

    if IsObject(HF_ClipGui) {
        try EndHyperUi(HF_ClipGui)
        HF_ClipGui := ""
    }

    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge — Clipboard")
    HF_ClipGui := g
    BeginHyperUi(g)
    g.SetFont("s10", "Segoe UI")
    g.AddText("w520", "Clipboard history")
    filterEdit := g.AddEdit("w400 vFilterText")
    g.AddButton("x+8 w110 Default", "Paste").OnEvent("Click", (*) => ClipHistory_PasteSelected(g))
    list := g.AddListBox("xm w520 r16 vClipList")
    g.AddButton("w110", "Pin / unpin").OnEvent("Click", (*) => ClipHistory_ToggleSelectedPin())
    g.AddButton("x+8 w90", "Delete").OnEvent("Click", (*) => ClipHistory_DeleteSelected())
    g.AddText("x+12 yp+4", "Enter paste · ↑↓ move · Ctrl+Del delete · Esc close")

    HF_ClipFilter := filterEdit
    filterEdit.OnEvent("Change", (*) => ClipHistory_RefreshList())
    list.OnEvent("DoubleClick", (*) => ClipHistory_PasteSelected(g))
    g.OnEvent("Escape", (*) => EndHyperUi(g))
    GuiNavAttach(g, list, (*) => ClipHistory_DeleteSelected())
    ClipHistory_RefreshList()
    g.Show()
    filterEdit.Focus()
}

ClipHistory_RefreshList() {
    global HF_ClipGuiEntries, HF_ClipFilter, HF_NavList
    filter := ""
    try filter := HF_ClipFilter.Value
    items := ClipHistory_PinnedFirst()
    if (filter != "")
        items := ClipHistory_Filter(items, filter)
    HF_ClipGuiEntries := items
    list := HF_NavList
    if !IsObject(list)
        return
    list.Delete()
    if !items.Length {
        list.Add([filter != "" ? "No matches" : "Nothing saved yet — copy some text"])
        GuiNavSetCount(0)
        return
    }
    rows := []
    for entry in items {
        prefix := entry.pinned ? "★ " : "   "
        rows.Push(prefix ClipHistory_Preview(entry.text))
    }
    list.Add(rows)
    list.Choose(1)
    GuiNavSetCount(items.Length)
}

ClipHistory_Filter(items, filter) {
    out := []
    for entry in items {
        if InStr(entry.text, filter, false)
            out.Push(entry)
    }
    return out
}

ClipHistory_PasteSelected(g, *) {
    global HF_ClipGui, HF_ClipGuiEntries, HF_NavList
    idx := IsObject(HF_NavList) ? HF_NavList.Value : 0
    if (idx < 1)
        idx := 1
    if !HF_ClipGuiEntries.Length || idx > HF_ClipGuiEntries.Length
        return
    text := HF_ClipGuiEntries[idx].text
    EndHyperUi(g)
    HF_ClipGui := ""
    A_Clipboard := text
    SendPlain("^v")
}

ClipHistory_SelectedEntry() {
    global HF_ClipGuiEntries, HF_NavList
    if !IsObject(HF_NavList) || !HF_ClipGuiEntries.Length
        return ""
    idx := HF_NavList.Value
    if (idx < 1 || idx > HF_ClipGuiEntries.Length)
        return ""
    return HF_ClipGuiEntries[idx]
}

ClipHistory_ToggleSelectedPin() {
    global HF_ClipHistory
    target := ClipHistory_SelectedEntry()
    if !IsObject(target)
        return
    for entry in HF_ClipHistory {
        if (entry.text = target.text) {
            entry.pinned := !entry.pinned
            break
        }
    }
    ClipHistory_Save()
    ClipHistory_RefreshList()
}

ClipHistory_DeleteSelected() {
    global HF_ClipHistory
    target := ClipHistory_SelectedEntry()
    if !IsObject(target)
        return
    kept := []
    for entry in HF_ClipHistory {
        if (entry.text != target.text)
            kept.Push(entry)
    }
    HF_ClipHistory := kept
    ClipHistory_Save()
    ClipHistory_RefreshList()
}
