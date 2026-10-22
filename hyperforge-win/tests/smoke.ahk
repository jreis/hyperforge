; Pure-logic checks for HyperForge on Windows. No hotkeys, no windows moved.
;   AutoHotkey64.exe /ErrorStdOut tests\smoke.ahk
; Prints "ok <n>" and exits 0 on success. Exit 1 = assertion failures,
; exit 2 = unexpected runtime error. Warnings print to stdout, not a dialog.
; Includes resolve from A_ScriptDir, i.e. tests\, so ..\lib is the repo's lib\.

#Requires AutoHotkey v2.0+
#NoTrayIcon
#SingleInstance Off
#Warn All, StdOut
; Lib locals often share a name with a test global (dir, m, cfg…); that's harmless noise.
#Warn LocalSameAsGlobal, Off

#Include "%A_ScriptDir%\..\lib\Config.ahk"
#Include "%A_ScriptDir%\..\lib\Utils.ahk"
#Include "%A_ScriptDir%\..\lib\CapsHyper.ahk"
#Include "%A_ScriptDir%\..\lib\Mute.ahk"
#Include "%A_ScriptDir%\..\lib\Window.ahk"
#Include "%A_ScriptDir%\..\lib\Snippets.ahk"
#Include "%A_ScriptDir%\..\lib\Apps.ahk"
#Include "%A_ScriptDir%\..\lib\Explorer.ahk"
#Include "%A_ScriptDir%\..\lib\Clipboard.ahk"
#Include "%A_ScriptDir%\..\lib\Scroll.ahk"
#Include "%A_ScriptDir%\..\lib\QuickMenu.ahk"
#Include "%A_ScriptDir%\..\lib\Network.ahk"
#Include "%A_ScriptDir%\..\lib\KeepAlive.ahk"
#Include "%A_ScriptDir%\..\lib\Pin.ahk"
#Include "%A_ScriptDir%\..\lib\Doctor.ahk"
#Include "%A_ScriptDir%\..\lib\Catalog.ahk"
#Include "%A_ScriptDir%\..\lib\Backup.ahk"
#Include "%A_ScriptDir%\..\lib\Scripts.ahk"
#Include "%A_ScriptDir%\..\lib\Workspaces.ahk"
#Include "%A_ScriptDir%\..\lib\SystemControls.ahk"
#Include "%A_ScriptDir%\..\lib\Tray.ahk"

; Scripts seeds example .ahk files here; removed on every exit (ok, FAIL or ERROR),
; since OnExit runs for ExitApp(0), ExitApp(1) and the ExitApp(2) in SmokeOnError.
SmokeScriptsDir := A_Temp "\hf-smoke-scripts"
OnExit(SmokeCleanup)
SmokeCleanup(reason, code) {
    try DirDelete(SmokeScriptsDir, true)
    return 0  ; 0 = let the exit continue
}

; Any uncaught error: print it and exit 2 instead of showing a dialog.
OnError(SmokeOnError)
SmokeOnError(e, mode) {
    FileAppend("ERROR " e.Message " (" e.What " line " e.Line ")`n", "*")
    ExitApp(2)
    return 1
}

fails := 0
checks := 0

Assert(cond, msg) {
    global fails, checks
    checks++
    if !cond {
        fails++
        FileAppend("FAIL " msg "`n", "*")
    }
}

AssertEq(got, want, msg) {
    if (got != want)
        Assert(false, msg " got=[" got "] want=[" want "]")
    else
        Assert(true, msg)
}

dir := A_Temp "\hf-smoke-cfg"
DirCreate dir
HFConfig.Init(dir)
HFConfig.data["general.toasts"] := "0"

; ── config ──────────────────────────────────────────────────────────────
HFConfig.data["general.caps_tap_escape"] := "0"
Assert(!HFConfig.GetBool("general.caps_tap_escape", true), "bool 0")
HFConfig.data["general.caps_tap_escape"] := "off"
Assert(!HFConfig.GetBool("general.caps_tap_escape", true), "bool off")
HFConfig.data["general.caps_tap_escape"] := "yes"
Assert(HFConfig.GetBool("general.caps_tap_escape", false), "bool yes")
Assert(HFConfig.GetBool("general.no_such_key", true), "bool default on")
Assert(!HFConfig.GetBool("general.no_such_key", false), "bool default off")
HFConfig.data["general.keepalive_minutes"] := "nope"
AssertEq(HFConfig.GetInt("general.keepalive_minutes", 5), 5, "bad int falls back")
HFConfig.data["clipboard.max_items"] := "15"
AssertEq(HFConfig.GetInt("clipboard.max_items", 20), 15, "int 15")

