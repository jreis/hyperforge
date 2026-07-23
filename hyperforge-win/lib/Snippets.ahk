; Snippets.ahk — hotstrings from config [snippets]

RegisterSnippets() {
    ; Built-in useful defaults (override via config.ini [snippets])
    defaults := Map(
        ",mach", "{ComputerName}",
        ",v", "{Clipboard}",
        "@@", "you@example.com",
        "tj", "Thanks,`nYour Name"
    )
    ; Load from config keys that look like snippets.xxx
    for key, val in HFConfig.data {
        if SubStr(key, 1, 9) = "snippets." {
            trigger := SubStr(key, 10)
            if (trigger != "" && val != "")
                defaults[trigger] := val
        }
    }
    for trigger, expansion in defaults {
        if (expansion = "")
            continue
        ; Hotstring needs a bound expansion
        _regHotstring(trigger, expansion)
    }
}

_regHotstring(trigger, expansion) {
    ; Use :*?: for flexible expand
    try Hotstring(":*:" trigger, _snippetHandler.Bind(expansion))
}

_snippetHandler(expansion, *) {
    if (expansion = "{ComputerName}") {
        SendText A_ComputerName
        return
    }
    if (expansion = "{Clipboard}") {
        SendText A_Clipboard
        return
    }
    ; `n in config → newline
    text := StrReplace(expansion, "``n", "`n")
    text := StrReplace(text, "`n", "`n")
    SendText text
}
