; Tray.ahk — HyperForge tray menu

InitTray() {
    try TraySetIcon(A_ScriptDir "\keybd.ico")
    A_IconTip := "HyperForge for Windows"
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Doctor — health check", ShowDoctor)
    tray.Add("Pause Hyper (toggle)", ToggleHyperPause)
    tray.Add()
    tray.Add("Reload HyperForge", (*) => Reload())
    tray.Add("Edit config.ini", (*) => {
        cfg := A_ScriptDir "\config.ini"
        if !FileExist(cfg)
            cfg := A_ScriptDir "\config.example.ini"
        Run 'notepad.exe "' cfg '"'
    })
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
    Hotkey "~^s", (*) => {
        if WinActive(A_ScriptName) {
            ShowMsg("Reloading…")
            Reload
        }
    }
}
