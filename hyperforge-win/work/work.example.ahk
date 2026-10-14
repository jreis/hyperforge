; work.example.ahk — template for private hotkeys (copy to work.ahk)
; This file is safe to commit. work.ahk is not.

; Example: override Hyper+S to open an internal dashboard
; Hotkey "#^!+s", (*) => Run(ChromeCmd() " https://example.internal/")

; Example: type a password from Windows Credential Manager (the entry must exist).
; Typed with SendText, never put on the clipboard, so it can't land in clipboard
; history, cloud clipboard or another app's clipboard monitor.
; Put the Credential Manager target name in place of the placeholder below.
; AHK v2.0 fat arrows can only be expressions, so use a named function for blocks.
; TypeWorkPassword(*) {
;     cred := CredRead("YOUR-CREDENTIAL-TARGET")   ; placeholder — not a secret
;     if cred
;         SendText cred.password
; }
; Hotkey "+F6", TypeWorkPassword
