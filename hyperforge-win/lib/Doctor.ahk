; Doctor.ahk — quick health check (tray)

ShowDoctor(*) {
    lines := []
    lines.Push("HyperForge for Windows — Doctor")
    lines.Push("")
    lines.Push("AHK: " A_AhkVersion (A_Is64bitOS ? " (64-bit OS)" : ""))
    lines.Push("Script: " A_ScriptFullPath)
    lines.Push("Config: " (FileExist(A_ScriptDir "\config.ini") ? "config.ini OK" : "missing — using defaults / example"))
    lines.Push("Caps→Hyper: " (HFConfig.GetBool("general.caps_to_hyper", true) ? "enabled" : "disabled"))
    lines.Push("Wheel accel: " (HFConfig.GetBool("general.wheel_accel", true) ? "on" : "off"))
    lines.Push("Toasts: " (HFConfig.GetBool("general.toasts", true) ? "on" : "off"))

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

    ; TouchCursor detection (common process names)
    tc := false
    for name in ["TouchCursor.exe", "touchcursor.exe"] {
        if ProcessExist(name) {
            tc := true
            break
        }
    }
    lines.Push("TouchCursor process: " (tc ? "running" : "not detected (OK if you use another Space tool)"))

    lines.Push("")
    lines.Push("Tips: Hyper+[ ] next/prev monitor · Hyper+Z undo snap")
    lines.Push("Win+Esc pauses Hyper briefly · edit mute.processes in config.ini")

    msg := ""
    for line in lines
        msg .= line "`n"
    MsgBox msg, "HyperForge Doctor", "Iconi"
}
