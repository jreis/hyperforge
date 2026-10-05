; Catalog.ahk — command bar + cheat sheet (macOS Hyper+Space / Hyper+/ parity)

global HF_CmdGui := 0
global HF_CmdShown := []

RegisterCatalogHotkeys() {
    BindHyper("/", (*) => ShowCheatSheet(), "ui")
    BindHyper(";", (*) => ShowCommandBar(), "ui")
    BindHyper("f", (*) => WarpMouseToActive())
}

HF_Catalog() {
    return [
        ["Snap left", "half window", (*) => SnapActive(0, 0, 0.5, 1)],
        ["Snap right", "half window", (*) => SnapActive(0.5, 0, 0.5, 1)],
        ["Snap top", "half window", (*) => SnapActive(0, 0, 1, 0.5)],
        ["Snap bottom", "half window", (*) => SnapActive(0, 0.5, 1, 0.5)],
        ["Maximize", "full", (*) => SnapActive(0, 0, 1, 1)],
        ["Quarter top-left", "corner tl", (*) => SnapActive(0, 0, 0.5, 0.5)],
        ["Quarter top-right", "corner tr", (*) => SnapActive(0.5, 0, 0.5, 0.5)],
        ["Quarter bottom-left", "corner bl", (*) => SnapActive(0, 0.5, 0.5, 0.5)],
        ["Quarter bottom-right", "corner br", (*) => SnapActive(0.5, 0.5, 0.5, 0.5)],
        ["Left third", "column", (*) => SnapThird(0)],
        ["Center third", "column", (*) => SnapThird(1)],
        ["Right third", "column", (*) => SnapThird(2)],
        ["Left two-thirds", "wide", (*) => SnapTwoThirds(true)],
        ["Right two-thirds", "wide", (*) => SnapTwoThirds(false)],
        ["Almost maximize", "90 percent", (*) => AlmostMaximize()],
        ["Center window", "keep size", (*) => CenterActive()],
        ["Tile all windows", "grid", (*) => TileAllVisible()],
        ["Undo last layout", "snap tile", (*) => UndoSnap()],
        ["Next monitor", "screen", (*) => MoveActiveToMonitor(1)],
        ["Previous monitor", "screen", (*) => MoveActiveToMonitor(-1)],
        ["Always on top", "pin window", (*) => ToggleAlwaysOnTop()],
        ["Minimize", "hide", (*) => MinimizeActive()],
        ["Close window", "quit", (*) => CloseActive()],
        ["Warp mouse to window", "center pointer", (*) => WarpMouseToActive()],
        ["Clipboard history", "paste pin", (*) => ShowClipboardHistory()],
        ["Paste transforms", "comma base64", (*) => ShowPasteMenu()],
        ["Pin screen region", "snip screenshot", (*) => BeginRegionPin()],
        ["OCR region", "text recognize", (*) => BeginRegionOCR()],
        ["Cheat sheet", "help keys", (*) => ShowCheatSheet()],
        ["Keep-alive toggle", "idle", (*) => ToggleKeepAlive()],
        ["Scripts", "run ahk", (*) => ShowScriptsMenu()],
        ["Workspaces", "layout save", (*) => ShowWorkspacesMenu()],
        ["Volume up", "sound", (*) => VolumeUp()],
        ["Volume down", "sound", (*) => VolumeDown()],
        ["Mute / unmute", "sound", (*) => ToggleMute()],
        ["Next Space", "desktop", (*) => NextSpace()],
        ["Previous Space", "desktop", (*) => PreviousSpace()],
        ["Pause Hyper", "suspend", (*) => ToggleHyperPause()],
        ["Copy hostname", "computer name", (*) => CopyHostname()],
        ["Copy LAN IP", "address", (*) => CopyLanIP()],
        ["ARIN whois", "clipboard ip", (*) => ArinWhois()],
        ["Google clipboard", "search", (*) => ChromeLaunch("https://www.google.com/search?q=" UrlEncode(A_Clipboard))],
        ["Notepad", "app", (*) => RunOrActivateOrMinimizeProgram(AppPath("notepad") || "notepad.exe")],
        ["VS Code", "app editor", (*) => RunOrActivateOrMinimizeProgram(AppPath("vscode") || _defaultPath("vscode"))],
        ["Chrome", "app browser", (*) => RunOrActivateOrMinimizeProgram(ChromeCommand())],
        ["Teams", "app", (*) => LaunchTeams()],
        ["Explorer", "app files", (*) => Run("explorer.exe")],
        ["Outlook", "app mail", (*) => RunOrActivateOrMinimizeProgram(AppPath("outlook") || _defaultPath("outlook"))],
        ["Terminal in folder", "wt shell", (*) => LaunchTerminalHere()],
        ["Edit HyperForge script", "config code", (*) => EditHyperForge()],
        ["Export config", "backup json", (*) => ExportHyperForgeConfig()],
        ["Import config", "backup json", (*) => ImportHyperForgeConfig()],
        ["Install Startup shortcut", "login", (*) => InstallStartupShortcut()],
        ["Doctor", "health check", (*) => ShowDoctor()]
    ]
}

