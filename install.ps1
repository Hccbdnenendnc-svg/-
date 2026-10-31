<#
.SYNOPSIS
    Installs the "bright" command so it works from anywhere (Win+R, terminal, Run dialog).
#>

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'src'
$destDir = Join-Path $env:LOCALAPPDATA 'BrightnessDDC'
$binDir = Join-Path $destDir 'bin'

New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Copy-Item (Join-Path $src 'bright.ps1') $binDir -Force
Copy-Item (Join-Path $src 'bright.cmd') $binDir -Force

# add to user PATH if missing
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
    Write-Host "Added to PATH: $binDir" -ForegroundColor Green
    Write-Host "Open a NEW terminal window for the change to take effect." -ForegroundColor Yellow
}

# optional: register startup shortcut for hotkeys if AutoHotkey v2 exists
$ahk = 'bright_hotkeys.ahk'
$ahkSrc = Join-Path $src $ahk
if (Test-Path $ahkSrc) {
    Copy-Item $ahkSrc $destDir -Force
    Write-Host ""
    $ans = Read-Host "Install Ctrl+Alt+Up/Down brightness hotkeys at startup? (y/N)"
    if ($ans -eq 'y') {
        Copy-Item $ahkSrc $destDir -Force
        $shell = New-Object -ComObject WScript.Shell
        $startup = [Environment]::GetFolderPath('Startup')
        $lnk = $shell.CreateShortcut((Join-Path $startup 'Brightness Hotkeys.lnk'))
        $lnk.TargetPath = (Join-Path $destDir $ahk)
        $lnk.WorkingDirectory = $destDir
        $lnk.Save()
        Write-Host "Hotkeys installed. They start after next login (AutoHotkey v2 required)." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done. Try:  bright   |   bright 40   |   bright +10   |   bright -10   |   bright list" -ForegroundColor Green
