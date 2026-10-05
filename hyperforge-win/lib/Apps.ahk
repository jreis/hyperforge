; Apps.ahk — Hyper app launch / focus / minimize cycle

ExeNameFromCommand(Program) {
    if RegExMatch(Program, 'i)"([^"]+\.exe)"', &m)
        return m[1]
    if RegExMatch(Program, 'i)([^\\/:*?"<>|\r\n]+\.exe)', &m)
        return m[1]
    SplitPath Program, &name
    return name
}

; Quote an executable path that contains spaces. Leave `wt -d "..."` alone.
QuoteCmd(Program) {
    Program := Trim(Program)
    if (Program = "" || SubStr(Program, 1, 1) = '"')
        return Program
    if RegExMatch(Program, 'i)^(.*?\.exe)(\s+.*)?$', &m) {
        tail := (m.Count >= 2 && m[2] != "") ? m[2] : ""
        if InStr(m[1], " ")
            return '"' m[1] '"' tail
        return Program
    }
    return Program
}

RunOrActivateOrMinimizeProgram(Program) {
    exeOnly := ExeNameFromCommand(Program)
    SplitPath exeOnly, &ExeFile
    if (ExeFile = "") {
        try Run QuoteCmd(Program)
        catch
            ShowMsg("Could not start " Program)
        return
    }
    PID := ProcessExist(ExeFile)
    if (PID = 0) {
        try Run QuoteCmd(Program)
        catch
            ShowMsg("Could not start " ExeFile)
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
            return DefaultTeamsPath()
        default:
            return ""
    }
}

; Classic Teams if it is still installed; otherwise the Windows 11 execution alias.
DefaultTeamsPath() {
    classic := EnvGet("LOCALAPPDATA") "\Microsoft\Teams\current\Teams.exe"
    if FileExist(classic)
        return classic
    return "ms-teams.exe"
}

AppPath(name) {
    p := HFConfig.Path(name, "")
    if (p != "")
        return p
    return _defaultPath(name)
}

ChromeCommand() {
    chrome := AppPath("chrome")
    if (chrome = "")
        chrome := "chrome.exe"
    port := HFConfig.Get("paths.chrome_debug_port", "")
    if (port != "" && !InStr(chrome, "--remote-debugging-port"))
        return chrome " --remote-debugging-port=" port
    return chrome
}

; Quoted form, so `Run ChromeCmd() " https://..."` still works from work.ahk.
ChromeCmd() {
    return QuoteCmd(ChromeCommand())
}

ChromeLaunch(url := "") {
    cmd := ChromeCmd()
    if (url != "")
        cmd .= " " Chr(34) url Chr(34)
    try Run cmd
    catch
        ShowMsg("Could not start Chrome")
}

LaunchTeams() {
    t := AppPath("teams")
    if (t = "") {
        ShowMsg("Set paths.teams in config.ini")
        return
    }
    RunOrActivateOrMinimizeProgram(t)
}

LaunchTerminalHere() {
    folder := GetFolder()
    term := HFConfig.Path("terminal", "wt")
    try {
        if (folder != "")
            Run QuoteCmd(term) ' -d "' folder '"'
        else
            Run QuoteCmd(term)
    } catch {
        ShowMsg("Could not start terminal")
    }
}

EditHyperForge() {
    target := HFConfig.Path("edit_target", A_ScriptFullPath)
    code := AppPath("vscode") || _defaultPath("vscode")
    try {
        if FileExist(code)
            Run '"' code '" "' target '"'
        else
            Run 'notepad.exe "' target '"'
    } catch {
        Run 'notepad.exe "' target '"'
    }
}

RegisterAppHotkeys() {
    BindHyper("n", (*) => RunOrActivateOrMinimizeProgram(AppPath("notepad") || "notepad.exe"), "send")
    BindHyper("v", (*) => RunOrActivateOrMinimizeProgram(AppPath("vscode") || _defaultPath("vscode")), "send")
    BindHyper("c", (*) => RunOrActivateOrMinimizeProgram(ChromeCommand()), "send")
    BindHyper("t", (*) => LaunchTeams(), "send")
    BindHyper("e", (*) => Run("explorer.exe"), "send")
    BindHyper("4", (*) => RunOrActivateOrMinimizeProgram(AppPath("outlook") || _defaultPath("outlook")), "send")
    BindHyper("g", (*) => ChromeLaunch("https://www.google.com/search?q=" UrlEncode(A_Clipboard)), "send")
    BindHyper("d", (*) => CloseActive())
    BindHyper("x", (*) => LaunchTerminalHere(), "send")
    BindHyper("r", (*) => LaunchSearchHere(), "send")
    BindHyper("h", (*) => EditHyperForge(), "send")
    BindHyper("s", (*) => LaunchHyperS(), "send")
}

LaunchSearchHere() {
    folder := GetFolder()
    search := HFConfig.Path("search", "")
    if (search = "") {
        ShowMsg("Set paths.search in config.ini")
        return
    }
    try {
        if (folder != "")
            Run QuoteCmd(search) ' -d "' folder '"'
        else
            Run QuoteCmd(search)
    } catch {
        ShowMsg("Could not start search")
    }
}

LaunchHyperS() {
    url := HFConfig.Get("apps.hyper_s_url", "")
    if (url = "") {
        ShowMsg("Set apps.hyper_s_url or use work module")
        return
    }
    ChromeLaunch(url)
}
