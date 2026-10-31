<#
.SYNOPSIS
    System-tray brightness app for desktop monitors. Laptop-like experience:
    tray icon + slider + global hotkeys, no AutoHotkey needed.

.DESCRIPTION
    - Tray icon (sun glyph, brightness-colored), tooltip shows current level
    - Right-click menu: slider, +/-10, presets, rescan, exit
    - Global hotkeys: Ctrl+Alt+Up/Down = +/-10, Ctrl+Alt+0..9 = 0%..90%
    - Remembers last brightness, reapplies it on start (DDC monitors only)
    - Falls back to gamma dimming (50-100%) when no DDC/CI monitor is present,
      so it also works with HDR on / on laptops

    Run hidden:  powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File bright_tray.ps1
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'monitor_api.ps1')

# ---- single instance ------------------------------------------------------
$mutex = New-Object System.Threading.Mutex($false, 'DesktopBrightnessTray')
if (-not $mutex.WaitOne(0)) {
    Write-Host 'bright_tray is already running.'
    exit 0
}

# ---- state ----------------------------------------------------------------
$stateDir  = Join-Path $env:LOCALAPPDATA 'BrightnessDDC'
$stateFile = Join-Path $stateDir 'state.json'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Save-State([int]$Pct) {
    try { "{""pct"":$Pct}" | Out-File -FilePath $stateFile -Encoding ascii -Force } catch { }
}
function Load-State {
    try {
        if (Test-Path $stateFile) {
            $j = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($j.pct -ge 0 -and $j.pct -le 100) { return [int]$j.pct }
        }
    } catch { }
    return 50
}

# ---- monitor state --------------------------------------------------------
$script:mon = $null

function Refresh-Monitors {
    try {
        if ($script:mon) { Release-DDCMonitors $script:mon }
        $script:mon = Get-DDCMonitors
    } catch { $script:mon = $null }
}

function Test-DDCAvailable {
    if (-not $script:mon) { return $false }
    foreach ($ok in $script:mon.Ok) { if ($ok) { return $true } }
    return $false
}

function Set-BrightnessPct([int]$Pct) {
    $Pct = [math]::Max(0, [math]::Min(100, $Pct))
    Refresh-Monitors
    if (Test-DDCAvailable) {
        [void](Set-DDCBrightnessPct $script:mon $Pct)
    }
    else {
        # no DDC/CI (HDR on, laptop panel): gamma fallback, floor 50%
        [void](Set-GammaFactor ($Pct / 100.0))
        if ($Pct -lt 50) { $Pct = 50 }
    }
    $script:currentPct = $Pct
    Save-State $Pct
    Update-Icon
}

# ---- hotkey window (C# subclass for WM_HOTKEY) ----------------------------
if (-not ('BrightTray.HotkeyForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms.dll, System.Drawing.dll -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BrightTray
{
    public class HotkeyForm : Form
    {
        public delegate void HotkeyHandler(int id);
        public event HotkeyHandler Hotkey;

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312 && Hotkey != null) Hotkey(m.WParam.ToInt32());
            base.WndProc(ref m);
        }

        protected override bool ShowWithoutActivation { get { return true; } }
    }
}
'@
}

$form = New-Object BrightTray.HotkeyForm
$form.ShowInTaskbar = $false
$form.WindowState = 'Minimized'
$form.Visible = $false

# hotkey ids: 1 = up(+10), 2 = down(-10), 3..12 = digits 0..9 (x10%)
$MOD_ALT = 1; $MOD_CONTROL = 2
[void][BrightTray.HotkeyForm]::RegisterHotKey($form.Handle, 1, ($MOD_CONTROL -bor $MOD_ALT), 0x26) # Up
[void][BrightTray.HotkeyForm]::RegisterHotKey($form.Handle, 2, ($MOD_CONTROL -bor $MOD_ALT), 0x28) # Down
for ($i = 0; $i -le 9; $i++) {
    [void][BrightTray.HotkeyForm]::RegisterHotKey($form.Handle, 3 + $i, ($MOD_CONTROL -bor $MOD_ALT), 0x30 + $i)
}

$form.Add_Hotkey({
    param($id)
    switch ($id) {
        1 { Set-BrightnessPct ($script:currentPct + 10) }
        2 { Set-BrightnessPct ($script:currentPct - 10) }
        default { if ($id -ge 3 -and $id -le 12) { Set-BrightnessPct (($id - 3) * 10) } }
    }
}.GetNewClosure())

