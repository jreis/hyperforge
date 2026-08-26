; Scripts.ahk — Hyper + J → run user-authored .ahk automations from scripts\
; Windows parity for macOS HyperForge's JavaScript Scripts (Hyper+⇧Y): AHK already
; *is* a full scripting language, so instead of embedding a second interpreter, each
; script is a standalone .ahk file spawned as its own AutoHotkey process (edits take
; effect on the next run — no reload of HyperForge.ahk needed). HFBridge.ahk gives
; scripts the same `HF.*`-shaped verbs as the macOS bridge (snap/notify/clipboard/
; pasteText/pressKey/launchApp/runShortcut/sleep/log).

RegisterScriptsHotkeys() {
    SeedBuiltInScripts()
    HotIf HyperAllowed
    ; J — Y is region pin. Linux Scripts picker is Hyper+J.
    Hotkey "#^!+j", (*) => ShowScriptsMenu()
    HotIf
}

ScriptsDir() {
    dir := HFConfig.Path("scripts_dir", A_ScriptDir "\scripts")
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

BridgeIncludeLine() {
    return '#Include "' A_ScriptDir '\lib\HFBridge.ahk"`n`n'
}

SeedBuiltInScripts() {
    dir := ScriptsDir()
    count := 0
    Loop Files dir "\*.ahk"
        count++
    if (count > 0)
        return

    inc := BridgeIncludeLine()

    _writeScript(dir "\Say hello.ahk"
        , inc
        . '; Say hello — minimal example: one HF call.`n'
        . 'HF_Notify("Hello from HyperForge")`n')

    _writeScript(dir "\Snap left and notify.ahk"
        , inc
        . '; Snap left and notify — HF_Snap + HF_Notify together.`n'
        . 'HF_Snap("left")`n'
        . 'HF_Notify("Snapped left")`n')

    _writeScript(dir "\Uppercase clipboard.ahk"
        , inc
        . '; Uppercase clipboard — HF_ClipboardGet / HF_ClipboardSet round-trip.`n'
        . 'text := HF_ClipboardGet()`n'
        . 'if (text != "") {`n'
        . '    HF_ClipboardSet(StrUpper(text))`n'
        . '    HF_Notify("Clipboard uppercased")`n'
        . '} else {`n'
        . '    HF_Notify("Clipboard is empty")`n'
        . '}`n')

    _writeScript(dir "\New timestamped note.ahk"
        , inc
        . '; New timestamped note — HF_LaunchApp + HF_Sleep + HF_PasteText.`n'
        . 'stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")`n'
        . 'HF_LaunchApp("notepad.exe")`n'
        . 'HF_Sleep(400)`n'
        . 'HF_PasteText("Note — " stamp "``n")`n')

    _writeScript(dir "\Toggle Focus (Shortcut).ahk"
        , inc
        . '; Toggle Focus — HF_RunShortcut runs a named .ps1 from the shortcuts\ folder.`n'
        . 'HF_RunShortcut("Toggle Focus")`n'
        . 'HF_Sleep(200)`n'
        . 'HF_Notify("Focus toggled")`n')
}

_writeScript(path, source) {
    try FileAppend(source, path, "UTF-8")
}

ShowScriptsMenu(*) {
    dir := ScriptsDir()
    m := Menu()
    found := false
    Loop Files dir "\*.ahk" {
        found := true
        m.Add(RegExReplace(A_LoopFileName, "\.ahk$", ""), RunScript.Bind(A_LoopFileFullPath))
    }
    if !found
        m.Add("No scripts — add .ahk files to " dir, (*) => Run('explorer.exe "' dir '"'))
    m.Add()
    m.Add("Open scripts folder", (*) => Run('explorer.exe "' dir '"'))
    m.Show()
}

RunScript(path, *) {
    SplitPath path, &name
    name := RegExReplace(name, "\.ahk$", "")
    ShowMsg("Running " name)
    try {
        Run '"' A_AhkPath '" /ErrorStdOut "' path '"'
    } catch as e {
        ShowMsg("Script error: " e.Message)
    }
}
