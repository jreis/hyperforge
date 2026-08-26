; Workspaces.ahk — Hyper + L → save/restore named window layouts.
; Extends the tile-all/undo mechanism (Window.ahk) into named, persisted multi-window
; layouts — Windows parity for macOS HyperForge's Hyper+⇧L Workspaces chord. Windows'
; Hyper always includes Shift (see CapsHyper.ahk), so plain L is the equivalent chord.

RegisterWorkspacesHotkeys() {
    HotIf HyperAllowed
    Hotkey "#^!+l", (*) => ShowWorkspacesMenu()
    HotIf
}

WorkspacesDir() {
    dir := A_AppData "\HyperForge\workspaces"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

ShowWorkspacesMenu(*) {
    dir := WorkspacesDir()
    m := Menu()
    found := false
    Loop Files dir "\*.txt" {
        found := true
        name := RegExReplace(A_LoopFileName, "\.txt$", "")
        m.Add(name, RestoreWorkspace.Bind(name))
    }
    if !found
        m.Add("No saved layouts — save one below", (*) => Run('explorer.exe "' dir '"'))
    m.Add()
    m.Add("Save current layout…", (*) => PromptSaveWorkspace())
    m.Show()
}

PromptSaveWorkspace(*) {
    ib := InputBox("Name this layout", "Save Workspace")
    if ib.Result != "OK"
        return
    name := Trim(ib.Value)
    if (name = "")
        return
    SaveWorkspace(name)
    ShowMsg('Saved "' name '"')
}

; Same "real app window" filter as TileAllVisible (Window.ahk), minus the
; single-monitor restriction — a layout spans every monitor.
CaptureWorkspaceWindows() {
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
            exe := WinGetProcessName("ahk_id " hwnd)
            if (exe = "")
                continue
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            wins.Push({ exe: exe, title: title, x: x, y: y, w: w, h: h })
        }
    }
    return wins
}

SaveWorkspace(name) {
    wins := CaptureWorkspaceWindows()
    path := WorkspacesDir() "\" name ".txt"
    out := ""
    for win in wins {
        safeTitle := StrReplace(StrReplace(win.title, "`t", " "), "`n", " ")
        out .= win.exe "`t" safeTitle "`t" win.x "`t" win.y "`t" win.w "`t" win.h "`n"
    }
    try FileDelete(path)
    if (out != "")
        FileAppend(out, path, "UTF-8")
}

RestoreWorkspace(name, *) {
    path := WorkspacesDir() "\" name ".txt"
    if !FileExist(path) {
        ShowMsg('No layout named "' name '"')
        return
    }
    used := Map()
    restored := 0
    Loop Read path {
        line := Trim(A_LoopReadLine, "`r`n")
        if (line = "")
            continue
        parts := StrSplit(line, "`t")
        if (parts.Length < 6)
            continue
        exe := parts[1], title := parts[2]
        x := Integer(parts[3]), y := Integer(parts[4])
        w := Integer(parts[5]), h := Integer(parts[6])
        hwnd := _findWorkspaceWindow(exe, title, used)
        if !hwnd
            continue
        used[hwnd] := true
        try WinRestore("ahk_id " hwnd)
        WinMove x, y, w, h, "ahk_id " hwnd
        restored++
    }
    ShowMsg("Restored " restored " window(s) — " name)
}

; Prefer an exact title match (multi-window apps restore correctly), else the first
; not-yet-used window of that exe.
_findWorkspaceWindow(exe, title, used) {
    candidates := []
    for hwnd in WinGetList() {
        try {
            if !WinExist("ahk_id " hwnd)
                continue
            if used.Has(hwnd)
                continue
            if (WinGetProcessName("ahk_id " hwnd) != exe)
                continue
            candidates.Push(hwnd)
        }
    }
    if (title != "") {
        for hwnd in candidates {
            try {
                if (WinGetTitle("ahk_id " hwnd) = title)
                    return hwnd
            }
        }
    }
    return candidates.Length ? candidates[1] : 0
}
