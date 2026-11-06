; Pin.ahk — region pin + OCR (macOS Hyper+P / Hyper+O parity)
; Snip via Win+Shift+S, then float the capture always-on-top.

global HF_Pins := []

RegisterPinHotkeys() {
    BindHyper("y", (*) => BeginRegionPin(), "send")
    BindHyper("q", (*) => BeginRegionOCR(), "send")
}

BeginRegionPin(*) {
    snip := _snipToPng()
    if !IsObject(snip)
        return
    ShowPinWindow(snip.path, snip.region)
}

BeginRegionOCR(*) {
    snip := _snipToPng()
    if !IsObject(snip)
        return
    path := snip.path
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
    ; Hyper may still be holding modifiers; release before selection.
    ReleaseHyperModifiers()
    Sleep 40
    region := _selectScreenRegion()
    RestoreHyperModifiers()
    if !IsObject(region) {
        ShowMsg("Pin cancelled")
        return ""
    }
    path := A_Temp "\hf-pin-" A_TickCount ".png"
    if !SaveScreenRegionImage(path, region.x, region.y, region.w, region.h) {
        ShowMsg("No image captured")
        return ""
    }
    return { path: path, region: region }
}

SaveScreenRegionImage(path, x, y, w, h) {
    ps1 := A_Temp "\hf-clip-save.ps1"
    try FileDelete(ps1)
    script := "Add-Type -AssemblyName System.Drawing`n"
        . "Add-Type @'`n"
        . "using System;`n"
        . "using System.Runtime.InteropServices;`n"
        . "public static class HF_Dpi {`n"
        . '    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);`n'
        . "}`n"
        . "'@`n"
        . "[HF_Dpi]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null`n"
        . "$bmp = New-Object System.Drawing.Bitmap(" w ", " h ")`n"
        . "$g = [System.Drawing.Graphics]::FromImage($bmp)`n"
        . "$g.CopyFromScreen(" x ", " y ", 0, 0, $bmp.Size)`n"
        . "$bmp.Save('" path "', [System.Drawing.Imaging.ImageFormat]::Png)`n"
        . "$g.Dispose()`n"
        . "$bmp.Dispose()`n"
    FileAppend(script, ps1)
    RunWait 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' ps1 '"', , "Hide"
    return FileExist(path)
}

_selectScreenRegion() {
    dpiCtx := 0
    try dpiCtx := DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

    vx := DllCall("GetSystemMetrics", "int", 76, "int")
    vy := DllCall("GetSystemMetrics", "int", 77, "int")
    vw := DllCall("GetSystemMetrics", "int", 78, "int")
    vh := DllCall("GetSystemMetrics", "int", 79, "int")

    shade := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    topBorder := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    rightBorder := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    bottomBorder := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    leftBorder := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
    cancelled := false
    x1 := y1 := x2 := y2 := 0

    hintMon := _cursorMonitor()

    try {
        shade.BackColor := "000000"
        shade.Show("NA x" vx " y" vy " w" vw " h" vh)
        WinSetTransparent(30, shade)

        for g in [topBorder, rightBorder, bottomBorder, leftBorder]
            g.BackColor := "4aa3ff"

        ShowMsg("Drag a region…  Esc cancels", hintMon)
        while !GetKeyState("LButton", "P") {
            if GetKeyState("Escape", "P") {
                cancelled := true
                break
            }
            Sleep 10
        }
        if !cancelled {
            _getPhysicalMousePos(&x1, &y1)
            x2 := x1
            y2 := y1

            while true {
                if GetKeyState("Escape", "P") {
                    cancelled := true
                    break
                }
                _getPhysicalMousePos(&x2, &y2)
                x := Min(x1, x2)
                y := Min(y1, y2)
                w := Abs(x2 - x1)
                h := Abs(y2 - y1)
                if (w > 1 && h > 1)
                    _showSelectionBorder(topBorder, rightBorder, bottomBorder, leftBorder, x, y, w, h)
                if !GetKeyState("LButton", "P")
                    break
                Sleep 10
            }
        }
    } finally {
        try topBorder.Destroy()
        try rightBorder.Destroy()
        try bottomBorder.Destroy()
        try leftBorder.Destroy()
        try shade.Destroy()
        if (dpiCtx)
            try DllCall("SetThreadDpiAwarenessContext", "ptr", dpiCtx, "ptr")
        _ensureCursorVisible()
    }

    if cancelled
        return ""
    x := Min(x1, x2)
    y := Min(y1, y2)
    w := Abs(x2 - x1)
    h := Abs(y2 - y1)
    if (w < 2 || h < 2)
        return ""
    return { x: x, y: y, w: w, h: h }
}