; ── snap geometry ───────────────────────────────────────────────────────
m := FrameMarginsFromRects(100, 50, 800, 600, 107, 50, 893, 643)
AssertEq(m.l, 7, "margin left")
AssertEq(m.t, 0, "margin top")
AssertEq(m.r, 7, "margin right")
AssertEq(m.b, 7, "margin bottom")
rect := VisibleMoveRect(0, 0, 1000, 500, m)
AssertEq(rect.x, -7, "visible x")
AssertEq(rect.y, 0, "visible y")
AssertEq(rect.w, 1014, "visible w")
AssertEq(rect.h, 507, "visible h")
AssertEq(ClampFrameMargin(500), 0, "absurd margin dropped")
AssertEq(ClampFrameMargin(7), 7, "normal margin kept")

stack := []
loop 9
    UndoPush(stack, [A_Index])
AssertEq(stack.Length, 8, "undo cap")
AssertEq(stack[1][1], 2, "undo dropped oldest")
AssertEq(stack[8][1], 9, "undo kept newest")

; ── commands ────────────────────────────────────────────────────────────
Assert(CommandScore("", "Snap left") = 1, "empty query")
Assert(CommandScore("zzz", "Snap left") = 0, "miss")
Assert(CommandScore("snapl", "Snap left") > 0, "subsequence")
Assert(CommandScore("left", "Left third") > CommandScore("left", "Snap left"), "prefix wins")
ranked := RankCommands([["Bravo", "", (*) => 0], ["Alpha", "a", (*) => 0]], "")
AssertEq(ranked[1].row[1], "Bravo", "empty query keeps order")

labels := Map()
for row in HF_Catalog() {
    Assert(row.Length = 3, "catalog width " row[1])
    Assert(row[1] != "", "catalog label")
    Assert(!labels.Has(row[1]), "duplicate " row[1])
    labels[row[1]] := true
    Assert(HasMethod(row[3], "Call"), "callback " row[1])
}
Assert(labels.Has("Quarter top-left") && labels.Has("Quarter bottom-right"), "quarters split")
Assert(!labels.Has("Quarter TL / TR / BL / BR"), "combined quarter gone")
clipRank := RankCommands(HF_Catalog(), "clipboard")
Assert(clipRank.Length >= 1 && InStr(clipRank[1].row[1], "Clipboard") = 1, "clipboard ranks first")

sheet := CheatSheetText()
Assert(InStr(sheet, "Escape"), "sheet mentions Escape")
Assert(InStr(sheet, "LAN"), "sheet mentions LAN")
Assert(InStr(sheet, "top row"), "sheet labels the top row")
Assert(!InStr(sheet, "Win+I"), "sheet does not claim Win+I")
Assert(!InStr(sheet, "Win+W"), "sheet does not claim Win+W")

