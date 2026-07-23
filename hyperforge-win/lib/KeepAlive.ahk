; KeepAlive.ahk — Hyper+J toggle idle nudge (Teams-safe-ish)

global HF_KeepAliveOn := false

RegisterKeepAlive() {
    ; Win+J — not full Hyper (avoids fighting game binds); still listed in README
    Hotkey "#j", ToggleKeepAlive
}

ToggleKeepAlive(*) {
    global HF_KeepAliveOn
    mins := HFConfig.GetInt("general.keepalive_minutes", 5)
    period := mins * 60 * 1000
    if !HF_KeepAliveOn {
        SetTimer(KeepAliveTick, period)
        HF_KeepAliveOn := true
        ShowMsg("Keep-alive ON")
    } else {
        SetTimer(KeepAliveTick, 0)
        HF_KeepAliveOn := false
        ShowMsg("Keep-alive OFF")
    }
}

KeepAliveTick() {
    if (A_TimeIdlePhysical > 60000)
        MouseMove 1, 0, 0, "R"
}
