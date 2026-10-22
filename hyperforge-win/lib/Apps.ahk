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

RunOrActivateOrMinimizeProgram(Program, processHint := "") {
    exeOnly := ExeNameFromCommand(processHint != "" ? processHint : Program)
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
    if WinActive("ahk_exe " ExeFile)
        WinMinimize "A"
    else if hwnd := WinExist("ahk_exe " ExeFile)
        WinActivate "ahk_id " hwnd
    else {
        try Run QuoteCmd(Program)
        catch
            ShowMsg("Could not start " ExeFile)
    }
}

EnsureEditorBootstrapEnv() {
    static loadedFor := ""
    bootstrap := Trim(HFConfig.Get("apps.editor_env_bootstrap", ""))
    if (bootstrap = "" || loadedFor = bootstrap)
        return true

    tmpName := "hf-editor-env-" A_TickCount ".txt"
    tmp := A_Temp "\\" tmpName
    escapedBootstrap := StrReplace(bootstrap, '"', '""')
    cmd := A_ComSpec ' /d /s /c "' escapedBootstrap ' & set > ' tmpName '"'
    ok := false
    try {
        RunWait(cmd, A_Temp, "Hide")
        if FileExist(tmp) {
            Loop Read tmp {
                line := A_LoopReadLine
                p := InStr(line, "=")
                if (p <= 1)
                    continue
                key := SubStr(line, 1, p - 1)
                val := SubStr(line, p + 1)
                EnvSet(key, val)
            }
            ok := true
        }
    }
    try FileDelete(tmp)
    if ok
        loadedFor := bootstrap
    return ok
}

IsNvimEditor(editor) {
    exe := StrLower(ExeNameFromCommand(editor))
    return (exe = "nvim.exe" || exe = "nvim")
}

TerminalProcessHint(term) {
    exe := StrLower(ExeNameFromCommand(term))
    if (exe = "wt" || exe = "wt.exe" || exe = "windowsterminal.exe")
        return "WindowsTerminal.exe"
    return exe
}

_PowerShellEscapeForDoubleQuotes(s) {
    return StrReplace(s, Chr(34), '`"')
}

_PowerShellSingleQuoted(s) {
    return "'" StrReplace(s, "'", "''") "'"
}

WriteNvimPowerShellLauncher(editor, args := "", includeBootstrapImport := true) {
    path := A_Temp "\\hf-nvim-launch.ps1"
    body := "if (Test-Path $PROFILE) { . $PROFILE }`r`n"
    bootstrap := Trim(HFConfig.Get("apps.editor_env_bootstrap", ""))
    if (includeBootstrapImport && bootstrap != "") {
        body .= "$hfBootstrap = " _PowerShellSingleQuoted(bootstrap) "`r`n"
        body .= "$hfEnv = & cmd.exe /d /s /c " Chr(34) "$hfBootstrap & set" Chr(34) "`r`n"
        body .= "foreach ($hfLine in $hfEnv) {`r`n"
        body .= "  if ($hfLine -match '^[^=]+=') {`r`n"
        body .= "    $hfName, $hfValue = $hfLine -split '=', 2`r`n"
        body .= "    Set-Item -Path ('Env:' + $hfName) -Value $hfValue`r`n"
        body .= "  }`r`n"
        body .= "}`r`n"
    }
    body .= "& " _PowerShellSingleQuoted(editor)
    if (args != "")
        body .= " " args
    body .= "`r`n"
    try FileDelete(path)
    FileAppend(body, path)
    return path
}

LaunchNvimInTerminal(editor, args := "") {
    term := HFConfig.Path("terminal", "wt")
    processHint := TerminalProcessHint(term)
    try Run QuoteCmd(term)
    catch
        return false

    if !WinWaitActive("ahk_exe " processHint, , 2)
        return false

    cmd := "nvim"
    if (args != "")
        cmd .= " " args
    SendText(cmd)
    Send "{Enter}"
    return true
}

WriteNvimCmdLauncher(bootstrap, editor, args := "", shell := "") {
    path := A_Temp "\\hf-nvim-launch.cmd"
    body := "@echo off`r`n"
    body .= bootstrap "`r`n"
    shellExe := StrLower(ExeNameFromCommand(shell))
    if (shell != "" && (InStr(shellExe, "pwsh") || InStr(shellExe, "powershell"))) {
        psLauncher := WriteNvimPowerShellLauncher(editor, args, false)
        body .= QuoteCmd(shell) ' -NoLogo -NoExit -File "' psLauncher '"'
    } else {
        body .= QuoteCmd(editor)
        if (args != "")
            body .= " " args
    }
    body .= "`r`n"
    try FileDelete(path)
    FileAppend(body, path)
    return path
}

EditorProgramForLaunch(editor, args := "", &processHint := "") {
    cmd := QuoteCmd(editor)
    if (args != "")
        cmd .= " " args

    if IsNvimEditor(editor) {
        term := HFConfig.Path("terminal", "wt")
        shell := HFConfig.Path("terminal_shell", "powershell.exe")
        bootstrap := Trim(HFConfig.Get("apps.editor_env_bootstrap", ""))
        processHint := TerminalProcessHint(term)
        if (bootstrap != "") {
            cmdLauncher := WriteNvimCmdLauncher(bootstrap, editor, args, shell)
            return QuoteCmd(term) ' cmd.exe /d /k "' cmdLauncher '"'
        }
        shellExe := StrLower(ExeNameFromCommand(shell))
        if (InStr(shellExe, "pwsh") || InStr(shellExe, "powershell")) {
            psLauncher := WriteNvimPowerShellLauncher(editor, args)
            return QuoteCmd(term) " " QuoteCmd(shell) ' -NoLogo -NoExit -File "' psLauncher '"'
        }
        return QuoteCmd(term) " " QuoteCmd(shell) " " cmd
    }

    processHint := editor
    return cmd
}

