<#
.SYNOPSIS
    Shared monitor API: DDC/CI brightness + gamma dimming.
    Dot-sourced by bright.ps1 (CLI) and bright_tray.ps1 (tray app).
#>

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

        [StructLayout(LayoutKind.Sequential)]
        public struct RAMP
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
            public ushort[] Red;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
            public ushort[] Green;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
            public ushort[] Blue;
        }

        [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
        public static extern IntPtr CreateDC(string lpszDriver, string lpszDevice, string lpszOutput, IntPtr devMode);

        [DllImport("gdi32.dll")]
        public static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        public static extern bool SetDeviceGammaRamp(IntPtr hdc, ref RAMP ramp);

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceKey;
        }

        public static bool ApplyGammaFactor(double factor)
        {
            var ramp = new RAMP();
            ramp.Red = new ushort[256];
            ramp.Green = new ushort[256];
            ramp.Blue = new ushort[256];
            for (int i = 0; i < 256; i++)
            {
                ushort v = (ushort)Math.Min(65535.0, Math.Round(65535.0 * factor * i / 255.0));
                ramp.Red[i] = v;
                ramp.Green[i] = v;
                ramp.Blue[i] = v;
            }

            bool ok = false;
            var adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            for (uint i = 0; EnumDisplayDevices(null, i, ref adapter, 0); i++)
            {
                if ((adapter.StateFlags & 1) == 0) continue; // not attached to desktop
                IntPtr hdc = CreateDC("DISPLAY", adapter.DeviceName, null, IntPtr.Zero);
                if (hdc != IntPtr.Zero)
                {
                    if (SetDeviceGammaRamp(hdc, ref ramp)) ok = true;
                    DeleteDC(hdc);
                }
                adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            }
            return ok;
        }
    }
}
'@
}

# ---- DDC/CI helpers -------------------------------------------------------

function Get-DDCMonitors {
    # Returns @{Handles=[IntPtr[]]; Names=[string[]]; Min=[int[]]; Max=[int[]]; Cur=[int[]]; Ok=[bool[]] }
    $raw = [DDCBrightness.MonitorApi]::Enumerate()
    $r = @{ Handles = @(); Names = @(); Min = @(); Max = @(); Cur = @(); Ok = @() }
    foreach ($m in $raw) {
        $min = [uint32]0; $cur = [uint32]0; $max = [uint32]0
        $ok = [DDCBrightness.MonitorApi]::GetMonitorBrightness($m.hPhysicalMonitor, [ref]$min, [ref]$cur, [ref]$max)
        $r.Handles += $m.hPhysicalMonitor
        $r.Names   += $m.szPhysicalMonitorDescription
        $r.Min     += [int]$min
        $r.Max     += [int]$max
        $r.Cur     += [int]$cur
        $r.Ok      += [bool]$ok
    }
    return $r
}

function Release-DDCMonitors {
    param($Monitors)
    foreach ($h in $Monitors.Handles) {
        [void][DDCBrightness.MonitorApi]::DestroyPhysicalMonitor($h)
    }
}

function ConvertTo-Pct {
    param([int]$Cur, [int]$Min, [int]$Max)
    if ($Max -le $Min) { return $Cur }
    return [int][math]::Round(100 * ($Cur - $Min) / ($Max - $Min))
}

function ConvertFrom-Pct {
    param([int]$Pct, [int]$Min, [int]$Max)
    if ($Max -le $Min) { return $Min }
    $v = $Min + [int][math]::Round(($Max - $Min) * $Pct / 100.0)
    return [math]::Max($Min, [math]::Min($Max, $v))
}

function Set-DDCBrightnessPct {
    # Sets every DDC-capable monitor to the given percentage. Returns $true if at least one succeeded.
    param($Monitors, [int]$Pct)
    $any = $false
    for ($i = 0; $i -lt $Monitors.Handles.Count; $i++) {
        if (-not $Monitors.Ok[$i]) { continue }
        $v = ConvertFrom-Pct $Pct $Monitors.Min[$i] $Monitors.Max[$i]
        if ([DDCBrightness.MonitorApi]::SetMonitorBrightness($Monitors.Handles[$i], [uint32]$v)) { $any = $true }
    }
    return $any
}

function Get-DDCBrightnessPct {
    # Returns the average percentage across DDC-capable monitors, or $null if none.
    param($Monitors)
    $vals = @()
    for ($i = 0; $i -lt $Monitors.Handles.Count; $i++) {
        if ($Monitors.Ok[$i]) { $vals += (ConvertTo-Pct $Monitors.Cur[$i] $Monitors.Min[$i] $Monitors.Max[$i]) }
    }
    if ($vals.Count -eq 0) { return $null }
    return [int](($vals | Measure-Object -Average).Average)
}

# ---- gamma dimming (HDR fallback) ----------------------------------------

function Set-GammaFactor {
    # $Factor: 1.0 = normal. Driver safety floor is ~0.5 (tested).
    param([double]$Factor)
    $Factor = [math]::Max(0.5, [math]::Min(1.0, $Factor))
    return [DDCBrightness.MonitorApi]::ApplyGammaFactor($Factor)
}
