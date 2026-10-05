; Backup.ahk — export / import config + clipboard history.
; Version 2 stores both payloads as base64 so Windows paths survive the round trip.
; Version 1 (escaped JSON strings) still imports.

RegisterBackupHotkeys() {
    ; No default Hyper chord — command bar and the tray menu call these.
}

EncodeHyperForgeBackup(cfg, clip) {
    return '{"version":2,"exported":"' FormatTime(, "yyyy-MM-dd HH:mm:ss") '","configIniB64":'
        . _jsonStr(Base64Encode(cfg))
        . ',"clipboardHistoryB64":'
        . _jsonStr(Base64Encode(clip))
        . '}'
}

DecodeHyperForgeBackup(raw) {
    if (raw = "")
        return ""
    if (SubStr(raw, 1, 1) = Chr(0xFEFF))
        raw := SubStr(raw, 2)
    if InStr(raw, '"configIniB64"') {
        return {
            config: Base64Decode(ExtractJsonString(raw, "configIniB64")),
            clipboard: Base64Decode(ExtractJsonString(raw, "clipboardHistoryB64"))
        }
    }
    if !InStr(raw, '"configIni"')
        return ""
    return {
        config: ExtractJsonString(raw, "configIni"),
        clipboard: ExtractJsonString(raw, "clipboardHistory")
    }
}

ExportHyperForgeConfig(*) {
    dest := FileSelect("S16", A_MyDocuments "\hyperforge-backup-" FormatTime(, "yyyy-MM-dd") ".json", "Export HyperForge", "JSON (*.json)")
    if (dest = "")
        return
    clipPath := EnvGet("APPDATA") "\HyperForge\clipboard-history.dat"
    clip := FileExist(clipPath) ? FileRead(clipPath, "UTF-8") : ""
    cfg := FileExist(A_ScriptDir "\config.ini") ? FileRead(A_ScriptDir "\config.ini", "UTF-8") : ""
    blob := EncodeHyperForgeBackup(cfg, clip)
    f := FileOpen(dest, "w", "UTF-8-RAW")
    if !f {
        ShowMsg("Export failed")
        return
    }
    f.Write(blob)
    f.Close()
    ShowMsg("Exported config")
}

ImportHyperForgeConfig(*) {
    src := FileSelect(1, A_MyDocuments, "Import HyperForge", "JSON (*.json)")
    if (src = "")
        return
    decoded := DecodeHyperForgeBackup(FileRead(src, "UTF-8"))
    if !IsObject(decoded) {
        ShowMsg("Not a HyperForge backup")
        return
    }
    if (decoded.config != "") {
        try FileCopy(A_ScriptDir "\config.ini", A_ScriptDir "\config.ini.bak", true)
        f := FileOpen(A_ScriptDir "\config.ini", "w", "UTF-8-RAW")
        if !f {
            ShowMsg("Could not write config.ini")
            return
        }
        f.Write(decoded.config)
        f.Close()
    }
    if (decoded.clipboard != "") {
        dir := EnvGet("APPDATA") "\HyperForge"
        DirCreate(dir)
        f := FileOpen(dir "\clipboard-history.dat", "w", "UTF-8-RAW")
        if f {
            f.Write(decoded.clipboard)
            f.Close()
            ClipHistory_Load()
        }
    }
    ShowMsg("Imported — reloading")
    SetTimer((*) => Reload(), -400)
}

_jsonStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    s := StrReplace(s, '"', '\"')
    return '"' s '"'
}

ExtractJsonString(raw, key) {
    q := Chr(34)
    marker := q . key . q
    pos := InStr(raw, marker)
    if !pos
        return ""
    i := pos + StrLen(marker)
    while (i <= StrLen(raw) && InStr(" `t`r`n", SubStr(raw, i, 1)))
        i++
    if (SubStr(raw, i, 1) != ":")
        return ""
    i++
    while (i <= StrLen(raw) && InStr(" `t`r`n", SubStr(raw, i, 1)))
        i++
    if (SubStr(raw, i, 1) != q)
        return ""
    i++
    out := ""
    while (i <= StrLen(raw)) {
        ch := SubStr(raw, i, 1)
        if (ch = "\") {
            n := SubStr(raw, i + 1, 1)
            if (n = "n")
                out .= "`n"
            else if (n = "r")
                out .= "`r"
            else if (n = "t")
                out .= "`t"
            else if (n = "\")
                out .= "\"
            else if (n = q)
                out .= q
            else
                out .= n
            i += 2
        } else if (ch = q) {
            return out
        } else {
            out .= ch
            i++
        }
    }
    return ""
}
