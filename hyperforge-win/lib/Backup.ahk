; Backup.ahk — export / import config + clipboard history (macOS Privacy backup)

RegisterBackupHotkeys() {
    ; No default Hyper chord — use command bar or tray.
}

ExportHyperForgeConfig(*) {
    dest := FileSelect("S16", A_MyDocuments "\hyperforge-backup-" FormatTime(, "yyyy-MM-dd") ".json", "Export HyperForge", "JSON (*.json)")
    if (dest = "")
        return
    clipPath := EnvGet("APPDATA") "\HyperForge\clipboard-history.dat"
    clip := FileExist(clipPath) ? FileRead(clipPath) : ""
    cfg := FileExist(A_ScriptDir "\config.ini") ? FileRead(A_ScriptDir "\config.ini") : ""
    blob := '{'
        . '"version":1,'
        . '"exported":"' FormatTime(, "yyyy-MM-dd HH:mm:ss") '",'
        . '"configIni":' _jsonStr(cfg) ','
        . '"clipboardHistory":' _jsonStr(clip)
        . '}'
    try FileDelete(dest)
    FileAppend blob, dest, "UTF-8"
    ShowMsg("Exported config")
}

ImportHyperForgeConfig(*) {
    src := FileSelect(1, A_MyDocuments, "Import HyperForge", "JSON (*.json)")
    if (src = "")
        return
    raw := FileRead(src)
    if !RegExMatch(raw, '"configIni"\s*:\s*"(.*?)"(,|})', &m) {
        ShowMsg("Not a HyperForge backup")
        return
    }
    ; Prefer simple fields written by ExportHyperForgeConfig
    cfg := _jsonExtract(raw, "configIni")
    clip := _jsonExtract(raw, "clipboardHistory")
    if (cfg != "") {
        try FileCopy(A_ScriptDir "\config.ini", A_ScriptDir "\config.ini.bak", true)
        try FileDelete(A_ScriptDir "\config.ini")
        FileAppend cfg, A_ScriptDir "\config.ini", "UTF-8"
    }
    if (clip != "") {
        dir := EnvGet("APPDATA") "\HyperForge"
        DirCreate(dir)
        try FileDelete(dir "\clipboard-history.dat")
        FileAppend clip, dir "\clipboard-history.dat", "UTF-8"
        ClipHistory_Load()
    }
    ShowMsg("Imported — reload HyperForge")
}

_jsonStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    s := StrReplace(s, '"', '\"')
    return '"' s '"'
}

_jsonExtract(raw, key) {
    if !RegExMatch(raw, '"' key '"\s*:\s*"((?:\\.|[^"\\])*)"', &m)
        return ""
    s := m[1]
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\t", "`t")
    s := StrReplace(s, "\\", "\")
    return s
}