; ── quoting ─────────────────────────────────────────────────────────────
AssertEq(QuoteCmd("notepad.exe"), "notepad.exe", "simple exe")
AssertEq(QuoteCmd('C:\Program Files\Google\Chrome\Application\chrome.exe'), '"C:\Program Files\Google\Chrome\Application\chrome.exe"', "space path")
AssertEq(QuoteCmd('C:\Program Files\Google\Chrome\Application\chrome.exe --remote-debugging-port=9222'), '"C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222', "space path plus args")
AssertEq(QuoteCmd('wt -d "C:\work"'), 'wt -d "C:\work"', "wt args stay unquoted")
AssertEq(QuoteCmd('"C:\Program Files\chrome.exe"'), '"C:\Program Files\chrome.exe"', "already quoted")
AssertEq(ExeNameFromCommand('C:\Program Files\Google\Chrome\Application\chrome.exe --flag'), "chrome.exe", "exe name from path")
Assert(InStr(ExeNameFromCommand('"C:\Program Files\Google\Chrome\Application\chrome.exe"'), "chrome.exe"), "exe name from quoted path")
HFConfig.data["apps.editor_env_bootstrap"] := ""
nvimCmd := EditorLaunchCommand("nvim.exe")
Assert(InStr(nvimCmd, 'wt powershell.exe -NoLogo -NoExit -File "' A_Temp '\hf-nvim-launch.ps1"') = 1, "nvim launch via powershell file")
psLauncherPath := A_Temp "\\hf-nvim-launch.ps1"
psLauncherText := FileRead(psLauncherPath)
Assert(!InStr(psLauncherText, "$hfBootstrap ="), "nvim launcher has no bootstrap when unset")
HFConfig.data["apps.editor_env_bootstrap"] := 'call "%USERPROFILE%\dev\env.cmd"'
nvimCmd2 := EditorLaunchCommand("nvim.exe")
Assert(InStr(nvimCmd2, 'wt cmd.exe /d /k "' A_Temp '\hf-nvim-launch.cmd"') = 1, "nvim launch via cmd script with bootstrap set")
cmdLauncherPath := A_Temp "\\hf-nvim-launch.cmd"
cmdLauncherText := FileRead(cmdLauncherPath)
Assert(InStr(cmdLauncherText, 'call "%USERPROFILE%\dev\env.cmd"'), "nvim cmd launcher embeds bootstrap")
AssertEq(EditorLaunchCommand("notepad.exe"), "notepad.exe", "gui editor launch direct")

; ── encoding, uuid, snippets, newlines ──────────────────────────────────
sample := "héllo 日本語 " 
loop 80
    sample .= "A"
enc := Base64Encode(sample)
Assert(enc != "", "base64 produced")
Assert(!InStr(enc, "`n") && !InStr(enc, "`r"), "base64 has no line break")
AssertEq(Base64Decode(enc), sample, "base64 round trip")
AssertEq(NormalizeNewlines("a`r`nb`nc`rd"), "a`nb`nc`nd", "newlines")

