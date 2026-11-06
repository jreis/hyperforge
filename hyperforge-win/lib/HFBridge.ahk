; HFBridge.ahk — `HF_*` verbs for user Scripts (Hyper + J), mirrors macOS HyperForge's
; `HF.*` JavaScript bridge (ScriptStore.swift) one-for-one where a Windows equivalent
; exists. Each Scripts\*.ahk file runs as its own AutoHotkey process (see Scripts.ahk),
; so this is a plain #Include, not a shared-state API — every call re-resolves the
; active window / clipboard / config fresh.
;
;   #Include "%A_ScriptDir%\..\lib\HFBridge.ahk"   (or the absolute path Scripts.ahk seeds)
;
; HF_Snap(position)       — "left" "right" "top" "bottom" "max" "center"
;                            "tl" "tr" "bl" "br" "thirdLeft" "thirdCenter" "thirdRight"
;                            "twoThirdsLeft" "twoThirdsRight" "almostMax"
; HF_Notify(message)      — toast (respects general.toasts like the rest of HyperForge)
; HF_Log(message)         — appends to scripts.log under %APPDATA%\HyperForge
; HF_ClipboardGet()       — current clipboard text
; HF_ClipboardSet(text)   — replace clipboard text
; HF_PasteText(text)      — set clipboard then send Ctrl+V
; HF_PressKey(chord)      — Send() a chord verbatim, AHK syntax (e.g. "^!4", "{F5}")
; HF_LaunchApp(pathOrExe) — run / focus / minimize-cycle, same as Hyper app-launch chords
; HF_RunShortcut(name)    — run "<shortcuts_dir>\<name>.ps1" (Windows has no Shortcuts.app;
;                            named PowerShell scripts are the closest reusable-action analog)
; HF_Sleep(ms)

HF_Snap(position) {
    hwnd := WinExist("A")
    if !hwnd
        return false
    if (position = "center") {
        MonitorGetWorkArea(, &L, &T, &R, &B)
        HF_CenterActiveWindow(hwnd, L, T, R, B)
        return true
    }
    rect := HF_SnapRect(position)
    if !IsObject(rect)
        return false
    MonitorGetWorkArea(, &L, &T, &R, &B)
    w := R - L, h := B - T
    x := L + Round(w * rect.rx), y := T + Round(h * rect.ry)
    nw := Round(w * rect.rw), nh := Round(h * rect.rh)
    try WinRestore("ahk_id " hwnd)
    WinMove x, y, nw, nh, "ahk_id " hwnd
    return true
}

; rx/ry/rw/rh are fractions of the work area (0..1) — same layout as macOS WindowManager.
HF_SnapRect(position) {
    switch position {
        case "left":           return { rx: 0,   ry: 0,   rw: 0.5, rh: 1 }
        case "right":          return { rx: 0.5, ry: 0,   rw: 0.5, rh: 1 }
        case "top":            return { rx: 0,   ry: 0,   rw: 1,   rh: 0.5 }
        case "bottom":         return { rx: 0,   ry: 0.5, rw: 1,   rh: 0.5 }
        case "max":            return { rx: 0,   ry: 0,   rw: 1,   rh: 1 }
        case "tl":             return { rx: 0,   ry: 0,   rw: 0.5, rh: 0.5 }
        case "tr":             return { rx: 0.5, ry: 0,   rw: 0.5, rh: 0.5 }
        case "bl":             return { rx: 0,   ry: 0.5, rw: 0.5, rh: 0.5 }
        case "br":             return { rx: 0.5, ry: 0.5, rw: 0.5, rh: 0.5 }
        case "thirdLeft":       return { rx: 0,   ry: 0, rw: 1/3, rh: 1 }
        case "thirdCenter":     return { rx: 1/3, ry: 0, rw: 1/3, rh: 1 }
        case "thirdRight":      return { rx: 2/3, ry: 0, rw: 1/3, rh: 1 }
        case "twoThirdsLeft":   return { rx: 0,   ry: 0, rw: 2/3, rh: 1 }
        case "twoThirdsRight":  return { rx: 1/3, ry: 0, rw: 2/3, rh: 1 }
        case "almostMax":       return { rx: 0.05, ry: 0.05, rw: 0.9, rh: 0.9 }
        default:                return false
    }
}

