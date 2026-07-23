; HyperForge for Windows
; AHK v2 Hyper Key automation — pairs with TouchCursor for Space-layer nav.
; No SpaceFN here by design.
;
; Run: right-click → Open with AutoHotkey v2, or add to Startup.
; Config: copy config.example.ini → config.ini

#Requires AutoHotkey v2.0+
#SingleInstance Force
#UseHook
#WinActivateForce
Persistent
A_MaxHotkeysPerInterval := 200
SendMode "Input"
SetTitleMatchMode 2

; --- Core libraries (order matters) ---
#Include "%A_ScriptDir%\lib\Config.ahk"
#Include "%A_ScriptDir%\lib\Utils.ahk"
#Include "%A_ScriptDir%\lib\CapsHyper.ahk"
#Include "%A_ScriptDir%\lib\Apps.ahk"
#Include "%A_ScriptDir%\lib\Explorer.ahk"
#Include "%A_ScriptDir%\lib\Clipboard.ahk"
#Include "%A_ScriptDir%\lib\Network.ahk"
#Include "%A_ScriptDir%\lib\Window.ahk"
#Include "%A_ScriptDir%\lib\Scroll.ahk"
#Include "%A_ScriptDir%\lib\Snippets.ahk"
#Include "%A_ScriptDir%\lib\QuickMenu.ahk"
#Include "%A_ScriptDir%\lib\KeepAlive.ahk"
#Include "%A_ScriptDir%\lib\Tray.ahk"

HFConfig.Init(A_ScriptDir)
InitTray()
InitCapsHyper()
RegisterAppHotkeys()
RegisterExplorerHotkeys()
RegisterClipboardHotkeys()
RegisterNetworkHotkeys()
RegisterWindowHotkeys()
InitScrollAccel()
RegisterSnippets()
RegisterQuickMenu()
RegisterKeepAlive()

; Optional private work module (gitignored) — Splunk/AD/etc. (*i = ignore if missing)
#Include "*i %A_ScriptDir%\work\work.ahk"

ShowMsg("HyperForge ready")