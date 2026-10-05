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
    tray.Add("Install Startup shortcut", (*) => InstallStartupShortcut())
    tray.Add("Export config…", (*) => ExportHyperForgeConfig())
    tray.Add("Import config…", (*) => ImportHyperForgeConfig())
    tray.Add("Cheat sheet", (*) => ShowCheatSheet())
    tray.Add("Command bar", (*) => ShowCommandBar())
    tray.Add("Edit config.ini", EditConfigIni)
    tray.Add("Open script folder", (*) => Run('explorer.exe "' A_ScriptDir '"'))
    tray.Add()
    tray.Add("About", (*) => MsgBox(
        "HyperForge for Windows`n"
        "AHK v2 Hyper Key companion (parity target: macOS 0.4.x)`n"
        "Caps → Hyper · tap Caps for Escape · numpad window pad`n"
        "Pairs with TouchCursor for Space-layer nav`n`n"
        "https://github.com/jreis/hyperforge",
        "HyperForge"
    ))
    tray.Add("Exit", (*) => ExitApp())
    Hotkey "~^s", ReloadIfEditingThisScript
}

EditConfigIni(*) {
    cfg := A_ScriptDir "\config.ini"
    if !FileExist(cfg)
        cfg := A_ScriptDir "\config.example.ini"
    Run 'notepad.exe "' cfg '"'
}

ReloadIfEditingThisScript(*) {
    if WinActive(A_ScriptName) {
        ShowMsg("Reloading…")
        Reload
    }
}

InstallStartupShortcut(*) {
    try {
        lnk := A_Startup "\HyperForge.lnk"
        shell := ComObject("WScript.Shell")
        link := shell.CreateShortcut(lnk)
        link.TargetPath := A_AhkPath
        link.Arguments := '"' A_ScriptFullPath '"'
        link.WorkingDirectory := A_ScriptDir
        link.WindowStyle := 7
        link.Description := "HyperForge for Windows"
        link.Save()
        ShowMsg("Startup shortcut installed")
    } catch {
        ShowMsg("Could not create Startup shortcut")
    }
}
