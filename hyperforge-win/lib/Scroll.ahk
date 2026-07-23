; Scroll.ahk — accelerated mouse wheel (optional)

global HF_ScrollDistance := 0
global HF_ScrollVMax := 1
global HF_ScrollTimeout := 500
global HF_ScrollBoost := 400
global HF_ScrollLimit := 60

InitScrollAccel() {
    if !HFConfig.GetBool("general.wheel_accel", true)
        return
    Hotkey "WheelUp", ScrollAccel
    Hotkey "WheelDown", ScrollAccel
}

ScrollAccel(*) {
    global HF_ScrollDistance, HF_ScrollVMax, HF_ScrollTimeout, HF_ScrollBoost, HF_ScrollLimit
    t := A_TimeSincePriorHotkey
    if (A_PriorHotkey = A_ThisHotkey && t < HF_ScrollTimeout) {
        HF_ScrollDistance++
        v := (t < 80 && t > 1) ? (250.0 / t) - 1 : 1
        if (HF_ScrollBoost > 1 && HF_ScrollDistance > HF_ScrollBoost) {
            if (v > HF_ScrollVMax)
                HF_ScrollVMax := v
            else
                v := HF_ScrollVMax
            v *= HF_ScrollDistance / HF_ScrollBoost
        }
        v := (v > 1) ? ((v > HF_ScrollLimit) ? HF_ScrollLimit : Floor(v)) : 1
        MouseClick A_ThisHotkey, , , v
    } else {
        HF_ScrollDistance := 0
        HF_ScrollVMax := 1
        MouseClick A_ThisHotkey
    }
}
