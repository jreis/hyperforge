; Tray.ahk — HyperForge tray menu

InitTray() {
    try TraySetIcon(A_ScriptDir "\keybd.ico")
    A_IconTip := "HyperForge for Windows"
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Reload HyperForge", (*) => Reload())
    tray.Add("Edit config.ini", (*) => Run('notepad.exe "' A_ScriptDir '\config.ini"'))
    tray.Add("Open script folder", (*) => Run('explorer.exe "' A_ScriptDir '"'))
    tray.Add()
    tray.Add("About", (*) => MsgBox(
        "HyperForge for Windows`n"
        "AHK v2 Hyper Key companion`n"
        "Pairs with TouchCursor for Space-layer nav`n`n"
        "https://github.com/jreis/hyperforge",
        "HyperForge"
    ))
    tray.Add("Exit", (*) => ExitApp())
    ; Reload when saving this script in an editor with the script name in the title
    Hotkey "~^s", (*) => {
        if WinActive(A_ScriptName) {
            ShowMsg("Reloading…")
            Reload
        }
    }
}
