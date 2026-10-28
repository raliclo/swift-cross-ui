# windows

Native Windows: WinUIBackend, and GtkBackend on Windows (GTK 4.22.4, `-gtk4`
builds, `Pn-gtk4.exe`). WSL is a separate platform (see the WSL index).
Index as of 2026-10-24; each line links one topic.

## Toolchain and build

- [Swift toolchain](windows/swift-toolchain.md) -- Swift 6.4.1; 6.3.3 exes die with 0xC0000139 on 6.4; what swiftbuild changed; WinUI cannot compile on the Mac.
- [Building and stripped exes](windows/build-and-stripped-exes.md) -- compile.zsh defaults (release, SCUI_DEBUG=1), separate build trees, stale debug.yaml, `llvm-strip --strip-debug` (22.6 -> 11.1 GB), build times.

## WinUIBackend

- [Stack and threading](windows/winui-stack-and-threading.md) -- swift-winui 0.2.1 on WinAppSDK 1.5 preview; the STA start and its copied tickler; main queue drained by a wait (P66); never subclass WebView2.
- [Layout and hit testing](windows/winui-layout-and-hit-testing.md) -- a transparent brush swallows clicks (use nil); text +1 DIP at 125%; parent links before load; ComboBox measurement; gesture handlers.
- [Controls](windows/winui-controls.md) -- own date wheels for `\.locale`, shell file dialogs, popover arrow, sheets as ContentDialog popups, menus, Ctrl+Shift+Z redo.
- [Effects, gradients and Mesh3D](windows/winui-effects-and-3d.md) -- Win2D effect graph (contrast matrix, AppKit grayscale), conic gradients, SVG text via DirectWrite, D3D11 meshes and the rasterization scale.

## GtkBackend on Windows

- [GTK runtime and -gtk4 builds](windows/gtk-runtime.md) -- gvsbuild GTK 4.22.4 (not MSYS2/vcpkg), the AccessKit build, `.pc` rewriting, gtk_runtime.zsh PATH, WebView2 for WebView.
- [Renderer and GPU](windows/gtk-renderer-and-gpu.md) -- Direct Composition on by default; per-exe GPU registry policy; the dGPU wake-up stall (P107, accepted); first-frame warm-up in a throwaway window.
- [Scale, windows and popovers](windows/gtk-windows-scale-and-popovers.md) -- GTK scale 1 vs Win32 1.25; popovers are top-level windows; the single-instance empty log; windows that would not shrink.
- [Input](windows/gtk-input.md) -- touch plus emulated mouse; VK_PACKET keys as VoidSymbol; the GDK touch-device use-after-free.
- [Theme, fonts, accessibility, frame rate](windows/gtk-theme-fonts-a11y.md) -- dark mode from the registry, Segoe UI's five weights, AccessKit for UIA, CSS reloads that cost 2/3 of the frame rate (P96).

## Video (P6)

- [P6 on WinUI: D3D11 and SwapChainPanel](windows/p6-video-d3d11.md) -- ffmpeg in a child process, raw-COM SwapChainPanel, NV12 through the video processor for 4K60, the pipe-size and @Published traps.
- [P6-v2 on GTK](windows/p6-v2-video-gtk.md) -- NV12 in a GLArea, hardware decode chosen by the first frame, frame-clock mailbox, atempo chain.

## Harness

- [test.zsh on Windows](windows/harness-test-zsh.md) -- `-win`, TEST_BACKEND/TEST_GPU, the run in order, exit codes, ui-lock; stale gtk4 exes before b76c6818.
- [Screenshots: wincap](windows/harness-wincap.md) -- WGC then PrintWindow, count non-black pixels, popups not in window captures, captures work on a locked desktop.
- [Input injection](windows/harness-input-injection.md) -- topmost pin, SetCursorPos vs stepped SendInput on WinUI, held drags, keys, why injection is refused.
- [touch_gesture and hold mode](windows/harness-touch-gesture.md) -- synthetic pointer touch, hold timed by the clock, the drag-argument bug.
- [Action files](windows/action-files.md) -- DIPs on WinUI vs GTK pixels, `origin=popover`, files that invalidate their own coordinates, `move` vs `hover`.
- [UI Automation measuring](windows/harness-uia-measure.md) -- measure_win.zsh, uia_rects, Invoke without the mouse, sheets seen by UIA.

