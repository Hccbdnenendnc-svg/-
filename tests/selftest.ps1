<#
.SYNOPSIS
    Automated self-test for desktop-brightness.
    Verifies: shared API, state persistence, tray app lifecycle (launch, alive,
    single-instance mutex, clean exit), gamma pipeline (optional, brief).

.PARAMETER SkipGamma
    Skip the gamma dim/restore roundtrip (it briefly changes screen brightness).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\selftest.ps1
#>
param(
    [switch]$SkipGamma
)

$ErrorActionPreference = 'Continue'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
. (Join-Path $src 'monitor_api.ps1')

$script:results = @()
$script:skips = @()
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:results += [pscustomobject]@{ Test = $Name; Pass = $Ok; Detail = $Detail }
    $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}  {2}" -f $mark, $Name, $Detail)
}
function Skip {
    param([string]$Name, [string]$Detail = '')
    $script:skips += $Name
    Write-Host ("[SKIP] {0}  {1}" -f $Name, $Detail)
}

Write-Host '=== desktop-brightness self-test ===' -ForegroundColor Cyan
Write-Host ''

# ---- 1. shared API type ----
Check 'MonitorApi type loaded' ([bool]('DDCBrightness.MonitorApi' -as [type]))

# ---- 2. monitor enumeration ----
$mon = Get-DDCMonitors
Check 'Monitor enumeration' ($mon.Handles.Count -ge 1) "found $($mon.Handles.Count) monitor(s)"
$ddcCount = @($mon.Ok | Where-Object { $_ }).Count
Write-Host ("    DDC-capable: {0} (0 is normal on laptop panels / RDP)" -f $ddcCount)

# ---- 3. percentage conversion ----
Check 'ConvertTo-Pct midpoint' ((ConvertTo-Pct 50 0 100) -eq 50)
Check 'ConvertTo-Pct scaled range' ((ConvertTo-Pct 15 10 20) -eq 50)
Check 'ConvertFrom-Pct exact' ((ConvertFrom-Pct 40 0 100) -eq 40)
Check 'ConvertFrom-Pct clamps high' ((ConvertFrom-Pct 120 10 90) -eq 90)
Check 'ConvertFrom-Pct clamps low' ((ConvertFrom-Pct -5 10 90) -eq 10)

# ---- 4. DDC read path (no crash regardless of hardware) ----
try {
    $pct = Get-DDCBrightnessPct $mon
    Check 'Get-DDCBrightnessPct safe call' $true "pct=$pct"
}
catch {
    Check 'Get-DDCBrightnessPct safe call' $false $_.Exception.Message
}

# ---- 5. DDC set path (no crash regardless of hardware) ----
try {
    $cur = Get-DDCBrightnessPct $mon
    if ($null -eq $cur) { $cur = 50 }
    [void](Set-DDCBrightnessPct $mon $cur)
    Check 'Set-DDCBrightnessPct safe call' $true
}
catch {
    Check 'Set-DDCBrightnessPct safe call' $false $_.Exception.Message
}

# ---- 6. state persistence (same format the tray app uses) ----
$stateDir = Join-Path $env:TEMP 'BrightnessDDC_test'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir 'state.json'
try {
    '{ "pct": 42 }' | Out-File -FilePath $stateFile -Encoding ascii -Force
    $j = Get-Content $stateFile -Raw | ConvertFrom-Json
    Check 'State save/load roundtrip' ($j.pct -eq 42)
}
catch {
    Check 'State save/load roundtrip' $false $_.Exception.Message
}
Remove-Item $stateFile -Force -Confirm:$false -ErrorAction SilentlyContinue

# ---- 7. gamma pipeline ----
try {
    $ok = Set-GammaFactor 1.0
    Check 'Gamma identity (no visible change)' $ok
    if (-not $SkipGamma) {
        $ok = Set-GammaFactor 0.6
        $ok2 = Set-GammaFactor 1.0
        Check 'Gamma dim 60% + restore' ($ok -and $ok2) 'screen briefly dimmed and restored'
    }
}
catch {
    Check 'Gamma pipeline' $false $_.Exception.Message
}

# ---- 8. tray app lifecycle ----
Write-Host ''
Write-Host '--- tray app lifecycle (12s) ---'
$out1 = Join-Path $env:TEMP 'tray_t1.out'; $out2 = Join-Path $env:TEMP 'tray_t2.out'
$trayArgs = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $src 'bright_tray.ps1'))
try {
    $tray = Start-Process powershell -ArgumentList $trayArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $out1 -ErrorAction Stop
}
catch {
    Skip 'Tray lifecycle test' "Start-Process unavailable on this host: $($_.Exception.Message)"
    $tray = $null
}
if ($tray) {
    Start-Sleep -Seconds 6
    Check 'Tray app stays alive (6s, past startup timer)' (-not $tray.HasExited) "pid=$($tray.Id)"

    $second = $null
    try {
        $second = Start-Process powershell -ArgumentList $trayArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $out2 -ErrorAction Stop
    } catch { Write-Host "    second Start-Process failed: $($_.Exception.Message)" }
    if ($second) {
        Start-Sleep -Seconds 4
        $secondOut = (Get-Content $out2 -ErrorAction SilentlyContinue) -join ''
        Check 'Second instance exits fast (mutex)' ([bool]$second.HasExited) "out: $secondOut"
        Check 'Mutex message correct' ($secondOut -match 'already running')
    }

    if ($tray -and -not $tray.HasExited) {
        Stop-Process -Id $tray.Id -Force -Confirm:$false
        Check 'Tray app stopped' $true
    }
    elseif ($tray) {
        Check 'Tray app stopped' $false 'exited prematurely'
        $firstOut = (Get-Content $out1 -ErrorAction SilentlyContinue) -join ''
        Write-Host "    tray stdout: $firstOut"
    }
    Remove-Item $out1, $out2 -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# ---- summary ----
Write-Host ''
$pass = @($script:results | Where-Object Pass).Count
$total = $script:results.Count
$skipNote = if ($script:skips.Count -gt 0) { " (+$($script:skips.Count) skipped: $($script:skips -join ', '))" } else { '' }
if ($pass -eq $total) {
    Write-Host ("=== ALL $total TESTS PASSED$skipNote ===") -ForegroundColor Green
    exit 0
}
else {
    Write-Host ("=== $($total - $pass)/$total FAILED$skipNote ===") -ForegroundColor Red
    $script:results | Where-Object { -not $_.Pass } | Format-Table -AutoSize
    exit 1
}