EditorLaunchCommand(editor, args := "") {
    local processHint := ""
    return EditorProgramForLaunch(editor, args, &processHint)
}

LaunchPreferredTextEditor() {
    editor := PreferredTextEditor()
    if IsNvimEditor(editor) {
        if LaunchNvimInTerminal(editor)
            return
    }
    if !IsNvimEditor(editor) {
        if !EnsureEditorBootstrapEnv()
            ShowMsg("Editor env bootstrap failed; using current environment")
    }
    processHint := ""
    program := EditorProgramForLaunch(editor, "", &processHint)
    if IsNvimEditor(editor)
        Run program
    else
        RunOrActivateOrMinimizeProgram(program, processHint)
}

_defaultPath(name) {
    switch name {
        case "lazyvim":
            return DefaultLazyVimPath()
        case "notepad":
            return "notepad.exe"
        case "vscode":
            return DefaultVSCodePath()
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

DefaultLazyVimPath() {
    nvim := "C:\Program Files\Neovim\bin\nvim.exe"
    if FileExist(nvim)
        return nvim
    localPath := EnvGet("LOCALAPPDATA") "\nvim\bin\nvim.exe"
    if FileExist(localPath)
        return localPath
    try {
        if (RunWait(A_ComSpec ' /c where nvim >nul 2>nul', , "Hide") = 0)
            return "nvim.exe"
    }
    return ""
}

; System-wide install first, then the per-user build (the usual one on corporate
; machines, no admin needed). Falls back to the system path so errors name it.
DefaultVSCodePath() {
    system := "C:\Program Files\Microsoft VS Code\Code.exe"
    if FileExist(system)
        return system
    perUser := EnvGet("LOCALAPPDATA") "\Programs\Microsoft VS Code\Code.exe"
    if FileExist(perUser)
        return perUser
    return system
}

PreferredTextEditor() {
    return AppPath("lazyvim") || AppPath("notepad") || "notepad.exe"
}

OpenInTextEditor(path) {
    editor := PreferredTextEditor()
    try {
        if IsNvimEditor(editor) {
            if LaunchNvimInTerminal(editor, '"' path '"')
                return
        }
        if !IsNvimEditor(editor) {
            if !EnsureEditorBootstrapEnv()
                ShowMsg("Editor env bootstrap failed; using current environment")
        }
        processHint := ""
        Run EditorProgramForLaunch(editor, '"' path '"', &processHint)
    } catch {
        Run 'notepad.exe "' path '"'
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

; Hyper+G guard: one line, not huge. Keeps pasted documents, logs and multi-line
; secrets out of a Google search URL.
LooksLikeSearchQuery(s, maxLen := 200) {
    s := Trim(s)
    return (s != "" && StrLen(s) <= maxLen && !RegExMatch(s, "[\r\n]"))
}

; One-line preview for confirm prompts: whitespace runs collapsed, cut at maxLen
; characters with an ellipsis. Pure, so the smoke test can check it.
SendPreview(s, maxLen := 80) {
    one := Trim(RegExReplace(s, "\s+", " "))
    if (StrLen(one) > maxLen)
        return SubStr(one, 1, maxLen - 1) "…"
    return one
}

; Ask before clipboard text leaves the machine. True only on an explicit Yes;
; No is the default button so a stray Enter sends nothing.
ConfirmSend(dest, text) {
    ReleaseHyperModifiers()
    answer := MsgBox("Send this clipboard text to " dest "?`n`n" SendPreview(text), "HyperForge — confirm send", "YesNo Icon? Default2")
    return (answer = "Yes")
}

GoogleClipboard(*) {
    q := Trim(A_Clipboard)
    if !LooksLikeSearchQuery(q) {
        ShowMsg("Google: clipboard is empty, multi-line or too long — nothing sent")
        return
    }
    if !ConfirmSend("Google search", q)
        return
    ChromeLaunch("https://www.google.com/search?q=" UrlEncode(q))
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
            OpenInTextEditor(target)
    } catch {
        OpenInTextEditor(target)
    }
}

DevUrlsFromConfig() {
    raw := HFConfig.Get("apps.local_urls", "http://localhost:3000, http://localhost:5173, http://localhost:8080")
    urls := []
    Loop Parse, raw, "," {
        u := Trim(A_LoopField)
        if (u = "")
            continue
        if !RegExMatch(u, "i)^https?://")
            u := "http://" u
        urls.Push(u)
    }
    return urls
}

OpenDevUrl(url, *) {
    try Run url
    catch
        ShowMsg("Could not open " url)
}

OpenDevLocalhostMenu(*) {
    urls := DevUrlsFromConfig()
    if !urls.Length {
        ShowMsg("Set apps.local_urls in config.ini")
        return
    }
    m := Menu()
    for url in urls
        m.Add(url, OpenDevUrl.Bind(url))
    m.Show()
}

RegisterAppHotkeys() {
    BindHyper("n", (*) => LaunchPreferredTextEditor(), "send")
    BindHyper("v", (*) => RunOrActivateOrMinimizeProgram(AppPath("vscode") || _defaultPath("vscode")), "send")
    BindHyper("c", (*) => RunOrActivateOrMinimizeProgram(ChromeCommand()), "send")
    BindHyper("t", (*) => LaunchTeams(), "send")
    BindHyper("e", (*) => Run("explorer.exe"), "send")
    BindHyper("4", (*) => RunOrActivateOrMinimizeProgram(AppPath("outlook") || _defaultPath("outlook")), "send")
    BindHyper("5", (*) => OpenDevLocalhostMenu(), "send")
    BindHyper("g", (*) => GoogleClipboard(), "send")
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
