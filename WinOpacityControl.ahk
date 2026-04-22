#NoEnv
#SingleInstance Force
#Persistent
SetBatchLines, -1
SetWorkingDir, %A_ScriptDir%

; ---------------------------------------------------------------
;  CONFIG
; ---------------------------------------------------------------
global STEP_SMALL   := 5        ; Ctrl+Alt+Up/Down
global STEP_LARGE   := 25       ; Ctrl+Alt+PgUp/PgDn
global TRANS_MIN    := 50
global TRANS_MAX    := 255
global OSD_TIMEOUT  := 1200     ; ms before fade-out starts
global FADE_STEPS   := 15
global FADE_DELAY   := 10       ; ms per fade step
global WATCH_TIMER  := 500      ; ms between window-watch checks

; ---------------------------------------------------------------
;  GLOBALS
; ---------------------------------------------------------------
global settingsFile := A_ScriptDir "\opacity.ini"
global GuiHWND      := 0
global osdVisible   := false
global lastAdjTime  := 0        ; throttle WatchActiveWindow
global lastProcess  := ""       ; detect window switch

; ---------------------------------------------------------------
;  TRAY
; ---------------------------------------------------------------
Menu, Tray, Tip, WinOpacityControl
Menu, Tray, NoStandard
Menu, Tray, Add, Reset Active Window,  ResetWindow
Menu, Tray, Add, Reset All Windows,    ResetAll
Menu, Tray, Add,                       ; separator
Menu, Tray, Add, Exit,                 ExitApp

; ---------------------------------------------------------------
;  SETTINGS FILE
; ---------------------------------------------------------------
if (!FileExist(settingsFile))
    FileAppend,, %settingsFile%

; ---------------------------------------------------------------
;  OSD GUI
; ---------------------------------------------------------------
Gui, OSD: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HWNDGuiHWND
Gui, OSD: Color, 1E1E1E
Gui, OSD: Margin, 16, 14
Gui, OSD: Font, cFFFFFF s10 Bold, Segoe UI
Gui, OSD: Add, Text,     vLabel Center w260, Transparency 100`%
Gui, OSD: Font, s8 Normal
Gui, OSD: Add, Progress, vBar w260 h8 Range%TRANS_MIN%-%TRANS_MAX% c4CC2FF Background2A2A2A, 255
WinSet, Region, 0-0 w292 h68 R16-16, ahk_id %GuiHWND%
Gui, OSD: Show, Hide AutoSize
WinSet, Transparent, 0, ahk_id %GuiHWND%

; ---------------------------------------------------------------
;  WINDOW WATCHER  – only fires when the active window changes
; ---------------------------------------------------------------
SetTimer, WatchActiveWindow, %WATCH_TIMER%
return

; ---------------------------------------------------------------
;  HOTKEYS
; ---------------------------------------------------------------
^!Up::   AdjustTransparency( STEP_SMALL)
^!Down:: AdjustTransparency(-STEP_SMALL)
^!PgUp:: AdjustTransparency( STEP_LARGE)
^!PgDn:: AdjustTransparency(-STEP_LARGE)
^!Space:: ResetActiveWindow()    ; Ctrl+Alt+Space → fully opaque

; ---------------------------------------------------------------
;  CORE – adjust opacity of the currently active window
; ---------------------------------------------------------------
AdjustTransparency(step) {
    global lastAdjTime, settingsFile, TRANS_MIN, TRANS_MAX

    ; Don't accidentally adjust the OSD itself
    WinGet, activeHWND, ID, A
    if (activeHWND = GuiHWND)
        return

    WinGet, cur, Transparent, A
    trans := (cur = "" || cur = "OFF") ? TRANS_MAX : cur
    trans := Clamp(trans + step, TRANS_MIN, TRANS_MAX)

    WinSet, Transparent, %trans%, A

    ; Per-app persistence
    WinGet, proc, ProcessName, A
    IniWrite, %trans%, %settingsFile%, Apps, %proc%

    lastAdjTime := A_TickCount   ; suppress watcher for a moment
    ShowOSD(trans)
}

; ---------------------------------------------------------------
;  RESET helpers
; ---------------------------------------------------------------
ResetActiveWindow() {
    global settingsFile
    WinGet, proc, ProcessName, A
    WinSet, Transparent, OFF, A
    IniDelete, %settingsFile%, Apps, %proc%
    ShowOSD(255)
}

ResetWindow:                     ; tray menu target
    ResetActiveWindow()
return

ResetAll:
    WinGet, list, List
    Loop, %list% {
        hwnd := list%A_Index%
        WinSet, Transparent, OFF, ahk_id %hwnd%
    }
    FileDelete, %settingsFile%
    FileAppend,, %settingsFile%
    ToolTip, All windows reset to opaque.
    SetTimer, ClearTip, -2000
return

ClearTip:
    ToolTip
return

; ---------------------------------------------------------------
;  OSD DISPLAY
; ---------------------------------------------------------------
ShowOSD(val) {
    global osdVisible, GuiHWND, OSD_TIMEOUT

    pct := Round((val / 255) * 100)
    GuiControl, OSD:, Label, Transparency %pct%`%
    GuiControl, OSD:, Bar,   %val%

    ; Bottom-centre of working area (multi-monitor aware)
    SysGet, mon, MonitorWorkArea
    x := monLeft + ((monRight  - monLeft) // 2) - 146
    y := monBottom - 120

    Gui, OSD: Show, NoActivate x%x% y%y% AutoSize

    if (!osdVisible) {
        osdVisible := true
        FadeIn()
    }
    SetTimer, FadeOut, -%OSD_TIMEOUT%
}

; ---------------------------------------------------------------
;  FADE IN  (function)
; ---------------------------------------------------------------
FadeIn() {
    global GuiHWND, FADE_STEPS, FADE_DELAY
    Loop, %FADE_STEPS% {
        v := Min(A_Index * (230 // FADE_STEPS), 230)
        WinSet, Transparent, %v%, ahk_id %GuiHWND%
        Sleep, %FADE_DELAY%
    }
}

; ---------------------------------------------------------------
;  FADE OUT  (timer label)
; ---------------------------------------------------------------
FadeOut:
    global GuiHWND, osdVisible, FADE_STEPS, FADE_DELAY
    Loop, %FADE_STEPS% {
        v := Max(230 - A_Index * (230 // FADE_STEPS), 0)
        WinSet, Transparent, %v%, ahk_id %GuiHWND%
        Sleep, %FADE_DELAY%
    }
    Gui, OSD: Hide
    osdVisible := false
return

; ---------------------------------------------------------------
;  WINDOW WATCHER  – restores saved opacity on window switch
;  Skips if user just adjusted (within 1 s) to avoid fighting
; ---------------------------------------------------------------
WatchActiveWindow:
    global lastProcess, lastAdjTime, settingsFile

    WinGet, activeHWND, ID, A
    if (activeHWND = GuiHWND)   ; ignore the OSD window
        return

    WinGet, proc, ProcessName, A
    if (proc = lastProcess)     ; same window – nothing to do
        return
    lastProcess := proc

    ; Don't override if the user just manually adjusted
    if (A_TickCount - lastAdjTime < 1000)
        return

    IniRead, saved, %settingsFile%, Apps, %proc%, -1
    if (saved != -1)
        WinSet, Transparent, %saved%, A
return

; ---------------------------------------------------------------
;  UTILITY
; ---------------------------------------------------------------
Clamp(val, lo, hi) {
    return (val < lo) ? lo : (val > hi) ? hi : val
}

; ---------------------------------------------------------------
;  EXIT
; ---------------------------------------------------------------
ExitApp:
    ExitApp
