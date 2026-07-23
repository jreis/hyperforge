; QuickMenu.ahk — XButton2 power menu (window list + optional favorites/quickref)

RegisterQuickMenu() {
    Hotkey "*XButton2", ShowQuickMenu
}

ShowQuickMenu(*) {
    DetectHiddenWindows false
    m := Menu()
    for win in IndexWindows() {
        title := win.title
        if (title = "")
            title := win.name
        m.Add(title, ActivateWindow.Bind(win.id))
    }
    m.Add()

    qdir := HFConfig.Path("quickref_dir", "")
    if (qdir != "" && DirExist(qdir)) {
        Loop Files qdir "\*.txt"
            m.Add(A_LoopFileName, HandleQuickRef.Bind(A_LoopFileFullPath))
        m.Add()
    }

    fav := HFConfig.Path("favorites_ini", "")
    if (fav != "" && FileExist(fav)) {
        fm := Menu()
        try {
            section := IniRead(fav, "Favorites")
            Loop Parse section, "`n", "`r" {
                if (A_LoopField = "" || !InStr(A_LoopField, "="))
                    continue
                parts := StrSplit(A_LoopField, "=", , 2)
                fm.Add(parts[1], RunFavorite.Bind(parts[2]))
            }
        }
        fm.Add("Edit favorites…", (*) => Run('notepad.exe "' fav '"'))
        m.Add("Favorites", fm)
        m.Add()
    }

    m.Add("Paste transforms…", (*) => ShowPasteMenu())
    m.Add("Copy hostname", (*) => (A_Clipboard := A_ComputerName, ShowMsg(A_ComputerName)))
    m.Add("Copy IP", (*) => {
        a := SysGetIPAddresses()
        if a.Length {
            A_Clipboard := a[1]
            ShowMsg(a[1])
        }
    })
    m.Show()
    DetectHiddenWindows true
}

IndexWindows() {
    windows := []
    for this_id in AltTabWindows() {
        try {
            windows.Push({
                name: WinGetProcessName(this_id),
                path: WinGetProcessPath(this_id),
                title: WinGetTitle(this_id),
                id: this_id
            })
        }
    }
    return windows
}

AltTabWindows() {
    static WS_EX_APPWINDOW := 0x40000
    static WS_EX_TOOLWINDOW := 0x80
    DllCall("GetCursorPos", "int64*", &point := 0)
    hMonitor := DllCall("MonitorFromPoint", "int64", point, "uint", 0x2, "ptr")
    AltTabList := []
    DetectHiddenWindows false
    for hwnd in WinGetList() {
        if hMonitor != DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 0x2, "ptr")
            continue
        owner := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
        owner := owner || hwnd
        if (DllCall("GetLastActivePopup", "ptr", owner) != hwnd)
            continue
        es := WinGetExStyle(hwnd)
        if (!(es & WS_EX_TOOLWINDOW) || (es & WS_EX_APPWINDOW))
            AltTabList.Push(hwnd)
    }
    return AltTabList
}

ActivateWindow(hwnd, *) {
    try {
        WinActivate "ahk_id " hwnd
        WinWaitActive "ahk_id " hwnd, , 1
        MoveMouseWinActive()
    }
}

MoveMouseWinActive() {
    try {
        WinGetPos(&x, &y, &w, &h, "A")
        MouseMove x + w // 2, y + h // 2, 0
    }
}

HandleQuickRef(path, *) {
    try SendText FileRead(path)
}

RunFavorite(target, *) {
    try Run target
}
