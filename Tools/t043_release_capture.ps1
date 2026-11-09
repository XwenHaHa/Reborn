# T043：发行包启动取证（GUI exe，自建隐藏桌面）。只读启动 + 截图，不写真实 user://。
# 用法：powershell -ExecutionPolicy Bypass -File E:\Reborn\Tools\t043_release_capture.ps1
# 产物：Art/Probes/t043_release_menu.png、t043_release_hud.png、Art/Probes/.capture_logs/t043_release_*.log
# 判定：visible_hits=0、console_windows=0、两帧非黑（non_black_ratio>0.05）。
param(
    [string]$Exe = 'E:\Reborn\Builds\P0-Win64\Reborn.exe',
    [int]$TimeoutSec = 90,
    [string]$LogDir = 'E:\Reborn\Art\Probes\.capture_logs',
    [string]$PngRoot = 'E:\Reborn\Art\Probes'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (-not (Test-Path $PngRoot)) { New-Item -ItemType Directory -Force -Path $PngRoot | Out-Null }
$logPath = Join-Path $LogDir "t043_release_$stamp.log"
$menuPng = Join-Path $PngRoot 't043_release_menu.png'
$hudPng = Join-Path $PngRoot 't043_release_hud.png'
# 隔离 user://：子进程继承临时 APPDATA，绝不碰真实存档。
$tempAppData = 'E:\Reborn\Builds\P0-Win64\_userdata_probe'
if (Test-Path $tempAppData) { Remove-Item $tempAppData -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tempAppData | Out-Null
$env:APPDATA = $tempAppData

Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class RebornReleaseProbe {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumDesktopWindows(IntPtr d, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateDesktopW(string name, string dev, IntPtr dm, uint flags, uint access, IntPtr sa);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr d);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessW(IntPtr app, IntPtr cmd, IntPtr pa, IntPtr ta, bool inherit,
        uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO { public uint cb; public IntPtr a,b,c; public uint x,y,xs,ys,xc,yc,fill,flags;
        public ushort show,cb2; public IntPtr r2, hin, hout, herr; }
    [StructLayout(LayoutKind.Sequential)] public struct PROCESS_INFORMATION { public IntPtr hp, ht; public uint pid, tid; }
    public static IntPtr Desk = IntPtr.Zero;
    public static IntPtr Proc = IntPtr.Zero;

    public static uint Launch(string exe, string desktopName) {
        Desk = CreateDesktopW(desktopName, null, IntPtr.Zero, 0, 0x10000000u, IntPtr.Zero);
        if (Desk == IntPtr.Zero) throw new Exception("CreateDesktop failed " + Marshal.GetLastWin32Error());
        STARTUPINFO si = new STARTUPINFO();
        si.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
        si.flags = 0;
        IntPtr pd = Marshal.StringToHGlobalUni("winsta0\\" + desktopName);
        si.b = pd;
        PROCESS_INFORMATION pi;
        IntPtr cmd = Marshal.StringToHGlobalUni("\"" + exe + "\"");
        bool ok;
        try { ok = CreateProcessW(IntPtr.Zero, cmd, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, null, ref si, out pi); }
        finally { Marshal.FreeHGlobal(cmd); Marshal.FreeHGlobal(pd); }
        if (!ok) throw new Exception("CreateProcess failed " + Marshal.GetLastWin32Error());
        CloseHandle(pi.ht); Proc = pi.hp;
        return pi.pid;
    }

    public static IntPtr FindMain(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumDesktopWindows(Desk, delegate(IntPtr h, IntPtr l) {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp == pid) { RECT r; GetWindowRect(h, out r); if ((r.R-r.L) > 200 && (r.B-r.T) > 200) found = h; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string WindowInfo(uint pid, bool userDesktop) {
        var sb = new StringBuilder();
        int total=0, visible=0, console=0;
        EnumProc cb = delegate(IntPtr h, IntPtr l) {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (pid != 0 && wp != pid) return true;
            total++;
            var cls = new StringBuilder(256); GetClassNameW(h, cls, 256);
            string c = cls.ToString();
            if (c == "ConsoleWindowClass" || c.Contains("CASCADIA") || c.Contains("Console")) console++;
            if (IsWindowVisible(h)) visible++;
            RECT r; GetWindowRect(h, out r);
            sb.Append("WIN|" + (userDesktop ? "user" : "desk") + "|" + c + "|visible=" + IsWindowVisible(h) +
                "|rect=" + r.L + "," + r.T + "," + r.R + "," + r.B + ";");
            return true;
        };
        if (userDesktop) EnumWindows(cb, IntPtr.Zero); else EnumDesktopWindows(Desk, cb, IntPtr.Zero);
        return "STAT|" + (userDesktop ? "user" : "desk") + "|total=" + total + "|visible=" + visible +
            "|console=" + console + "|" + sb.ToString();
    }

    public static bool Grab(IntPtr h, string path, out double nonBlack) {
        RECT r; GetWindowRect(h, out r);
        int w = Math.Max(1, r.R-r.L), hgt = Math.Max(1, r.B-r.T);
        using (var bmp = new Bitmap(w, hgt)) {
            using (var g = Graphics.FromImage(bmp)) {
                IntPtr hdc = g.GetHdc();
                PrintWindow(h, hdc, 2);
                g.ReleaseHdc(hdc);
            }
            int hit=0, total=0;
            for (int y=0; y<hgt; y+=Math.Max(1,hgt/40))
                for (int x=0; x<w; x+=Math.Max(1,w/40)) {
                    Color c = bmp.GetPixel(x,y);
                    total++;
                    if (c.R + c.G + c.B > 30) hit++;
                }
            nonBlack = total > 0 ? (double)hit/total : 0.0;
            bmp.Save(path, ImageFormat.Png);
        }
        return true;
    }

    public static void Key(IntPtr h, int vk) {
        PostMessageW(h, 0x0100, (IntPtr)vk, IntPtr.Zero);
        Thread.Sleep(80);
        PostMessageW(h, 0x0101, (IntPtr)vk, IntPtr.Zero);
    }

    public static bool Alive() { return WaitForSingleObject(Proc, 0) != 0; }
    public static void Kill() { if (Proc != IntPtr.Zero) { TerminateProcess(Proc, 0); CloseHandle(Proc); Proc = IntPtr.Zero; }
        if (Desk != IntPtr.Zero) { CloseDesktop(Desk); Desk = IntPtr.Zero; } }
}
"@

$pid2 = [RebornReleaseProbe]::Launch($Exe, 'RebornReleaseProbe')
Write-Host "RELEASE|pid=$pid2|exe=$Exe|desktop=RebornReleaseProbe"
$hwnd = [IntPtr]::Zero
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline -and $hwnd -eq [IntPtr]::Zero) {
    Start-Sleep -Milliseconds 300
    $hwnd = [RebornReleaseProbe]::FindMain($pid2)
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "RELEASE|alive=$([RebornReleaseProbe]::Alive())|desk_all=$([RebornReleaseProbe]::WindowInfo(0, $false))"
    Write-Host "RELEASE|FAIL|main_window_not_found"
    [RebornReleaseProbe]::Kill(); exit 1
}
Start-Sleep -Seconds 4
$ratio1 = 0.0
$ok1 = [RebornReleaseProbe]::Grab($hwnd, $menuPng, [ref]$ratio1)
Write-Host ("RELEASE|frame=menu|png={0}|non_black_ratio={1:F3}" -f $menuPng, $ratio1)
# 无存档首启菜单：Tab 聚焦唯一按钮（新游戏），Enter 进入存活。
[RebornReleaseProbe]::Key($hwnd, 0x09) # VK_TAB
Start-Sleep -Milliseconds 600
[RebornReleaseProbe]::Key($hwnd, 0x0D) # VK_RETURN
Start-Sleep -Seconds 4
if (-not [RebornReleaseProbe]::Alive()) {
    Write-Host "RELEASE|FAIL|process_exited_after_enter"
    [RebornReleaseProbe]::Kill(); exit 1
}
$ratio2 = 0.0
$ok2 = [RebornReleaseProbe]::Grab($hwnd, $hudPng, [ref]$ratio2)
Write-Host ("RELEASE|frame=hud|png={0}|non_black_ratio={1:F3}" -f $hudPng, $ratio2)
$user = [RebornReleaseProbe]::WindowInfo($pid2, $true)
$desk = [RebornReleaseProbe]::WindowInfo($pid2, $false)
$userVisible = [regex]::Match($user, 'visible=(\d+)').Groups[1].Value
$consoleDesk = [regex]::Match($desk, 'console=(\d+)').Groups[1].Value
$consoleUser = [regex]::Match($user, 'console=(\d+)').Groups[1].Value
Write-Host "RELEASE|$user"
Write-Host "RELEASE|$desk"
Write-Host "RELEASE|visible_hits=$userVisible|console_windows=$([int]$consoleUser + [int]$consoleDesk)|windows_seen=$([regex]::Match($desk, 'total=(\d+)').Groups[1].Value)"
$pass = ([double]$userVisible -eq 0) -and (([int]$consoleUser + [int]$consoleDesk) -eq 0) -and ($ratio1 -gt 0.05) -and ($ratio2 -gt 0.05)
Write-Host ("RELEASE|RESULT|{0}|menu_ratio={1:F3}|hud_ratio={2:F3}" -f ($(if($pass){'PASS'}else{'FAIL'}), $ratio1, $ratio2))
[RebornReleaseProbe]::Key($hwnd, 0x1B) # VK_ESCAPE -> 暂停
Start-Sleep -Milliseconds 500
[RebornReleaseProbe]::Kill()
Remove-Item Env:\APPDATA -ErrorAction SilentlyContinue
$env:APPDATA = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').AppData
if ($pass) { exit 0 } else { exit 1 }