# ---- tray icon ------------------------------------------------------------
function New-SunIcon([int]$Pct) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    # glow circle: dark amber -> bright yellow by level
    $t = [math]::Max(0.0, $Pct / 100.0)
    $r = [int](120 + 135 * $t); $gg = [int](90 + 120 * $t); $b = [int](20 + 40 * $t)
    $col = [System.Drawing.Color]::FromArgb(255, $r, $gg, $b)
    $brush = New-Object System.Drawing.SolidBrush $col
    $g.FillEllipse($brush, 5, 5, 22, 22)
    # rays
    $pen = New-Object System.Drawing.Pen ($col, 2.5)
    foreach ($a in 0..7) {
        $rad = $a * [math]::PI / 4
        $x1 = 16 + 14 * [math]::Cos($rad); $y1 = 16 + 14 * [math]::Sin($rad)
        $x2 = 16 + 19 * [math]::Cos($rad); $y2 = 16 + 19 * [math]::Sin($rad)
        if ($t -gt 0.15) { $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2) }
    }
    $brush.Dispose(); $pen.Dispose(); $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

function Update-Icon {
    if ($notify.Icon) { $notify.Icon.Dispose() }
    $notify.Icon = New-SunIcon $script:currentPct
    $mode = if (Test-DDCAvailable) { 'DDC/CI' } else { 'gamma (no DDC)' }
    $notify.Text = "Brightness: $($script:currentPct)%  [$mode]"
}

# ---- context menu ---------------------------------------------------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$track = New-Object System.Windows.Forms.TrackBar
$track.Minimum = 0; $track.Maximum = 100
$track.TickFrequency = 10; $track.Width = 180; $track.Height = 40
$track.Add_ValueChanged({ if ($track.Value -ne $script:currentPct) { Set-BrightnessPct $track.Value } }.GetNewClosure())
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripControlHost $track)) | Out-Null

$menu.Items.Add('-') | Out-Null

foreach ($pair in @(@('- 10', -10), @('+ 10', 10))) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $pair[0]
    $delta = $pair[1]
    $item.Add_Click({ Set-BrightnessPct ($script:currentPct + $delta) }.GetNewClosure())
    $menu.Items.Add($item) | Out-Null
}

$menu.Items.Add('-') | Out-Null

foreach ($p in 25, 50, 75, 100) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem ("$p%")
    $v = $p
    $item.Add_Click({ Set-BrightnessPct $v }.GetNewClosure())
    $menu.Items.Add($item) | Out-Null
}

$menu.Items.Add('-') | Out-Null

$refreshItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Rescan monitors'
$refreshItem.Add_Click({ Refresh-Monitors; Update-Icon }.GetNewClosure())
$menu.Items.Add($refreshItem) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
$exitItem.Add_Click({
    $notify.Visible = $false
    if ($notify.Icon) { $notify.Icon.Dispose() }
    for ($id = 1; $id -le 12; $id++) { [void][BrightTray.HotkeyForm]::UnregisterHotKey($form.Handle, $id) }
    if ($script:mon) { Release-DDCMonitors $script:mon }
    [System.Windows.Forms.Application]::Exit()
}.GetNewClosure())
$menu.Items.Add($exitItem) | Out-Null

$notify.ContextMenuStrip = $menu

# clicking the trackbar host shouldn't close the menu prematurely
$menu.AutoClose = $true

# ---- timers ---------------------------------------------------------------
# apply saved brightness shortly after start (skip gamma flash: DDC only)
$script:currentPct = Load-State
$startTimer = New-Object System.Windows.Forms.Timer
$startTimer.Interval = 3000
$startTimer.Add_Tick({
    $startTimer.Stop()
    Refresh-Monitors
    if (Test-DDCAvailable) { Set-BrightnessPct $script:currentPct }
    else { Update-Icon }
}.GetNewClosure())
$startTimer.Start()

# periodic refresh: tooltip + slider sync
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 60000
$pollTimer.Add_Tick({
    Refresh-Monitors
    Update-Icon
}.GetNewClosure())
$pollTimer.Start()

Refresh-Monitors
Update-Icon

# ---- run ------------------------------------------------------------------
[System.Windows.Forms.Application]::Run($form)
$mutex.ReleaseMutex()
