; Pin.ahk — region pin + OCR (macOS Hyper+P / Hyper+O parity)
; Snip via Win+Shift+S, then float the capture always-on-top.

global HF_Pins := []

RegisterPinHotkeys() {
    BindHyper("y", (*) => BeginRegionPin(), "send")
    BindHyper("q", (*) => BeginRegionOCR(), "send")
}

BeginRegionPin(*) {
    path := _snipToPng()
    if (path = "")
        return
    ShowPinWindow(path)
}

BeginRegionOCR(*) {
    path := _snipToPng()
    if (path = "")
        return
    text := OcrImageFile(path)
    try FileDelete(path)
    if (text = "") {
        ShowMsg("No text found")
        return
    }
    A_Clipboard := text
    preview := RegExReplace(text, "\s+", " ")
    if StrLen(preview) > 48
        preview := SubStr(preview, 1, 45) "…"
    ShowMsg("OCR → clipboard`n" preview)
}

_snipToPng() {
    ; Hyper is still holding Win/Ctrl/Alt/Shift. Snipping Tool listens for Win+Shift+S.
    ReleaseHyperModifiers()
    Sleep 40
    ShowMsg("Snip a region…  Esc cancels")
    previous := ""
    try previous := ClipboardAll()
    A_Clipboard := ""
    Send "#+s"
    if !ClipWait(45, 1) {
        _restoreClipboard(previous)
        RestoreHyperModifiers()
        ShowMsg("Pin cancelled")
        return ""
    }
    Sleep 200
    path := A_Temp "\hf-pin-" A_TickCount ".png"
    if !SaveClipboardImage(path) {
        _restoreClipboard(previous)
        RestoreHyperModifiers()
        ShowMsg("No image captured")
        return ""
    }
    ; The image lives in the pin window. Put the user's previous clipboard back.
    _restoreClipboard(previous)
    RestoreHyperModifiers()
    return path
}

_restoreClipboard(previous) {
    if (previous = "")
        return
    try A_Clipboard := previous
}

SaveClipboardImage(path) {
    ps1 := A_Temp "\hf-clip-save.ps1"
    try FileDelete(ps1)
    script :=
    (
        "Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not [Windows.Forms.Clipboard]::ContainsImage()) { exit 1 }
$img = [Windows.Forms.Clipboard]::GetImage()
$img.Save('" path "', [System.Drawing.Imaging.ImageFormat]::Png)
"
    )
    FileAppend(script, ps1)
    RunWait 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' ps1 '"', , "Hide"
    return FileExist(path)
}

CopyImageFile(path) {
    ps1 := A_Temp "\hf-clip-set.ps1"
    try FileDelete(ps1)
    FileAppend(
        "Add-Type -AssemblyName System.Windows.Forms`n"
        "Add-Type -AssemblyName System.Drawing`n"
        "$img = [System.Drawing.Image]::FromFile('" path "')`n"
        "[Windows.Forms.Clipboard]::SetImage($img)`n"
        "$img.Dispose()`n",
        ps1
    )
    RunWait 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' ps1 '"', , "Hide"
}

OcrImageFile(path) {
    ps1 := A_Temp "\hf-ocr.ps1"
    out := A_Temp "\hf-ocr-" A_TickCount ".txt"
    try FileDelete(ps1)
    try FileDelete(out)
    FileAppend(
        "$ErrorActionPreference = 'Stop'`n"
        "Add-Type -AssemblyName System.Runtime.WindowsRuntime`n"
        "$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]`n"
        "$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]`n"
        "$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.ReturnType.Name -eq 'Task``1' })[0]`n"
        "function Await($op) { $asTask.MakeGenericMethod($op.GetType().GenericTypeArguments).Invoke($null, @($op)).Wait(); $op.GetResults() }`n"
        "$bytes = [IO.File]::ReadAllBytes('" path "')`n"
        "$mem = New-Object IO.MemoryStream(,$bytes)`n"
        "$ras = [Windows.Storage.Streams.RandomAccessStreamReference]::CreateFromStream([IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($mem))`n"
        "$stream = Await ($ras.OpenReadAsync())`n"
        "$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream))`n"
        "$bitmap = Await ($decoder.GetSoftwareBitmapAsync())`n"
        "$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()`n"
        "if (-not $engine) { exit 2 }`n"
        "$result = Await ($engine.RecognizeAsync($bitmap))`n"
        "[IO.File]::WriteAllText('" out "', $result.Text)`n",
        ps1
    )
    RunWait 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' ps1 '"', , "Hide"
    if !FileExist(out)
        return ""
    text := Trim(FileRead(out))
    try FileDelete(out)
    return text
}

ShowPinWindow(imgPath) {
    global HF_Pins
    g := Gui("+AlwaysOnTop +Resize +ToolWindow", "HyperForge Pin")
    g.BackColor := "111111"
    g.OnEvent("Close", _pinClose)
    g.OnEvent("Escape", _pinClose)
    g.AddPicture("vPic w400 h-1", imgPath)
    bar := g.AddButton("w70", "Copy")
    bar.OnEvent("Click", (*) => (CopyImageFile(imgPath), ShowMsg("Copied pin")))
    g.AddButton("x+6 w70", "Save").OnEvent("Click", (*) => _pinSave(imgPath))
    g.AddButton("x+6 w70", "OCR").OnEvent("Click", _pinOcr.Bind(imgPath))
    g.AddButton("x+6 w70", "Close").OnEvent("Click", (*) => _pinClose(g))
    g.Show("AutoSize")
    HF_Pins.Push({ gui: g, path: imgPath })
}

_pinOcr(imgPath, *) {
    t := OcrImageFile(imgPath)
    if (t = "") {
        ShowMsg("No text found")
        return
    }
    A_Clipboard := t
    ShowMsg("OCR → clipboard")
}

_pinSave(imgPath) {
    pics := EnvGet("USERPROFILE") "\Pictures"
    dest := FileSelect("S16", pics "\pin-" FormatTime(, "yyyy-MM-dd_HH-mm-ss") ".png", "Save pin", "PNG (*.png)")
    if (dest = "")
        return
    try {
        FileCopy(imgPath, dest, true)
        ShowMsg("Saved " dest)
    } catch as e {
        ShowMsg("Save failed")
    }
}

_pinClose(g, *) {
    static busy := Map()
    if !IsObject(g)
        return
    id := 0
    try id := g.Hwnd
    if busy.Has(id)
        return
    busy[id] := true
    path := ""
    global HF_Pins
    kept := []
    for pin in HF_Pins {
        if (pin.gui = g)
            path := pin.path
        else
            kept.Push(pin)
    }
    HF_Pins := kept
    try g.Destroy()
    ; The picture control holds the file until the window is gone.
    if (path != "" && InStr(path, A_Temp) = 1)
        try FileDelete(path)
    busy.Delete(id)
}
