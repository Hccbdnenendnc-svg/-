<#
.SYNOPSIS
    Desktop monitor brightness control via DDC/CI, like a laptop's Fn keys.

.DESCRIPTION
    Uses the Windows High-Level Monitor Configuration API (dxva2.dll) to read
    and set the physical brightness of external desktop monitors through
    DDC/CI (VCP code 0x10). No drivers or extra software needed.

.EXAMPLE
    bright.ps1                    # show current brightness of every monitor
    bright.ps1 get 2              # show brightness of monitor #2
    bright.ps1 set 40             # set ALL monitors to 40%
    bright.ps1 set 40 2           # set monitor #2 to 40%
    bright.ps1 inc 10             # increase ALL monitors by 10
    bright.ps1 dec 10             # decrease ALL monitors by 10
    bright.ps1 list               # list detected monitors
    bright.ps1 dim 60             # software-dim the screen to 60% (works with HDR)
    bright.ps1 undim              # undo software dimming
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('get', 'set', 'inc', 'dec', 'list', 'dim', 'undim', '')]
    [string]$Action = '',

    [Parameter(Position = 1)]
    [int]$Value = 0,

    [Parameter(Position = 2)]
    [int]$Monitor = -1
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'monitor_api.ps1')

# ---- normalize arguments: allow "bright 40" / "bright +10" style calls ----
if (-not $Action -and $args.Count -gt 0) {
    $a = [string]$args[0]
    if ($a -match '^\+(\d+)$') { $Action = 'inc'; $Value = [int]$Matches[1] }
    elseif ($a -match '^-(\d+)$') { $Action = 'dec'; $Value = [int]$Matches[1] }
    elseif ($a -match '^\d+$') { $Action = 'set'; $Value = [int]$a }
}

try {
    $monitors = Get-DDCMonitors
}
catch {
    Write-Error "Failed to enumerate monitors: $_"
    exit 1
}

if ($monitors.Handles.Count -eq 0) {
    Write-Host 'No physical monitor found. This tool controls external monitors via DDC/CI only.' -ForegroundColor Yellow
    exit 1
}

# ---- action: list ----
if ($Action -eq 'list') {
    for ($i = 0; $i -lt $monitors.Handles.Count; $i++) {
        $ddc = if ($monitors.Ok[$i]) { 'DDC/CI OK' } else { 'no DDC/CI' }
        Write-Host ("[{0}] {1}  ({2})" -f ($i + 1), $monitors.Names[$i], $ddc)
    }
    Release-DDCMonitors $monitors
    exit 0
}

# ---- action: dim / undim (software dimming, works with HDR on) ----
if ($Action -eq 'dim' -or $Action -eq 'undim') {
    if ($Action -eq 'undim') { $factor = 1.0 }
    else {
        if ($Value -lt 1 -or $Value -gt 100) { $Value = 50 }
        $factor = $Value / 100.0
    }
    $ok = Set-GammaFactor $factor
    if ($ok) {
        Write-Host ("Software dimming applied: {0}%" -f [math]::Round($factor * 100)) -ForegroundColor Green
    }
    else {
        Write-Host 'Failed to apply gamma ramp (driver refused).' -ForegroundColor Red
    }
    Release-DDCMonitors $monitors
    exit 0
}

# ---- action: get (default) ----
if ($Action -eq '' -or $Action -eq 'get') {
    for ($i = 0; $i -lt $monitors.Handles.Count; $i++) {
        if ($Monitor -ge 0 -and ($i + 1) -ne $Monitor) { continue }
        if ($monitors.Ok[$i]) {
            $pct = ConvertTo-Pct $monitors.Cur[$i] $monitors.Min[$i] $monitors.Max[$i]
            Write-Host ("[{0}] {1}: {2}% ({3}/{4})" -f ($i + 1), $monitors.Names[$i], $pct, $monitors.Cur[$i], $monitors.Max[$i])
        }
        else {
            Write-Host ("[{0}] {1}: not supported (enable DDC/CI in the monitor OSD menu)" -f ($i + 1), $monitors.Names[$i]) -ForegroundColor Yellow
        }
    }
    Release-DDCMonitors $monitors
    exit 0
}

# ---- actions that change brightness ----
$anyOk = $false
for ($i = 0; $i -lt $monitors.Handles.Count; $i++) {
    if ($Monitor -ge 0 -and ($i + 1) -ne $Monitor) { continue }
    if (-not $monitors.Ok[$i]) {
        Write-Host ("[{0}] {1}: skipped - DDC/CI not available" -f ($i + 1), $monitors.Names[$i]) -ForegroundColor Yellow
        continue
    }
    $oldPct = ConvertTo-Pct $monitors.Cur[$i] $monitors.Min[$i] $monitors.Max[$i]
    $target = switch ($Action) {
        'set' { $Value }
        'inc' { [int]$monitors.Cur[$i] + $Value }
        'dec' { [int]$monitors.Cur[$i] - $Value }
    }
    $target = [math]::Max($monitors.Min[$i], [math]::Min($monitors.Max[$i], $target))
    $ok = [DDCBrightness.MonitorApi]::SetMonitorBrightness($monitors.Handles[$i], [uint32]$target)
    if ($ok) {
        $anyOk = $true
        $newPct = ConvertTo-Pct $target $monitors.Min[$i] $monitors.Max[$i]
        Write-Host ("[{0}] {1}: {2}% -> {3}%" -f ($i + 1), $monitors.Names[$i], $oldPct, $newPct) -ForegroundColor Green
    }
    else {
        Write-Host ("[{0}] {1}: failed to set brightness (error {2})" -f ($i + 1), $monitors.Names[$i],
            [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
    }
}
Release-DDCMonitors $monitors
if (-not $anyOk) { exit 1 }