; Substring matches outrank a scattered subsequence. Empty query keeps catalog order.
CommandScore(query, label) {
    q := StrLower(Trim(query))
    s := StrLower(label)
    if (q = "")
        return 1
    at := InStr(s, q)
    if at
        return 2000 - at
    si := 1
    score := 0
    prev := 0
    loop parse q {
        found := InStr(s, A_LoopField, , si)
        if !found
            return 0
        score += (prev && found = prev + 1) ? 4 : 1
        prev := found
        si := found + 1
    }
    return score
}

RankCommands(items, query) {
    ranked := []
    for row in items {
        score := CommandScore(query, row[1] " " row[2])
        if (score < 1)
            continue
        ranked.Push({ row: row, score: score })
    }
    i := 2
    while (i <= ranked.Length) {
        j := i
        while (j > 1 && ranked[j].score > ranked[j - 1].score) {
            tmp := ranked[j - 1]
            ranked[j - 1] := ranked[j]
            ranked[j] := tmp
            j--
        }
        i++
    }
    return ranked
}

CheatSheetText() {
    s := "HyperForge for Windows    Caps = Hyper`n"
    s .= "Tap Caps alone for Escape. Hold Caps, then the key.`n`n"
    s .= "Window pad`n"
    s .= "  arrows        halves              Enter    maximize`n"
    s .= "  top row 7 8 9 0   TL TR BL BR     6        tile all`n"
    s .= "  -  =  \       left / right / center third`n"
    s .= "  I / O         left / right two-thirds      U   almost-max`n"
    s .= "  .             center (keep size)           Z   undo`n"
    s .= "  [ / ]         previous / next monitor`n"
    s .= "  A             always on top                B   minimize`n`n"
    s .= "Numpad: 7 TL  8 top  9 TR    4 left  5 max  6 right`n"
    s .= "        1 BL  2 bot  3 BR    0 center`n`n"
    s .= "Tools`n"
    s .= "  P  clipboard history    Y  pin region     Q  OCR`n"
    s .= "  / cheat sheet    | command bar    | warp mouse`n"
    s .= "  K  keep-alive           G  Google clipboard`n"
    s .= "  J  scripts              L  workspaces`n"
    s .= "  M  hostname             W  ARIN whois      LAN IP is in the command bar`n`n"
    s .= "Apps`n"
    s .= "  N notepad  V VS Code  C Chrome  T Teams  E Explorer  4 Outlook`n"
    s .= "  X terminal in folder    D close window    H edit script`n`n"
    s .= "Ctrl+Alt+Shift+V paste transforms    Win+Esc pause    Win+J keep-alive`n"
    s .= "Win+Ctrl+I reverse DNS               XButton2 quick menu"
    return s
}

ShowCheatSheet(*) {
    static g := 0
    if IsObject(g) {
        try EndHyperUi(g)
        g := 0
    }
    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge")
    BeginHyperUi(g)
    g.SetFont("s10", "Consolas")
    g.AddEdit("ReadOnly w640 r26", CheatSheetText())
    g.OnEvent("Escape", (*) => EndHyperUi(g))
    g.AddButton("Default w80", "Close").OnEvent("Click", (*) => EndHyperUi(g))
    g.Show()
}

ShowCommandBar(*) {
    global HF_CmdGui, HF_CmdShown
    if IsObject(HF_CmdGui) {
        try EndHyperUi(HF_CmdGui)
        HF_CmdGui := 0
    }
    items := HF_Catalog()
    g := Gui("+AlwaysOnTop +ToolWindow", "HyperForge command bar")
    HF_CmdGui := g
    BeginHyperUi(g)
    g.SetFont("s10", "Segoe UI")
    g.AddText("w460", "Type a command")
    filter := g.AddEdit("w460")
    lv := g.AddListBox("w460 r16")
    refill(*) {
        global HF_CmdShown
        ranked := RankCommands(items, filter.Value)
        HF_CmdShown := []
        labels := []
        for hit in ranked {
            HF_CmdShown.Push(hit.row)
            labels.Push(hit.row[1])
        }
        lv.Delete()
        if labels.Length {
            lv.Add(labels)
            lv.Choose(1)
        }
        GuiNavSetCount(labels.Length)
    }
    runSelected(*) {
        global HF_CmdGui, HF_CmdShown
        idx := lv.Value
        if (idx < 1 || idx > HF_CmdShown.Length)
            return
        fn := HF_CmdShown[idx][3]
        EndHyperUi(g)
        HF_CmdGui := 0
        fn.Call()
    }
    filter.OnEvent("Change", refill)
    lv.OnEvent("DoubleClick", runSelected)
    g.OnEvent("Escape", (*) => EndHyperUi(g))
    g.AddButton("Default w80", "Run").OnEvent("Click", runSelected)
    GuiNavAttach(g, lv)
    refill()
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
        m := WindowFrameMargins(hwnd)
        cx := x + m.l + (w - m.l - m.r) // 2
        cy := y + m.t + (h - m.t - m.b) // 2
        MouseMove cx, cy
        ShowMsg("Warped")
    }
}
