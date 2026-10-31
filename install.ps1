<#
.SYNOPSIS
    Installs the "bright" CLI and (optionally) the bright_tray tray app.

.DESCRIPTION
    - Copies bright.ps1 / bright.cmd / monitor_api.ps1 / bright_tray.* to
      %LOCALAPPDATA%\BrightnessDDC\bin and adds it to the user PATH
    - Optionally registers bright_tray (tray icon + slider + hotkeys) to
      start at login - no AutoHotkey needed
#>

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'src'
$destDir = Join-Path $env:LOCALAPPDATA 'BrightnessDDC'
$binDir = Join-Path $destDir 'bin'

New-Item -ItemType Directory -Force -Path $binDir | Out-Null
foreach ($f in 'monitor_api.ps1', 'bright.ps1', 'bright.cmd', 'bright_tray.ps1', 'bright_tray.cmd') {
    Copy-Item (Join-Path $src $f) $binDir -Force
}

# add to user PATH if missing
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
    Write-Host "Added to PATH: $binDir" -ForegroundColor Green
    Write-Host "Open a NEW terminal window for the change to take effect." -ForegroundColor Yellow
}

Write-Host ""
$ans = Read-Host "Install the bright_tray tray app (icon + slider + Ctrl+Alt hotkeys) at startup? (Y/n)"
if ($ans -ne 'n') {
    $shell = New-Object -ComObject WScript.Shell
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = $shell.CreateShortcut((Join-Path $startup 'bright_tray.lnk'))
    $lnk.TargetPath = (Join-Path $binDir 'bright_tray.cmd')
    $lnk.WorkingDirectory = $binDir
    $lnk.WindowStyle = 7  # minimized
    $lnk.Save()
    Write-Host "Tray app installed - starts at next login. To start it now:  $binDir\bright_tray.cmd" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Try:  bright   |   bright 40   |   bright +10   |   bright list   |   bright dim 60" -ForegroundColor Green