HF_CenterActiveWindow(hwnd, L, T, R, B) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    aw := R - L, ah := B - T
    nx := L + (aw - w) // 2
    ny := T + (ah - h) // 2
    try WinRestore("ahk_id " hwnd)
    WinMove nx, ny, w, h, "ahk_id " hwnd
}

HF_Notify(message) {
    g := Gui("+AlwaysOnTop +ToolWindow -Caption")
    g.SetFont("s11")
    g.AddText("w260 Center", message)
    g.Show("x0 y0 NoActivate")
    SetTimer(() => (g.Hide(), g.Destroy()), -1200)
}

HF_Log(message) {
    dir := A_AppData "\HyperForge"
    if !DirExist(dir)
        DirCreate(dir)
    FileAppend(FormatTime() " " message "`n", dir "\scripts.log", "UTF-8")
}

HF_ClipboardGet() {
    return A_Clipboard
}

HF_ClipboardSet(text) {
    A_Clipboard := text
}

HF_PasteText(text) {
    A_Clipboard := text
    Sleep 50
    Send "^v"
}

HF_PressKey(chord) {
    Send chord
}

HF_LaunchApp(pathOrExe) {
    exeOnly := pathOrExe
    if RegExMatch(pathOrExe, 'i)^("[^"]+"|[^ ]+\.exe)', &m)
        exeOnly := Trim(m[1], '"')
    SplitPath exeOnly, &exeFile
    if (exeFile = "") {
        Run pathOrExe
        return
    }
    pid := ProcessExist(exeFile)
    if (pid = 0) {
        Run pathOrExe
        return
    }
    SetTitleMatchMode 2
    DetectHiddenWindows false
    if WinActive("ahk_pid " pid)
        WinMinimize "ahk_pid " pid
    else if WinExist("ahk_pid " pid)
        WinActivate "ahk_pid " pid
}

HF_RunShortcut(name) {
    dir := A_ScriptDir "\..\shortcuts"
    ps1 := dir "\" name ".ps1"
    if !FileExist(ps1) {
        HF_Notify('No shortcut "' name '" — add ' ps1)
        return
    }
    Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '"'
}

HF_Sleep(ms) {
    Sleep Max(0, ms)
}

HF_UIASelectorPairs(raw) {
    pairs := []
    raw := Trim(raw)
    if (raw = "")
        return pairs
    Loop Parse, raw, ";" {
        part := Trim(A_LoopField)
        if (part = "")
            continue
        p := InStr(part, "=")
        if (p <= 1)
            continue
        key := StrLower(Trim(SubStr(part, 1, p - 1)))
        val := Trim(SubStr(part, p + 1))
        if (key = "" || val = "")
            continue
        pairs.Push({ key: key, val: val })
    }
    return pairs
}

HF_UIASingleQuoted(text) {
    return "'" StrReplace(text, "'", "''") "'"
}

HF_UIASelectorExpression(raw, curVar := "$cur") {
    map := Map(
        "automationid", "AutomationId",
        "name", "Name",
        "classname", "ClassName",
        "controltype", "ControlType.ProgrammaticName"
    )
    pairs := HF_UIASelectorPairs(raw)
    if !pairs.Length
        return "$true"
    checks := []
    for pair in pairs {
        if !map.Has(pair.key)
            continue
        if (pair.key = "controltype")
            checks.Push("((" curVar ".ControlType) -and (" curVar ".ControlType.ProgrammaticName -eq " HF_UIASingleQuoted(pair.val) "))")
        else
            checks.Push("(" curVar "." map[pair.key] " -eq " HF_UIASingleQuoted(pair.val) ")")
    }
    if !checks.Length
        return "$true"
    expr := checks[1]
    i := 2
    while (i <= checks.Length) {
        expr .= " -and " checks[i]
        i++ }
    return expr
}

