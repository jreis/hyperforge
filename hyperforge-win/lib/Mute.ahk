; Mute.ahk — per-app Hyper mute + temporary pause

global HF_HyperPaused := false
global HF_MuteProcesses := []
global HF_PauseDeadline := 0

InitHyperMute() {
    global HF_MuteProcesses
    HF_MuteProcesses := []
    ; config: mute.processes=game.exe,fceux.exe,vmware.exe
    raw := HFConfig.Get("mute.processes", "")
    ; also support multi-line keys mute.proc1= etc. via section dump
    if (raw != "") {
        for part in StrSplit(raw, ",", " `t") {
            p := Trim(part)
            if (p != "")
                HF_MuteProcesses.Push(StrLower(p))
        }
    }
    ; Defaults that almost always want Hyper off
    for d in ["fceux.exe", "dosbox.exe", "vmware-vmx.exe", "VirtualBoxVM.exe"] {
        if !HasMute(d)
            HF_MuteProcesses.Push(d)
    }
    ; Optional extras from config without removing defaults
    extra := HFConfig.Get("mute.extra", "")
    if (extra != "") {
        for part in StrSplit(extra, ",", " `t") {
            p := StrLower(Trim(part))
            if (p != "" && !HasMute(p))
                HF_MuteProcesses.Push(p)
        }
    }
}

HasMute(proc) {
    global HF_MuteProcesses
    proc := StrLower(proc)
    for p in HF_MuteProcesses
        if (p = proc)
            return true
    return false
}

; Used as HotIf predicate — true means Hyper hotkeys are active.
HyperAllowed() {
    global HF_HyperPaused, HF_PauseDeadline
    if HF_HyperPaused {
        if (HF_PauseDeadline && A_TickCount > HF_PauseDeadline) {
            HF_HyperPaused := false
            HF_PauseDeadline := 0
            ShowMsg("Hyper resumed")
        } else {
            return false
        }
    }
    try {
        proc := StrLower(WinGetProcessName("A"))
        if HasMute(proc)
            return false
        ; RDP / full-screen-ish remote
        cls := WinGetClass("A")
        if (cls = "TscShellContainerClass" || cls = "OpusApp") ; optional
        {
            ; only block mstsc by process usually
        }
        if (proc = "mstsc.exe" || proc = "msrdc.exe")
            return false
    } catch {
        return true
    }
    return true
}

PauseHyper(seconds := 30) {
    global HF_HyperPaused, HF_PauseDeadline
    HF_HyperPaused := true
    HF_PauseDeadline := A_TickCount + (seconds * 1000)
    ShowMsg("Hyper paused " seconds "s")
    SetTimer(CheckHyperPause, 1000)
}

CheckHyperPause() {
    global HF_HyperPaused, HF_PauseDeadline
    if !HF_HyperPaused {
        SetTimer(CheckHyperPause, 0)
        return
    }
    if (HF_PauseDeadline && A_TickCount > HF_PauseDeadline) {
        HF_HyperPaused := false
        HF_PauseDeadline := 0
        SetTimer(CheckHyperPause, 0)
        ShowMsg("Hyper resumed")
    }
}

ToggleHyperPause(*) {
    global HF_HyperPaused, HF_PauseDeadline
    if HF_HyperPaused {
        HF_HyperPaused := false
        HF_PauseDeadline := 0
        SetTimer(CheckHyperPause, 0)
        ShowMsg("Hyper resumed")
    } else {
        PauseHyper(HFConfig.GetInt("mute.pause_seconds", 30))
    }
}

RegisterMuteHotkeys() {
    ; Win+Esc or Hyper+Esc — pause (Esc alone is too aggressive)
    Hotkey "#Esc", ToggleHyperPause
}
