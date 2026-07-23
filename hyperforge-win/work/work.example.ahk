; work.example.ahk — template for private hotkeys (copy to work.ahk)
; This file is safe to commit. work.ahk is not.

; Example: override Hyper+S to open an internal dashboard
; Hotkey "#^!+s", (*) => Run(ChromeCmd() " https://example.internal/")

; Example: credential paste (name must exist in Windows Credential Manager)
; Hotkey "+F6", (*) => {
;     account := Trim(A_Clipboard)
;     cred := CredRead(account)
;     if cred
;         A_Clipboard := cred.password
; }
