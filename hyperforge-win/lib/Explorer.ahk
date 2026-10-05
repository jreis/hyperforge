; Explorer.ahk — folder / selection helpers

GetFolder() {
    try {
        window := explorerGetWindow()
        if (window = "desktop")
            return A_Desktop
        if IsObject(window) {
            path := window.Document.Folder.Self.Path
            if (path != "")
                return path
        }
    }
    try activeClass := WinGetClass("A")
    catch
        return ""
    if !(activeClass ~= "i)\A(CabinetWClass|ExplorerWClass|Progman)\z")
        return ""
    if (activeClass = "Progman")
        return A_Desktop
    fullPath := StrReplace(WinGetText("A"), "Address: ", "")
    Loop Parse fullPath, "`r`n" {
        if InStr(A_LoopField, ":\")
            return Trim(A_LoopField)
    }
    return ""
}

explorerGetWindow(hwnd := 0) {
    hwnd := hwnd || WinExist("A")
    class := WinGetClass(hwnd)
    switch {
        case WinGetProcessName(hwnd) != "explorer.exe":
            return
        case class ~= "Progman|WorkerW":
            return "desktop"
        case class ~= "(Cabinet|Explore)WClass":
            for window in ComObject("Shell.Application").Windows {
                try if window.hwnd = hwnd
                    return window
            }
    }
}

explorerDesktopGetSel(hwnd := 0, selection := true) {
    ret := ""
    hwWindow := ""
    switch window := explorerGetWindow(hwnd) {
        case "":
            return "ERROR"
        case "desktop":
            try hwWindow := ControlGetHwnd("SysListView321", "ahk_class Progman")
            hwWindow := hwWindow || ControlGetHwnd("SysListView321", "A")
            Loop Parse ListViewGetContent((selection ? "Selected" : "") " Col1", hwWindow), "`n", "`r"
                ret .= A_Desktop "\" A_LoopField "`n"
        default:
            for item in selection ? window.document.SelectedItems : window.document.Folder.Items
                ret .= item.path "`n"
    }
    return Trim(ret, "`n")
}

RegisterExplorerHotkeys() {
    ; Ctrl+Alt+Shift+C in Explorer → file contents to clipboard
    HotIfWinActive "ahk_class CabinetWClass"
    Hotkey "^!+c", ExplorerFileToClipboard
    ; Shift+F4 / Middle-click → open selection in VS Code
    Hotkey "+F4", ExplorerOpenInEditor
    Hotkey "MButton", ExplorerOpenInEditor
    HotIfWinActive

    ; Ctrl+Alt+Shift+W → clipboard to a temp file in the editor.
    ; Win+W is left for Windows Widgets.
    Hotkey "^!+w", ClipboardToEditor
}

ExplorerFileToClipboard(*) {
    filePath := explorerDesktopGetSel()
    if (filePath = "" || filePath = "ERROR" || InStr(filePath, "`n")) {
        ShowMsg("Select one file")
        return
    }
    try {
        A_Clipboard := FileRead(filePath)
        ShowMsg("File → clipboard")
    } catch {
        ShowMsg("Read failed")
    }
}

ExplorerOpenInEditor(*) {
    if !WinActive("ahk_class CabinetWClass")
        return
    filePath := explorerDesktopGetSel()
    if (filePath = "" || filePath = "ERROR")
        return
    code := AppPath("vscode") || _defaultPath("vscode")
    Run '"' code '" "' filePath '"'
}

ClipboardToEditor(*) {
    FileEncoding "UTF-8"
    file := A_Temp "\" GenerateFileName() ".txt"
    FileAppend A_Clipboard, file
    code := AppPath("vscode") || _defaultPath("vscode")
    Run '"' code '" "' file '"'
}
