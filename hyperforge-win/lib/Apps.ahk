; Apps.ahk — Hyper app launch / focus / minimize cycle

RunOrActivateOrMinimizeProgram(Program) {
    ; Allow args after .exe (e.g. chrome --flags)
    exeOnly := Program
    if RegExMatch(Program, 'i)^("[^"]+"|[^ ]+\.exe)', &m)
        exeOnly := Trim(m[1], '"')
    SplitPath exeOnly, &ExeFile
    if (ExeFile = "") {
        Run Program
        return
    }
    PID := ProcessExist(ExeFile)
    if (PID = 0) {
        Run Program
        return
    }
    SetTitleMatchMode 2
    DetectHiddenWindows false
    if WinActive("ahk_pid " PID)
        WinMinimize "ahk_pid " PID
    else if WinExist("ahk_pid " PID)
        WinActivate "ahk_pid " PID
}

_defaultPath(name) {
    switch name {
        case "notepad":
            return "notepad.exe"
        case "vscode":
            return "C:\Program Files\Microsoft VS Code\Code.exe"
        case "chrome":
            return "C:\Program Files\Google\Chrome\Application\chrome.exe"
        case "outlook":
            return "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE"
        case "teams":
            ; Store / classic install vary — user should set paths.teams
            return EnvGet("LOCALAPPDATA") "\Microsoft\Teams\current\Teams.exe"
        default:
            return ""
    }
}

AppPath(name) {
    p := HFConfig.Path(name, "")
    if (p != "")
        return p
    return _defaultPath(name)
}

ChromeCmd() {
    chrome := AppPath("chrome")
    if InStr(chrome, "--")
        return chrome
    return chrome ' --remote-debugging-port=9222'
}

RegisterAppHotkeys() {
    ; Hyper + N / V / C / T / E / 4 — config-driven with defaults
    Hotkey "#^!+n", (*) => RunOrActivateOrMinimizeProgram(AppPath("notepad") || "notepad.exe")
    Hotkey "#^!+v", (*) => RunOrActivateOrMinimizeProgram(AppPath("vscode") || _defaultPath("vscode"))
    Hotkey "#^!+c", (*) => RunOrActivateOrMinimizeProgram(ChromeCmd())
    Hotkey "#^!+t", (*) => {
        t := AppPath("teams")
        if FileExist(t) || InStr(t, "ms-teams:") || t != ""
            RunOrActivateOrMinimizeProgram(t)
        else
            ShowMsg("Set paths.teams in config.ini")
    }
    Hotkey "#^!+e", (*) => Run("explorer.exe")
    Hotkey "#^!+4", (*) => RunOrActivateOrMinimizeProgram(AppPath("outlook") || _defaultPath("outlook"))

    ; Hyper + G — Google selection / clipboard
    Hotkey "#^!+g", (*) => {
        q := UrlEncode(A_Clipboard)
        Run ChromeCmd() ' "https://www.google.com/search?q=' q '"'
    }

    ; Hyper + D — close active window
    Hotkey "#^!+d", (*) => WinClose("A")

    ; Hyper + X — Windows Terminal in Explorer folder
    Hotkey "#^!+x", (*) => {
        folder := GetFolder()
        term := HFConfig.Path("terminal", "wt")
        if (folder != "")
            Run term ' -d "' folder '"'
        else
            Run term
    }

    ; Hyper + R — optional search tool in folder
    Hotkey "#^!+r", (*) => {
        folder := GetFolder()
        search := HFConfig.Path("search", "")
        if (search = "") {
            ShowMsg("Set paths.search in config.ini")
            return
        }
        if (folder != "")
            Run search ' -d "' folder '"'
        else
            Run search
    }

    ; Hyper + H — edit config / script target
    Hotkey "#^!+h", (*) => {
        target := HFConfig.Path("edit_target", A_ScriptFullPath)
        code := AppPath("vscode") || _defaultPath("vscode")
        if FileExist(code)
            Run '"' code '" "' target '"'
        else
            Run 'notepad.exe "' target '"'
    }

    ; Hyper + S — optional URL (generic; override in work module)
    Hotkey "#^!+s", (*) => {
        url := HFConfig.Get("apps.hyper_s_url", "")
        if (url = "") {
            ShowMsg("Set apps.hyper_s_url or use work module")
            return
        }
        Run ChromeCmd() " " url
    }
}