guid := Buffer(16, 0)
bytes := [0x33, 0x22, 0x11, 0x00, 0x55, 0x44, 0x77, 0x66, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
for i, b in bytes
    NumPut("UChar", b, guid, i - 1)
AssertEq(FormatGuidBuffer(guid), "00112233-4455-6677-8899-AABBCCDDEEFF", "guid endian")
uuid := GenerateUUID()
Assert(RegExMatch(uuid, "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"), "live uuid " uuid)

HFConfig.data["snippets.date_format"] := "yyyy"
expanded := ResolveSnippetTokens("X\n{{date}}{{date:MM}} {{hostname}}")
Assert(InStr(expanded, "X`n"), "snippet newline")
Assert(!InStr(expanded, "{{date"), "date tokens consumed")
Assert(!InStr(expanded, "{{hostname}}"), "hostname token consumed")
Assert(InStr(expanded, A_ComputerName), "hostname value")
Assert(RegExMatch(ResolveSnippetTokens("{{uuid}}"), "^[0-9A-F]{8}-"), "uuid token")
EnvSet("HF_SMOKE_ENV", "ok")
AssertEq(ResolveSnippetTokens("{{env:HF_SMOKE_ENV}}"), "ok", "env token")
EnvSet("HF_SMOKE_ENV", "")
AssertEq(ResolveSnippetTokens("a{{env:HF_SMOKE_ENV}}b"), "ab", "empty env token")
EnvSet("HF_SMOKE_ENV", "{{env:PATH}}")
AssertEq(ResolveSnippetTokens("{{env:HF_SMOKE_ENV}}"), "{{env:PATH}}", "env value is literal")
AssertEq(ResolveSnippetTokens("{{env:HF_NO_SUCH_ENV_ZZ}}"), "{{env:HF_NO_SUCH_ENV_ZZ}}", "missing env stays")
AssertEq(ResolveSnippetTokens("{{env:NOT-A}}"), "{{env:NOT-A}}", "illegal env name stays")
Assert(ResolveSnippetTokens("{{env:PATH}}") != "{{env:PATH}}", "env PATH expands")

; ── backup json ─────────────────────────────────────────────────────────
cfg := "vscode=C:\Program Files\Code.exe`r`n,sig=Thanks,\nYour Name`nquote=`"hi`""
clipText := "line1`nline2"
blob := EncodeHyperForgeBackup(cfg, clipText)
decoded := DecodeHyperForgeBackup(blob)
Assert(IsObject(decoded), "v2 decode")
AssertEq(decoded.config, cfg, "v2 config")
AssertEq(decoded.clipboard, clipText, "v2 clipboard")
legacy := '{"version":1,"configIni":' _jsonStr(cfg) ',"clipboardHistory":' _jsonStr(clipText) '}'
decoded := DecodeHyperForgeBackup(legacy)
AssertEq(decoded.config, cfg, "v1 config")
AssertEq(decoded.clipboard, clipText, "v1 clipboard")
Assert(!IsObject(DecodeHyperForgeBackup("not json")), "reject junk")

; ── outbound guards (Hyper+W / Hyper+G) ────────────────────────────────
Assert(LooksLikeWhoisQuery("8.8.8.8"), "ipv4")
Assert(LooksLikeWhoisQuery(" 10.0.0.0/8 "), "ipv4 cidr trimmed")
Assert(LooksLikeWhoisQuery("0.0.0.0/0"), "ipv4 /0")
Assert(!LooksLikeWhoisQuery("10.0.0.0/33"), "ipv4 cidr range")
Assert(!LooksLikeWhoisQuery("999.1.1.1"), "ipv4 octet range")
Assert(!LooksLikeWhoisQuery("1.2.3"), "ipv4 too short")
Assert(LooksLikeWhoisQuery("2001:db8::1"), "ipv6")
Assert(LooksLikeWhoisQuery("2001:db8::/32"), "ipv6 cidr")
Assert(LooksLikeWhoisQuery("2001:0db8:0000:0000:0000:0000:0000:0001"), "ipv6 full")
Assert(LooksLikeWhoisQuery("::1"), "ipv6 loopback")
Assert(!LooksLikeWhoisQuery("::::"), "ipv6 bad colons")
Assert(!LooksLikeWhoisQuery("dead:beef"), "ipv6 too few groups")
Assert(!LooksLikeWhoisQuery("1::2::3"), "ipv6 two ::")
Assert(!LooksLikeWhoisQuery("2001:db8::12345"), "ipv6 group too long")
Assert(!LooksLikeWhoisQuery("2001:db8::/129"), "ipv6 cidr range")
Assert(LooksLikeWhoisQuery("AS12345"), "asn")
Assert(LooksLikeWhoisQuery("as15169"), "asn lowercase")
Assert(!LooksLikeWhoisQuery("AS"), "asn no digits")
Assert(!LooksLikeWhoisQuery("example.com"), "no domains")
Assert(!LooksLikeWhoisQuery("srv01.corp.local"), "no internal hostnames")
Assert(!LooksLikeWhoisQuery("P4ssw0rd.Summer"), "no dotted secrets")
Assert(!LooksLikeWhoisQuery("hunter2"), "plain word")
Assert(!LooksLikeWhoisQuery("10.0.0.1`nsecret"), "multi-line")
Assert(LooksLikeSearchQuery("ahk v2 map"), "search ok")
Assert(!LooksLikeSearchQuery("line1`r`nline2"), "search multi-line")
Assert(!LooksLikeSearchQuery(StrRepeatSmoke("x", 201)), "search too long")
Assert(!LooksLikeSearchQuery("   "), "search blank")
AssertEq(UrlEncode("a b/c?x=1&y"), "a%20b%2Fc%3Fx%3D1%26y", "urlencode ascii")
AssertEq(UrlEncode("é-_."), "%C3%A9-_.", "urlencode utf-8 + excepts")
; Confirm-prompt preview (the MsgBox itself isn't exercised here).
AssertEq(SendPreview("short query"), "short query", "preview short")
AssertEq(SendPreview("a`tb  c"), "a b c", "preview collapses whitespace")
AssertEq(StrLen(SendPreview(StrRepeatSmoke("x", 200))), 80, "preview capped at 80")
AssertEq(SubStr(SendPreview(StrRepeatSmoke("x", 200)), -1), "…", "preview ellipsis")
AssertEq(StrLen(SendPreview(StrRepeatSmoke("y", 80))), 80, "preview exact 80 untouched")

StrRepeatSmoke(s, n) {
    out := ""
    Loop n
        out .= s
    return out
}

; ── clipboard history ───────────────────────────────────────────────────
HF_ClipFile := A_Temp "\hf-smoke-clip-" A_TickCount ".dat"
; History is opt-in and memory-only by default; turn both on for the round trip.
HFConfig.data["clipboard.enabled"] := "1"
HFConfig.data["clipboard.persist"] := "1"
HF_ClipHistory := []
HFConfig.data["clipboard.max_items"] := "2"
ClipHistory_Record("a")
ClipHistory_Record("b")
ClipHistory_Record("c")
AssertEq(HF_ClipHistory.Length, 2, "unpinned cap")
AssertEq(HF_ClipHistory[1].text, "c", "newest first")
AssertEq(HF_ClipHistory[2].text, "b", "second")
for entry in HF_ClipHistory {
    if (entry.text = "b")
        entry.pinned := true
}
ClipHistory_Save()
ClipHistory_Record("d")
ClipHistory_Record("e")
pinnedKept := false
for entry in HF_ClipHistory {
    if (entry.text = "b" && entry.pinned)
        pinnedKept := true
}
Assert(pinnedKept, "pin survives trim")
HF_ClipHistory := []
ClipHistory_Load()
pinnedKept := false
for entry in HF_ClipHistory {
    if (entry.text = "b" && entry.pinned)
        pinnedKept := true
}
Assert(pinnedKept, "pin survives reload")
Assert(HF_ClipHistory.Length >= 1 && HF_ClipHistory[1].text = "e", "reload order")

long := "hello hyperforge clipboard history entry that is long enough to have wrapped"
wrapped := Base64Encode(long)
broken := "1`t" SubStr(wrapped, 1, 16) "`n" SubStr(wrapped, 17) "`n"
parsed := ClipHistory_Parse(broken)
Assert(parsed.Length = 1 && parsed[1].pinned && parsed[1].text = long, "wrapped base64 repaired")

try FileDelete(HF_ClipFile)
try FileDelete(HF_ClipFile ".tmp")

; BindHyper closes over each callback. Closures must keep their own values.
CaptureValue(value) {
    return (*) => value
}
heldA := CaptureValue("one")
heldB := CaptureValue("two")
AssertEq(heldA.Call(), "one", "closure keeps first value")
AssertEq(heldB.Call(), "two", "closure keeps second value")

; Register every chord once so a bad hotkey name fails here, not on a user's machine.
HFConfig.data["general.caps_to_hyper"] := "0"
HFConfig.data["general.wheel_accel"] := "0"
HFConfig.data["general.xbutton1_minimize"] := "0"
; Opt-in features: enable them so their hotkey names get checked too.
HFConfig.data["general.keepalive_enabled"] := "1"
; Scripts seeds example files into scripts_dir; keep that in temp, not tests\scripts.
HFConfig.data["paths.scripts_dir"] := SmokeScriptsDir
try Hotkey("^+Space", (*) => ToggleAlwaysOnTop())
catch as e
    Assert(false, "space hotkey " e.Message)
try BindHyper("Left", (*) => SnapActive(0, 0, 0.5, 1))
catch as e
    Assert(false, "left hotkey " e.Message " " e.What)
for step in [
    ["window", RegisterWindowHotkeys],
    ["apps", RegisterAppHotkeys],
    ["explorer", RegisterExplorerHotkeys],
    ["clipboard", RegisterClipboardHotkeys],
    ["network", RegisterNetworkHotkeys],
    ["mute", RegisterMuteHotkeys],
    ["snippets", RegisterSnippets],
    ["quick", RegisterQuickMenu],
    ["keepalive", RegisterKeepAlive],
    ["pin", RegisterPinHotkeys],
    ["catalog", RegisterCatalogHotkeys],
    ["scripts", RegisterScriptsHotkeys],
    ["workspaces", RegisterWorkspacesHotkeys],
    ["backup", RegisterBackupHotkeys]
] {
    try step[2].Call()
    catch as e
        Assert(false, "register " step[1] " " e.Message)
}

if fails {
    FileAppend(fails " failed of " checks "`n", "*")
    ExitApp(1)
}
FileAppend("ok " checks "`n", "*")
ExitApp(0)
