#Requires AutoHotkey v2.0
; Laptop-style brightness hotkeys for desktop monitors (DDC/CI).
; Default: Ctrl+Alt+Up = brighter, Ctrl+Alt+Down = darker (step 10).
;
; Requirements:
;   1. AutoHotkey v2 installed (https://www.autohotkey.com)
;   2. bright.ps1 kept next to this file (or edit the path below)

ScriptDir := A_ScriptDir
BrightScript := ScriptDir "\bright.ps1"

AdjustBrightness(step) {
    action := (step >= 0) ? "inc" : "dec"
    RunWait('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" ' action ' ' Abs(step), , "Hide")
}

^!Up::AdjustBrightness(10)
^!Down::AdjustBrightness(-10)

; Optional: Ctrl+Alt+0..9 sets brightness to n*10 percent
^!0::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 0', , "Hide")
^!1::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 10', , "Hide")
^!2::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 20', , "Hide")
^!3::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 30', , "Hide")
^!4::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 40', , "Hide")
^!5::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 50', , "Hide")
^!6::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 60', , "Hide")
^!7::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 70', , "Hide")
^!8::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 80', , "Hide")
^!9::Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' BrightScript '" set 90', , "Hide")
