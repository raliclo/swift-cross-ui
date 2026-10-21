#if os(Linux)
    import CGtk
    import Foundation
    import Gtk

    /// `.floating` under WSL, done on the Windows side of the window.
    ///
    /// WSLg draws every Linux window as a Windows window of its own, and the
    /// Linux side cannot raise it: WSLg's X window manager (Weston WM)
    /// advertises no `_NET_WM_STATE_ABOVE` -- its `_NET_SUPPORTED` lists
    /// MOVERESIZE, STATE, FULLSCREEN, MAXIMIZED_VERT/HORZ, ACTIVE_WINDOW and
    /// FRAME_EXTENTS only (xprop, 2026-10-21) -- and Wayland lets no client
    /// raise itself. So, as the user chose, the backend asks Windows: through
    /// WSL interop it runs powershell.exe, which finds the Windows window by its
    /// title -- WSLg titles it "<GTK title> (<distro>)" -- and calls
    /// `SetWindowPos(HWND_TOPMOST)` (or `HWND_NOTOPMOST` to undo it). The call
    /// is not waited for: PowerShell takes about a second to start, and the
    /// script retries for three seconds because the Windows window appears a
    /// little after GTK maps its own.
    ///
    /// WSL 下的 `.floating`,在視窗的 Windows 那一側完成。WSLg 把每個 Linux 視窗都畫成一個獨立的 Windows 視窗，而 Linux
    /// 這一側無法把它抬高:WSLg 的 X 視窗管理員(Weston WM)沒有宣告 `_NET_WM_STATE_ABOVE`——它的 `_NET_SUPPORTED` 只有
    /// MOVERESIZE、STATE、FULLSCREEN、MAXIMIZED_VERT/HORZ、ACTIVE_WINDOW 與 FRAME_EXTENTS(xprop,2026-10-21)——而 Wayland
    /// 不讓任何 client 自行置頂。因此依使用者的選擇，由 backend 請 Windows 來做：透過 WSL 互通執行 powershell.exe,以標題
    /// 找到 Windows 視窗(WSLg 把它命名為「<GTK 標題> (<發行版>)」),再呼叫 `SetWindowPos(HWND_TOPMOST)`(取消時用
    /// `HWND_NOTOPMOST`)。不等待這個呼叫:PowerShell 啟動約需一秒，而且腳本會重試三秒，因為 Windows 視窗比 GTK 自己的
    /// 視窗稍晚出現。
    enum GtkWSLTopmost {
        private static let powershell = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

        /// Whether this process runs under WSL with Windows' PowerShell reachable.
        /// 本行程是否在 WSL 下執行，且能用到 Windows 的 PowerShell。
        static let isAvailable: Bool =
            (ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] != nil
                || FileManager.default.fileExists(atPath: "/proc/sys/fs/binfmt_misc/WSLInterop"))
            && FileManager.default.isExecutableFile(atPath: powershell)

        static func set(_ window: UnsafeMutablePointer<GtkWidget>, topmost: Bool) {
            guard isAvailable,
                let titlePointer = gtk_window_get_title(
                    UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self))
            else { return }
            let distro = ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] ?? "Ubuntu"
            let title = "\(String(cString: titlePointer)) (\(distro))"
                .replacingOccurrences(of: "'", with: "''")
            let insertAfter = topmost ? -1 : -2  // HWND_TOPMOST / HWND_NOTOPMOST
            // EnumWindows and GetWindowText rather than FindWindow: FindWindow
            // compares a window's stored text, and WSLg's Windows windows answer
            // their title only through WM_GETTEXT -- FindWindow never found
            // "P37 window level (Ubuntu)" in 25 s while EnumWindows listed it
            // (2026-10-21).
            // 用 EnumWindows 與 GetWindowText,而不是 FindWindow:FindWindow 比對的是視窗儲存的文字，而 WSLg 的 Windows
            // 視窗只透過 WM_GETTEXT 回答標題——25 秒內 FindWindow 從未找到「P37 window level (Ubuntu)」,EnumWindows 卻列得出
            // 它(2026-10-21)。
            let script = """
                Add-Type -Namespace Scui -Name User32 -MemberDefinition @'
                public delegate bool EnumProc(IntPtr h, IntPtr l);
                [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
                [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
                [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
                '@
                for ($i = 0; $i -lt 30; $i++) {
                    $found = [IntPtr]::Zero
                    [Scui.User32]::EnumWindows({
                        param($h, $l)
                        $text = New-Object System.Text.StringBuilder 512
                        [void][Scui.User32]::GetWindowText($h, $text, 512)
                        if ($text.ToString() -eq '\(title)') { $script:found = $h; return $false }
                        return $true
                    }, [IntPtr]::Zero) | Out-Null
                    if ($found -ne [IntPtr]::Zero) {
                        [Scui.User32]::SetWindowPos($found, [IntPtr]\(insertAfter), 0, 0, 0, 0, 0x13) | Out-Null
                        exit 0
                    }
                    Start-Sleep -Milliseconds 100
                }
                exit 1
                """
            // -EncodedCommand takes UTF-16LE in base64, so the script crosses WSL
            // interop without any quoting of its own.
            // -EncodedCommand 接受 base64 編碼的 UTF-16LE,讓腳本不經任何引號處理就能跨過 WSL 互通。
            let utf16 = script.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: powershell)
            process.arguments = [
                "-NoProfile", "-NonInteractive", "-EncodedCommand",
                Data(utf16).base64EncodedString(),
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
#endif