## Machine and shell

- [Win11 and multissh](windows/win11-machine.md) -- ASUS TUF A15 with AMD iGPU + RTX 4060 at 125%, input blockers, self-locking, `multissh -F ...config2Win winnode`.
- [scoop zsh, MSYS paths, jq.exe CRLF](windows/shell-scoop-zsh-jq-crlf.md) -- strip `\r` from every native tool, `MSYS2_ARG_CONV_EXCL` vs `//FI`, `cygpath`, ASCII-only PowerShell.

## Known limits and open items (last checked)

- GTK: first hardware present ~0.3 s inside GTK (2026-10-20); emoji without glyphs (2026-10-19); fractional-scale look (2026-10-23); popover menu arrow-key start (queue row 24a); GDK device bug not reported upstream (2026-10-24).
- WinUI: `.graphical` calendar stays English (2026-10-20); P41 taller than the screen at 125% (2026-10-20); WinAppSDK still a preview (#204).
- Video: fixed 960x540 area, no WARP fallback on `.display`, no zero-copy, A/V drift at 3x; P6-v2 pickers on GTK (2026-10-24).
- Harness: Win32 `forgetFocus()` mid-file unverified; the remote-desktop disconnect experiment (2026-10-24). (`test.zsh` never running check_wsl_host.zsh: fixed in a92edee1, verified 2026-10-29.) (winmin.exe built by test_common.zsh when missing: 2026-10-29.)
- Speech output of Narrator/NVDA (queue row 8, 2026-10-23).

---

# windows

原生 Windows:WinUIBackend,以及 Windows 上的 GtkBackend(GTK 4.22.4、`-gtk4` 建置、`Pn-gtk4.exe`)。WSL 是另一個
平台(見 WSL 索引)。2026-10-24 的索引；每行連到一個主題。

## 工具鏈與建置

- [Swift toolchain](windows/swift-toolchain.md)——Swift 6.4.1;6.3.3 的 exe 在 6.4 上以 0xC0000139 終止;swiftbuild 改變了什麼;WinUI 無法在 Mac 上編譯。
- [建置與去除除錯資訊的 exe](windows/build-and-stripped-exes.md)——compile.zsh 預設(release、SCUI_DEBUG=1)、分開的建置樹、過期的 debug.yaml、`llvm-strip --strip-debug`(22.6 -> 11.1 GB)、建置時間。

## WinUIBackend

- [技術堆疊與執行緒](windows/winui-stack-and-threading.md)——WinAppSDK 1.5 預覽版上的 swift-winui 0.2.1;STA 啟動與複製來的 tickler;以等待排空主佇列(P66);絕不繼承 WebView2。
- [版面與點擊判定](windows/winui-layout-and-hit-testing.md)——透明筆刷會吞掉點擊(用 nil);125% 下文字加 1 DIP;載入前的父連結;ComboBox 量測；手勢 handler。
- [控制項](windows/winui-controls.md)——為 `\.locale` 自繪日期滾輪、shell 檔案對話框、popover 箭頭、sheet 是 ContentDialog popup、選單、Ctrl+Shift+Z 重做。
- [效果、漸層與 Mesh3D](windows/winui-effects-and-3d.md)——Win2D 效果圖(對比矩陣、AppKit 灰階)、圓錐漸層、經 DirectWrite 的 SVG 文字、D3D11 mesh 與 rasterization scale。

## Windows 上的 GtkBackend

- [GTK runtime 與 -gtk4 建置](windows/gtk-runtime.md)——gvsbuild 的 GTK 4.22.4(非 MSYS2/vcpkg)、AccessKit 建置、`.pc` 改寫、gtk_runtime.zsh 的 PATH、WebView 用 WebView2。
- [算繪器與 GPU](windows/gtk-renderer-and-gpu.md)——預設開啟 Direct Composition;逐 exe 的 GPU 登錄原則；獨顯喚醒延遲(P107,已接受);在用完即丟的視窗中做第一幀暖機。
- [縮放、視窗與 popover](windows/gtk-windows-scale-and-popovers.md)——GTK 縮放 1 對 Win32 1.25;popover 是 top-level 視窗；單一實例的空 log;不會縮小的視窗。
- [輸入](windows/gtk-input.md)——觸控加上模擬滑鼠;VK_PACKET 按鍵變成 VoidSymbol;GDK 觸控裝置的釋放後使用。
- [主題、字型、無障礙、幀率](windows/gtk-theme-fonts-a11y.md)——由登錄讀取深色模式、Segoe UI 的五種字重、UIA 靠 AccessKit、CSS 重新載入吃掉三分之二的幀率(P96)。

## 影片(P6)

- [WinUI 上的 P6:D3D11 與 SwapChainPanel](windows/p6-video-d3d11.md)——子行程中的 ffmpeg、原始 COM 的 SwapChainPanel、經 video processor 的 NV12 達成 4K60、pipe 大小與 @Published 的陷阱。
- [GTK 上的 P6-v2](windows/p6-v2-video-gtk.md)——GLArea 中的 NV12、依第一幀決定硬體解碼、frame clock 信箱、atempo 串接。

## 測試工具

- [Windows 上的 test.zsh](windows/harness-test-zsh.md)——`-win`、TEST_BACKEND/TEST_GPU、執行順序、結束碼、ui-lock;b76c6818 之前的過期 gtk4 exe。
- [截圖:wincap](windows/harness-wincap.md)——先 WGC 再 PrintWindow、數非黑像素、彈出視窗不在視窗擷取中、鎖定的桌面上擷取仍有效。
- [輸入注入](windows/harness-input-injection.md)——置頂釘選、WinUI 上 SetCursorPos 對分段 SendInput、按住拖曳、按鍵、注入為何被拒。
- [touch_gesture 與 hold 模式](windows/harness-touch-gesture.md)——合成指標觸控、以時鐘計時的按住、drag 引數錯誤。
- [動作檔](windows/action-files.md)——WinUI 的 DIP 對 GTK 的像素、`origin=popover`、讓自己座標失效的檔案、`move` 對 `hover`。
- [UI Automation 量測](windows/harness-uia-measure.md)——measure_win.zsh、uia_rects、不用滑鼠的 Invoke、以 UIA 看到 sheet。

## 機器與 shell

- [Win11 與 multissh](windows/win11-machine.md)——125% 下的 ASUS TUF A15(AMD 內顯 + RTX 4060)、輸入阻擋程式、會自行鎖定、`multissh -F ...config2Win winnode`。
- [scoop 的 zsh、MSYS 路徑、jq.exe 的 CRLF](windows/shell-scoop-zsh-jq-crlf.md)——所有原生工具都要去掉 `\r`、`MSYS2_ARG_CONV_EXCL` 對 `//FI`、`cygpath`、純 ASCII 的 PowerShell。

## 已知限制與未解項目(最後檢查日)

- GTK:GTK 內部第一次硬體 present 約 0.3 秒(2026-10-20);沒有字形的 emoji(2026-10-19);分數縮放下的外觀(2026-10-23);popover 選單方向鍵的起點(queue 第 24a 列);GDK 裝置錯誤未回報上游(2026-10-24)。
- WinUI:`.graphical` 月曆仍是英文(2026-10-20);125% 下 P41 比螢幕高(2026-10-20);WinAppSDK 仍是預覽版(#204)。
- 影片：固定 960x540 的區域、`.display` 沒有 WARP 後備、沒有零複製、3 倍速時影音漂移;GTK 上 P6-v2 的選擇器(2026-10-24)。
- 測試工具:Win32 在檔案中途 `forgetFocus()` 未驗證；遠端桌面中斷連線的實驗(2026-10-24)。(test.zsh 從不執行 check_wsl_host.zsh:a92edee1 已修正,2026-10-29 驗證。)(winmin.exe 不存在時由 test_common.zsh 建置:2026-10-29。)
- Narrator/NVDA 的語音輸出(queue 第 8 列,2026-10-23)。