_ensureCursorVisible() {
    DllCall("ClipCursor", "ptr", 0)
    hCur := DllCall("LoadCursor", "ptr", 0, "ptr", 32512, "ptr")
    if (hCur)
        DllCall("SetCursor", "ptr", hCur, "ptr")
    tries := 0
    while (!_isCursorVisible() && tries < 64) {
        DllCall("ShowCursor", "int", 1)
        tries += 1
    }
    DllCall("SystemParametersInfo", "uint", 0x57, "uint", 0, "ptr", 0, "uint", 0)
    _getPhysicalMousePos(&mx, &my)
    DllCall("SetCursorPos", "int", mx, "int", my)
}

_isCursorVisible() {
    ci := Buffer(A_PtrSize = 8 ? 24 : 20, 0)
    NumPut("uint", ci.Size, ci, 0)
    if !DllCall("GetCursorInfo", "ptr", ci)
        return true
    return (NumGet(ci, 4, "uint") & 0x1) != 0
}

_cursorMonitor() {
    mon := MonitorGetPrimary()
    _getPhysicalMousePos(&cx, &cy)
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (cx >= ml && cx < mr && cy >= mt && cy < mb)
            return A_Index
    }
    return mon
}

_getPhysicalMousePos(&x, &y) {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    x := NumGet(pt, 0, "int")
    y := NumGet(pt, 4, "int")
}

_showSelectionBorder(topBorder, rightBorder, bottomBorder, leftBorder, x, y, w, h) {
    t := 2
    topBorder.Show("NA x" x " y" y " w" w " h" t)
    rightBorder.Show("NA x" (x + w - t) " y" y " w" t " h" h)
    bottomBorder.Show("NA x" x " y" (y + h - t) " w" w " h" t)
    leftBorder.Show("NA x" x " y" y " w" t " h" h)
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

ShowPinWindow(imgPath, region := "") {
    global HF_Pins
    static hooksInstalled := false
    if !hooksInstalled {
        OnMessage(0x0201, _pinBeginDrag)
        OnMessage(0x007B, _pinContextMenuMessage)
        hooksInstalled := true
    }
    g := Gui("+AlwaysOnTop -Caption", "HyperForge Pin")
    g.MarginX := 3
    g.MarginY := 3
    g.BackColor := "2f7de1"
    g.OnEvent("Close", _pinClose)
    g.OnEvent("Escape", _pinClose)
    picOpts := "vPic w400 h-1"
    if IsObject(region) && region.HasProp("w") && region.HasProp("h") && region.w > 1 && region.h > 1
        picOpts := "vPic w" region.w " h" region.h
    pic := g.AddPicture(picOpts, imgPath)
    opts := "AutoSize"
    if IsObject(region)
        opts .= " x" region.x " y" region.y
    g.Show(opts)
    HF_Pins.Push({ gui: g, path: imgPath, picHwnd: pic.Hwnd })
}

_pinBeginDrag(wParam, lParam, msg, hwnd) {
    global HF_Pins
    for pin in HF_Pins {
        if (hwnd != pin.gui.Hwnd && hwnd != pin.picHwnd)
            continue
        DllCall("ReleaseCapture")
        PostMessage(0x00A1, 2,,, "ahk_id " pin.gui.Hwnd)
        return 0
    }
}

_pinContextMenuMessage(wParam, lParam, msg, hwnd) {
    global HF_Pins
    for pin in HF_Pins {
        if (wParam != pin.gui.Hwnd && wParam != pin.picHwnd)
            continue
        MouseGetPos(&x, &y)
        _showPinContextMenu(pin, x, y)
        return 0
    }
}

_showPinContextMenu(pin, x, y) {
    m := Menu()
    m.Add("Copy", (*) => (CopyImageFile(pin.path), ShowMsg("Copied pin")))
    m.Add("Save", (*) => _pinSave(pin.path))
    m.Add("OCR", _pinOcr.Bind(pin.path))
    m.Add()
    m.Add("Close", (*) => _pinClose(pin.gui))
    m.Show(x, y)
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