HF_UIABuildWebActionSource(processName, windowTitle, inputSelector, submitSelector, text) { processName := Trim(processName)
    if (processName = "")
        processName := "chrome"
    processName := RegExReplace(processName, "i)\.exe$", "")
    inputExpr := HF_UIASelectorExpression(inputSelector)
    submitExpr := HF_UIASelectorExpression(submitSelector)

    ps := "$ErrorActionPreference = 'Stop'`n"
    ps .= "Add-Type -AssemblyName UIAutomationClient`n"
    ps .= "Add-Type -AssemblyName UIAutomationTypes`n`n"
    ps .= "$hfProc = " HF_UIASingleQuoted(processName) "`n"
    ps .= "$hfTitle = " HF_UIASingleQuoted(Trim(windowTitle)) "`n"
    ps .= "$hfText = " HF_UIASingleQuoted(text) "`n"
    ps .= "$hfInputExpr = { param($cur) " inputExpr " }`n"
    ps .= "$hfSubmitExpr = { param($cur) " submitExpr " }`n`n"
    ps .= "$procs = Get-Process -Name $hfProc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }`n"
    ps .= "if ($hfTitle -ne '') { $procs = $procs | Where-Object { $_.MainWindowTitle -like ('*' + $hfTitle + '*') } }`n"
    ps .= "$proc = $procs | Select-Object -First 1`n"
    ps .= "if (-not $proc) { exit 2 }`n"
    ps .= "$root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$proc.MainWindowHandle)`n"
    ps .= "if (-not $root) { exit 3 }`n"
    ps .= "$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)`n"
    ps .= "$input = $null`n"
    ps .= "foreach ($el in $all) { $cur = $el.Current; if (& $hfInputExpr $cur) { $input = $el; break } }`n"
    ps .= "if (-not $input) { exit 4 }`n"
    ps .= "try { $vp = $input.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $vp.SetValue($hfText) } else { exit 5 } } catch { exit 5 }`n"
    ps .= "if (" HF_UIASingleQuoted(Trim(submitSelector)) " -ne '') {`n"
    ps .= "  $clicked = $false`n"
    ps .= "  foreach ($el in $all) { $cur = $el.Current; if (& $hfSubmitExpr $cur) {`n"
    ps .= "    try { $ip = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern); if ($ip) { $ip.Invoke(); $clicked = $true; break } } catch {}`n"
    ps .= "  } }`n"
    ps .= "  if (-not $clicked) { exit 6 }`n"
    ps .= "}`n"
    ps .= "'ok'`n"
    return ps
}

HF_UIARunPowerShell(command) {
    sh := ComObject("WScript.Shell")
    ex := sh.Exec(command)
    while (ex.Status = 0)
        Sleep(10)
    return {
        code: ex.ExitCode,
        out: ex.StdOut.ReadAll(),
        err: ex.StdErr.ReadAll()
    }
}

HF_UIAClipboardToWebAction(url, processName, windowTitle, inputSelector, submitSelector := "", delayMs := 1200) {
    text := Trim(HF_ClipboardGet())
    if (text = "") {
        HF_Notify("Clipboard is empty")
        return false
    }
    if (url != "")
        Run url
    Sleep Max(0, delayMs)

    ps1 := A_Temp "\\hf-script-uia-web-action.ps1"
    try FileDelete(ps1)
    try FileAppend(HF_UIABuildWebActionSource(processName, windowTitle, inputSelector, submitSelector, text), ps1, "UTF-8")

    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '"'
    result := HF_UIARunPowerShell(cmd)
    if (result.code != 0) {
        HF_Notify("UIA action failed (" result.code ")")
        return false
    }
    HF_Notify("UIA action sent")
    return true
}
