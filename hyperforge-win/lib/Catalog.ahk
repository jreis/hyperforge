; Catalog.ahk — command bar + cheat sheet (macOS Hyper+Space / Hyper+/ parity)

RegisterCatalogHotkeys() {
    HotIf HyperAllowed
    Hotkey "#^!+/", (*) => ShowCheatSheet()
    Hotkey "#^!+;", (*) => ShowCommandBar()
    Hotkey "#^!+f", (*) => WarpMouseToActive()
    HotIf
}

HF_Catalog() {
    ; label, callback
    return [
        ["Snap left", (*) => SnapActive(0, 0, 0.5, 1)],
        ["Snap right", (*) => SnapActive(0.5, 0, 0.5, 1)],
        ["Snap top", (*) => SnapActive(0, 0, 1, 0.5)],
        ["Snap bottom", (*) => SnapActive(0, 0.5, 1, 0.5)],
        ["Maximize", (*) => SnapActive(0, 0, 1, 1)],
        ["Center (keep size)", (*) => CenterActive()],
        ["Quarter TL / TR / BL / BR", (*) => SnapActive(0, 0, 0.5, 0.5)],
        ["Tile all", (*) => TileAllVisible()],
        ["Undo snap", (*) => UndoSnap()],
        ["Next monitor", (*) => MoveActiveToMonitor(1)],
        ["Previous monitor", (*) => MoveActiveToMonitor(-1)],
        ["Always on top", (*) => ToggleAlwaysOnTop()],
        ["Clipboard history", (*) => ShowClipboardHistory()],
        ["Paste transforms", (*) => ShowPasteMenu()],
        ["Pin screen region", (*) => BeginRegionPin()],
        ["OCR region", (*) => BeginRegionOCR()],
        ["Keep-alive toggle", (*) => ToggleKeepAlive()],
        ["Warp mouse to window", (*) => WarpMouseToActive()],
        ["Export config", (*) => ExportHyperForgeConfig()],
        ["Import config", (*) => ImportHyperForgeConfig()],
        ["Doctor", (*) => ShowDoctor()]
    ]
}

CheatSheetText() {
    return (
        "HyperForge for Windows  (Caps = Hyper)`n"
        "`n"
        "Window pad`n"
        "  ←/→/↑/↓     halves          Enter     maximize`n"
        "  7 8 9 0     quarters        6         tile all`n"
        "  - = \       thirds          I / O     two-thirds`n"
        "  U           almost-max      .         center`n"
        "  Z           undo            [ / ]     prev / next monitor`n"
        "  A           always on top   B         minimize`n"
        "`n"
        "Tools`n"
        "  P           clipboard history`n"
        "  Y           pin screen region     Q     OCR region`n"
        "  /           this cheat sheet      ;     command bar`n"
        "  K           keep-alive            F     warp mouse`n"
        "  G           Google clipboard`n"
        "`n"
        "Also: Ctrl+Alt+Shift+V paste transforms · Win+Esc pause Hyper`n"
        "Numpad: 7 TL  8 Top  9 TR  /  4 Left  5 Max  6 Right  /  1 BL  2 Bot  3 BR  /  0 Center"
    )
}

ShowCheatSheet(*) {
    static g := 0
    if IsObject(g) {
        try g.Destroy()
        g := 0
    }
    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge")
    g.SetFont("s10", "Consolas")
    g.AddEdit("ReadOnly w560 r22", CheatSheetText())
    g.OnEvent("Escape", (*) => (g.Destroy(), g := 0))
    g.AddButton("Default w80", "Close").OnEvent("Click", (*) => (g.Destroy(), g := 0))
    g.Show()
}

ShowCommandBar(*) {
    items := HF_Catalog()
    labels := []
    for row in items
        labels.Push(row[1])
    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge command bar")
    g.SetFont("s10")
    filter := g.AddEdit("w360")
    lv := g.AddListBox("w360 r12")
    lv.Add(labels)
    applyFilter(*) {
        q := StrLower(filter.Value)
        lv.Delete()
        shown := []
        for row in items {
            if (q = "" || InStr(StrLower(row[1]), q))
                shown.Push(row[1])
        }
        if shown.Length
            lv.Add(shown)
    }
    runSelected(*) {
        name := lv.Text
        if (name = "")
            return
        for row in items {
            if (row[1] = name) {
                g.Destroy()
                row[2].Call()
                return
            }
        }
    }
    filter.OnEvent("Change", applyFilter)
    lv.OnEvent("DoubleClick", runSelected)
    g.OnEvent("Escape", (*) => g.Destroy())
    g.AddButton("Default w80", "Run").OnEvent("Click", runSelected)
    g.Show()
    filter.Focus()
}

WarpMouseToActive(*) {
    hwnd := WinExist("A")
    if !hwnd {
        ShowMsg("No window")
        return
    }
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        MouseMove x + w // 2, y + h // 2
        ShowMsg("Warped")
    }
}
