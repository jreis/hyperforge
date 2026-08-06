; Snippets.ahk — hotstrings from config [snippets]
; Token syntax matches macOS HyperForge's SnippetStore: {{date}}, {{date:FORMAT}},
; {{clipboard}}, {{hostname}}, {{uuid}}, {{lan-ip}}. `\n` / `\t` still expand to
; newline/tab for multi-line snippets (e.g. tj = sign-off).

RegisterSnippets() {
    ; Built-in useful defaults (override via config.ini [snippets])
    defaults := Map(
        ",sig", "Thanks,\nYour Name",
        ",v", "{{clipboard}}",
        "@@", "you@example.com",
        ",date", "{{date}}",
        ",host", "{{hostname}}",
        ",uuid", "{{uuid}}",
        "tj", "Thanks,\nYour Name"
    )
    ; Load from config keys that look like snippets.xxx ("date_format" is a
    ; reserved setting, not a hotstring trigger — see ResolveSnippetTokens).
    for key, val in HFConfig.data {
        if SubStr(key, 1, 9) = "snippets." {
            trigger := SubStr(key, 10)
            if (trigger != "" && trigger != "date_format" && val != "")
                defaults[trigger] := val
        }
    }
    for trigger, expansion in defaults {
        if (expansion = "")
            continue
        _regHotstring(trigger, expansion)
    }
}

_regHotstring(trigger, expansion) {
    ; Use :*?: for flexible expand
    try Hotstring(":*:" trigger, _snippetHandler.Bind(expansion))
}

_snippetHandler(expansion, *) {
    SendText ResolveSnippetTokens(expansion)
}

; Token set intentionally mirrors macOS: date / clipboard / hostname / uuid / lan-ip.
; Never add a shell/run token here — this fires on typed text, so an arbitrary-exec
; token would let any typed or pasted-in trigger string run code on expansion.
ResolveSnippetTokens(template) {
    out := StrReplace(template, "\n", "`n")
    out := StrReplace(out, "\t", "`t")
    out := _resolveDateTokens(out)
    if InStr(out, "{{clipboard}}")
        out := StrReplace(out, "{{clipboard}}", A_Clipboard)
    if InStr(out, "{{hostname}}")
        out := StrReplace(out, "{{hostname}}", A_ComputerName)
    if InStr(out, "{{uuid}}")
        out := StrReplace(out, "{{uuid}}", GenerateUUID())
    if InStr(out, "{{lan-ip}}")
        out := StrReplace(out, "{{lan-ip}}", LanIPAddress())
    return out
}

; `{{date}}` uses config.ini [snippets] date_format (default yyyy-MM-dd);
; `{{date:MM/dd/yyyy}}` overrides per token. Format tokens follow AHK's FormatTime
; (yyyy/MM/dd/HH/mm/ss/dddd/MMMM) — not ICU, so macOS-only tokens like EEEE won't work.
_resolveDateTokens(template) {
    if !InStr(template, "{{date")
        return template
    out := template
    pos := 1
    loop {
        start := RegExMatch(out, "\{\{date(?::([^}]+))?\}\}", &m, pos)
        if !start
            break
        fmt := (m.Count >= 1 && m[1] != "") ? m[1] : HFConfig.Get("snippets.date_format", "yyyy-MM-dd")
        stamp := FormatTime(, fmt)
        out := SubStr(out, 1, start - 1) stamp SubStr(out, start + m.Len[0])
        pos := start + StrLen(stamp)
    }
    return out
}

GenerateUUID() {
    buf := Buffer(16, 0)
    if DllCall("ole32\CoCreateGuid", "Ptr", buf) != 0
        return "00000000-0000-0000-0000-000000000000"
    s := ""
    Loop 16 {
        s .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        if (A_Index = 4 || A_Index = 6 || A_Index = 8 || A_Index = 10)
            s .= "-"
    }
    return s
}

; First non-loopback IPv4 via WMI (no shell-out; safe to call inline from a hotstring).
LanIPAddress() {
    try {
        for adapter in ComObjGet("winmgmts:")
            .ExecQuery("SELECT IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE")
        {
            if !IsSet(adapter.IPAddress)
                continue
            for ip in adapter.IPAddress {
                if (ip != "" && !InStr(ip, ":") && ip != "127.0.0.1")
                    return ip
            }
        }
    }
    return ""
}
