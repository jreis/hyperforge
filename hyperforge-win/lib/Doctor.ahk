; Doctor.ahk — quick health check (tray)

ShowDoctor(*) {
    ReleaseHyperModifiers()
    lines := []
    lines.Push("HyperForge for Windows — Doctor")
    lines.Push("")
    if A_IsAdmin
        lines.Push("Running as admin — Hyper reaches elevated windows.")
    else
        lines.Push("Not running as admin — Hyper does not fire in elevated windows (Task Manager, installers, admin terminals).")
    lines.Push("AHK: " A_AhkVersion (A_Is64bitOS ? " (64-bit OS)" : ""))
    lines.Push("Script: " A_ScriptFullPath)
    lines.Push("Config: " (FileExist(A_ScriptDir "\config.ini") ? "config.ini OK" : "missing — using defaults / example"))
    lines.Push("Caps→Hyper: " (HFConfig.GetBool("general.caps_to_hyper", true) ? "enabled" : "disabled"))
    lines.Push("Caps tap: " (HFConfig.GetBool("general.caps_tap_escape", true) ? "Escape" : "does nothing"))
    lines.Push("Wheel accel: " (HFConfig.GetBool("general.wheel_accel", true) ? "on" : "off"))
    lines.Push("Mouse Back minimizes: " (HFConfig.GetBool("general.xbutton1_minimize", false) ? "on" : "off (Hyper+B still minimizes)"))
    port := HFConfig.Get("paths.chrome_debug_port", "")
    lines.Push("Chrome debug port: " (port != "" ? port " — local debugging is ON" : "off"))
    lines.Push("Startup shortcut: " (FileExist(A_Startup "\HyperForge.lnk") ? "installed" : "not installed (tray → Install Startup shortcut)"))

    global HF_HyperPaused, HF_MuteProcesses, HF_KeepAliveOn
    lines.Push("Hyper paused: " (HF_HyperPaused ? "yes" : "no"))
    lines.Push("Keep-alive: " (IsSet(HF_KeepAliveOn) && HF_KeepAliveOn ? "on" : "off"))
    muteCount := IsSet(HF_MuteProcesses) ? HF_MuteProcesses.Length : 0
    lines.Push("Muted processes: " muteCount)
    if muteCount {
        sample := ""
        for i, p in HF_MuteProcesses {
            if i > 6
                break
            sample .= (sample = "" ? "" : ", ") p
        }
        lines.Push("  e.g. " sample)
    }

    tc := false
    for name in ["TouchCursor.exe", "touchcursor.exe"] {
        if ProcessExist(name) {
            tc := true
            break
        }
    }
    lines.Push("TouchCursor process: " (tc ? "running" : "not detected (OK if you use another Space tool)"))

    global HF_ClipHistory
    clipCount := IsSet(HF_ClipHistory) ? HF_ClipHistory.Length : 0
    lines.Push("Clipboard history: " clipCount " item(s) — Hyper+P")
    lines.Push("History file: " A_AppData "\HyperForge\clipboard-history.dat")
    lines.Push("Snippet date format: " HFConfig.Get("snippets.date_format", "yyyy-MM-dd"))

    lines.Push("")
    lines.Push("Window pad snaps to the visible frame (invisible borders included).")
    lines.Push("Hyper+Z undoes the last snap or tile. Hyper+L copies the LAN address.")
    lines.Push("Win+I (Settings) and Win+W (Widgets) are not used.")
    lines.Push("macOS-only: Shortcuts, AX recipes, Ollama command bar.")

    msg := ""
    for line in lines
        msg .= line "`n"
    MsgBox msg, "HyperForge Doctor", "Iconi"
    RestoreHyperModifiers()
}
