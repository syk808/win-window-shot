# win-window-shot

Screenshot one window of a running process to a PNG, from the command line. One PowerShell file, no install.

从命令行把某个正在运行的程序的窗口截成 PNG。只有一个 PowerShell 文件，不用安装。

## Why

Most "screenshot a window" tools pick the window by its title. Desktop widgets and overlays (Tkinter with `overrideredirect`, borderless Electron windows) have no title and no taskbar entry, so those tools find nothing. This script finds the window through the process that owns it instead: you give it a piece of the command line.

It was written to take README screenshots of a borderless desktop panel without cropping by hand.

## Usage

```powershell
.\win_shot.ps1 -Match panel.py -Out panel.png
.\win_shot.ps1 -Match "--port 8080" -Name node* -Out server.png -Margin 8
```

| Option | Meaning |
|---|---|
| `-Match` | Substring of the process command line. Required. |
| `-Out` | PNG path to write. Required. |
| `-Name` | Process name filter, wildcards allowed (`python*`, `node*`). Default `*`. |
| `-Margin` | Extra pixels captured around the window. Default 0. |
| `-DelayMs` | Wait after raising the window, before capturing. Default 400. |

If scripts are blocked on your machine: `powershell -ExecutionPolicy Bypass -File .\win_shot.ps1 -Match ... -Out ...`

## How it works

1. Finds processes whose command line contains `-Match` (via `Win32_Process`).
2. Enumerates top-level windows and keeps the largest visible one owned by those processes. A process often owns several (hidden roots, tooltips).
3. Raises that window above everything without activating it, captures its rectangle from the screen, then restores its previous always-on-top state.
4. Declares the process DPI-aware first, so a 125% or 150% display gives the full window rather than a cropped one.

## Limits

- It copies pixels from the screen, so the window must be on screen and not minimised. Anything drawn over it by the system (a notification toast) ends up in the picture.
- One window per run: the largest. A process with two equally important windows needs a narrower `-Match`.
- Windows only. Tested on Windows 11 with Windows PowerShell 5.1.

## License

MIT
