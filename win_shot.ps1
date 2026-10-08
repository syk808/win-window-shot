# Screenshot one window of a running process to a PNG, by matching its command line.
# Works for windows that have no title bar and no taskbar entry (overlays, widgets),
# where "pick a window by title" tools find nothing.
#
#   .\win_shot.ps1 -Match panel.py -Out panel.png
#   .\win_shot.ps1 -Match "--port 8080" -Name node* -Out server.png -Margin 8
param(
    [Parameter(Mandatory = $true)][string]$Match,   # substring of the process command line
    [Parameter(Mandatory = $true)][string]$Out,     # PNG path to write
    [string]$Name = '*',                            # process name filter, wildcards allowed (python*, node*)
    [int]$Margin = 0,                               # extra pixels around the window
    [int]$DelayMs = 400                             # wait after raising the window, before capturing
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class WinShot {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L, T, R, B; }
}
"@
# Without this, a scaled display reports logical sizes and the capture comes out cropped.
[WinShot]::SetProcessDPIAware() | Out-Null

$self = $PID
$procs = @(Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $self -and $_.Name -like $Name -and $_.CommandLine -like "*$Match*"
})
if (-not $procs) { Write-Error "no running process matches '$Match'"; exit 1 }
$ids = $procs.ProcessId

# A process can own several top-level windows (tooltips, hidden roots); take the largest visible one.
$script:hwnd = [IntPtr]::Zero; $script:area = 0; $script:rect = $null
$cb = [WinShot+EnumProc] {
    param($h, $l)
    $owner = 0
    [WinShot]::GetWindowThreadProcessId($h, [ref]$owner) | Out-Null
    if ($ids -contains $owner -and [WinShot]::IsWindowVisible($h)) {
        $r = New-Object WinShot+RECT
        [WinShot]::GetWindowRect($h, [ref]$r) | Out-Null
        $a = ($r.R - $r.L) * ($r.B - $r.T)
        if ($a -gt $script:area) { $script:area = $a; $script:rect = $r; $script:hwnd = $h }
    }
    return $true
}
[WinShot]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
if ($script:area -le 0) { Write-Error "process found, but it has no visible window"; exit 1 }

# Raise it above everything for the capture, then put it back the way it was.
$TOPMOST = [IntPtr](-1); $NOTOPMOST = [IntPtr](-2)
$FLAGS = 0x0013                                     # NOSIZE | NOMOVE | NOACTIVATE
$wasTopmost = ([WinShot]::GetWindowLong($script:hwnd, -20) -band 0x8) -ne 0
[WinShot]::SetWindowPos($script:hwnd, $TOPMOST, 0, 0, 0, 0, $FLAGS) | Out-Null
Start-Sleep -Milliseconds $DelayMs

$r = $script:rect
$w = $r.R - $r.L + 2 * $Margin; $h = $r.B - $r.T + 2 * $Margin
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
# .NET resolves relative paths against the process directory, not PowerShell's current location.
$full = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location).Path $Out }
$failed = $null
try {
    $g.CopyFromScreen($r.L - $Margin, $r.T - $Margin, 0, 0, $bmp.Size)
    $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
} catch {
    $failed = $_.Exception.Message
} finally {
    $g.Dispose(); $bmp.Dispose()
    if (-not $wasTopmost) { [WinShot]::SetWindowPos($script:hwnd, $NOTOPMOST, 0, 0, 0, 0, $FLAGS) | Out-Null }
}
if ($failed) { Write-Error "capture failed: $failed"; exit 1 }
"${w}x$h -> $full"
