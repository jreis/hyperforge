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

    global HF_ClipHistory
    clipCount := IsSet(HF_ClipHistory) ? HF_ClipHistory.Length : 0
    lines.Push("Clipboard history: " clipCount " item(s) — Hyper+P")
    lines.Push("Snippet date format: " HFConfig.Get("snippets.date_format", "yyyy-MM-dd"))

    lines.Push("")
    lines.Push("Parity with macOS HyperForge (window pad + snippets + clipboard):")
    lines.Push("  Hyper+arrows halves · Enter max · 6 tile-all · Z undo")
    lines.Push("  Hyper+-/=/\ thirds · i/o two-thirds · u almost-max")
    lines.Push("  Numpad full spatial pad · A always-on-top · B minimize · K keep-alive")
    lines.Push("  Hyper+P clipboard history (pin/search) · {{token}} snippets")
    lines.Push("Tips: Hyper+[ ] next/prev monitor · Win+Esc pauses Hyper")
    lines.Push("edit mute.processes in config.ini for games / RDP")
    lines.Push("")
    lines.Push("  Hyper+Y pin region · Q OCR · / cheat sheet · ; command bar · F warp")
    lines.Push("macOS-only: Shortcuts, AX recipes, Ollama command bar.")

    msg := ""
    for line in lines
        msg .= line "`n"
    MsgBox msg, "HyperForge Doctor", "Iconi"
}
