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
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('get', 'set', 'inc', 'dec', 'list', '')]
    [string]$Action = '',

    [Parameter(Position = 1)]
    [int]$Value = 0,

    [Parameter(Position = 2)]
    [int]$Monitor = -1
)

$ErrorActionPreference = 'Stop'

if (-not ('DDCBrightness.MonitorApi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DDCBrightness
{
    public class MonitorApi
    {
        public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT rect, IntPtr data);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct PHYSICAL_MONITOR
        {
            public IntPtr hPhysicalMonitor;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szPhysicalMonitorDescription;
        }

        [DllImport("user32.dll")]
        public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);

        [DllImport("dxva2.dll")]
        public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);

        [DllImport("dxva2.dll")]
        public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint size, [Out] PHYSICAL_MONITOR[] monitors);

        [DllImport("dxva2.dll")]
        public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint min, ref uint current, ref uint max);

        [DllImport("dxva2.dll")]
        public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint newValue);

        [DllImport("dxva2.dll")]
        public static extern bool DestroyPhysicalMonitor(IntPtr hMonitor);

        public static List<PHYSICAL_MONITOR> Enumerate()
        {
            var hMonitors = new List<IntPtr>();
            MonitorEnumProc proc = delegate(IntPtr hMon, IntPtr hdc, ref RECT rect, IntPtr data)
            {
                hMonitors.Add(hMon);
                return true;
            };
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, proc, IntPtr.Zero);

            var result = new List<PHYSICAL_MONITOR>();
            foreach (var hMon in hMonitors)
            {
                uint count = 0;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count)) continue;
                if (count == 0) continue;

                var arr = new PHYSICAL_MONITOR[count];
                if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) continue;
                foreach (var item in arr)
                {
                    var m = item;
                    if (m.szPhysicalMonitorDescription == null) m.szPhysicalMonitorDescription = "Unknown monitor";
                    result.Add(m);
                }
            }
            return result;
        }
    }
}
'@
}

function Get-Monitors {
    $monitors = [DDCBrightness.MonitorApi]::Enumerate()
    $list = @()
    for ($i = 0; $i -lt $monitors.Count; $i++) {
        $m = $monitors[$i]
        $info = [ordered]@{
            Index       = $i + 1
            Handle      = $m.hPhysicalMonitor
            Name        = $m.szPhysicalMonitorDescription
            Supported   = $false
            Current     = $null
            Min         = $null
            Max         = $null
        }
        $min = [uint32]0; $cur = [uint32]0; $max = [uint32]0
        if ([DDCBrightness.MonitorApi]::GetMonitorBrightness($m.hPhysicalMonitor, [ref]$min, [ref]$cur, [ref]$max)) {
            $info.Supported = $true
            $info.Min = $min; $info.Current = $cur; $info.Max = $max
        }
        $list += [pscustomobject]$info
    }
    return $list
}

function Show-Pct($cur, $min, $max) {
    if ($null -eq $cur) { return 'n/a' }
    if ($max -le $min) { return "$cur" }
    return '{0}%' -f [math]::Round(100 * ($cur - $min) / ($max - $min))
}

# ---- normalize arguments: allow "bright 40" / "bright +10" style calls ----
if (-not $Action -and $args.Count -gt 0) {
    $a = [string]$args[0]
    if ($a -match '^\+(\d+)$') { $Action = 'inc'; $Value = [int]$Matches[1] }
    elseif ($a -match '^-(\d+)$') { $Action = 'dec'; $Value = [int]$Matches[1] }
    elseif ($a -match '^\d+$') { $Action = 'set'; $Value = [int]$a }
}

try {
    $monitors = Get-Monitors
}
catch {
    Write-Error "Failed to enumerate monitors: $_"
    exit 1
}

if ($monitors.Count -eq 0) {
    Write-Host 'No physical monitor found. This tool controls external monitors via DDC/CI only.' -ForegroundColor Yellow
    exit 1
}

# ---- action: list ----
if ($Action -eq 'list') {
    foreach ($m in $monitors) {
        $ddc = if ($m.Supported) { 'DDC/CI OK' } else { 'no DDC/CI' }
        Write-Host ("[{0}] {1}  ({2})" -f $m.Index, $m.Name, $ddc)
    }
    exit 0
}

# ---- action: get (default) ----
if ($Action -eq '' -or $Action -eq 'get') {
    foreach ($m in $monitors) {
        if ($Monitor -ge 0 -and $m.Index -ne $Monitor) { continue }
        if ($m.Supported) {
            Write-Host ("[{0}] {1}: {2} ({3}/{4})" -f $m.Index, $m.Name,
                (Show-Pct $m.Current $m.Min $m.Max), $m.Current, $m.Max)
        }
        else {
            Write-Host ("[{0}] {1}: not supported (enable DDC/CI in the monitor OSD menu)" -f $m.Index, $m.Name) -ForegroundColor Yellow
        }
    }
    exit 0
}

# ---- actions that change brightness ----
foreach ($m in $monitors) {
    if ($Monitor -ge 0 -and $m.Index -ne $Monitor) { continue }
    if (-not $m.Supported) {
        Write-Host ("[{0}] {1}: skipped - DDC/CI not available" -f $m.Index, $m.Name) -ForegroundColor Yellow
        continue
    }
    $min = [int]$m.Min; $max = [int]$m.Max
    $target = switch ($Action) {
        'set' { $Value }
        'inc' { [int]$m.Current + $Value }
        'dec' { [int]$m.Current - $Value }
    }
    $target = [math]::Max($min, [math]::Min($max, $target))
    $ok = [DDCBrightness.MonitorApi]::SetMonitorBrightness($m.Handle, [uint32]$target)
    if ($ok) {
        Write-Host ("[{0}] {1}: {2} -> {3}" -f $m.Index, $m.Name,
            (Show-Pct $m.Current $m.Min $m.Max), (Show-Pct $target $m.Min $m.Max)) -ForegroundColor Green
    }
    else {
        Write-Host ("[{0}] {1}: failed to set brightness (error {2})" -f $m.Index, $m.Name,
            [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
    }
}

# release handles
$monitors | ForEach-Object { [void][DDCBrightness.MonitorApi]::DestroyPhysicalMonitor($_.Handle) }
