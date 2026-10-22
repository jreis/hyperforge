#Include "C:\Users\jreis\code\hyperforge\hyperforge-win\lib\HFBridge.ahk"

; New timestamped note — HF_LaunchApp + HF_Sleep + HF_PasteText.
stamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
HF_LaunchApp("notepad.exe")
HF_Sleep(400)
HF_PasteText("Note — " stamp "`n")
