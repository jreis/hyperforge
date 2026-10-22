#Include "C:\Users\jreis\code\hyperforge\hyperforge-win\lib\HFBridge.ahk"

; Uppercase clipboard — HF_ClipboardGet / HF_ClipboardSet round-trip.
text := HF_ClipboardGet()
if (text != "") {
    HF_ClipboardSet(StrUpper(text))
    HF_Notify("Clipboard uppercased")
} else {
    HF_Notify("Clipboard is empty")
}
