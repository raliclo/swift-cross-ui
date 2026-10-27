# Screenshots on Windows: wincap and screenshot.zsh

Written 2026-10-24 from testapp/wincap.cpp, testapp/screenshot.zsh,
testapp/FAQ.md, commit 1a69075f (2026-09-14), testapp/P0-P26-windows-findings.md,
and results.csv2 (windows: P95, P17-DOE, P81, P100 2026-10-20).

## What

`screenshot.zsh -w <title>` captures one window with `testapp/helper/bin/wincap.exe`:

1. Find the first visible window whose title contains the argument
   (case-insensitive; retried every 250 ms for 5 s; per-monitor DPI aware v2).
2. **Windows Graphics Capture** (D3D11 device, free-threaded frame pool), waiting
   up to 750 ms for a frame with at least 2% non-black pixels (non-black: any of
   B, G, R above 8).
3. Otherwise `PrintWindow(..., PW_RENDERFULLCONTENT)`.

wincap logs the window rect, exstyle, cloaked state and display affinity into
`*-wincap.log` beside the PNG. Exstyle `0x200000` (`WS_EX_NOREDIRECTIONBITMAP`)
marks a Direct Composition window. Exit 1 no window, 3 image under 2% non-black;
screenshot.zsh returns 4 when an image was written and rejected. With `-w` it
fails closed; without `-w` it captures the desktop with `ffmpeg -f gdigrab`.

`ensure_wincap` rebuilds wincap.exe when the source is newer: cppwinrt from
Windows SDK 10.0.22621.0 (hard-coded path), then clang++ -std=c++20.

## Why not gdigrab or PrintWindow alone

- gdigrab by title matched exactly, used BitBlt, sometimes hung, exited 0 when
  no window matched, and returned black for DComp windows (GTK with GL, WinUI
  swap chains).
- PrintWindow alone returned TRUE with an all-black image for GTK GL windows.

## How to apply

- **Count non-black pixels; never trust an exit status.** A cold first present
  can read 0.0% (P17-DOE; a retry gave 91.1%). A small PNG can be valid: the
  5000-byte floor now applies only when wincap logged under 2% (P95, a 4531-byte
  capture at 88.8%).
- The non-black count says "this is a real capture", not "the content changed"
  (P34: identical counts before and after a real scroll).
- **Popups are not in a window capture**: GTK popovers, WinUI ContentDialog
  sheets and covers, menus. Use `TEST_FINAL_CAPTURE=desktop`, a desktop capture,
  or UIA ([harness-uia-measure.md](harness-uia-measure.md)).
- **A window capture works on a locked desktop** and still shows the app drawn
  correctly; judge the lock by a desktop capture (black or the lock screen) or
  by injection failing. With the display off, both WGC and PrintWindow gave
  0.0% (P100, 2026-10-20).
- For video and animation, `videoshot.zsh` records the composited desktop.

---

# Windows 上的截圖:wincap 與 screenshot.zsh

2026-10-24 依 testapp/wincap.cpp、testapp/screenshot.zsh、testapp/FAQ.md、1a69075f(2026-09-14)、
testapp/P0-P26-windows-findings.md,以及 results.csv2(windows:P95、P17-DOE、P81、P100 於 2026-10-20)寫成。

## 內容

`screenshot.zsh -w <標題>` 以 `testapp/helper/bin/wincap.exe` 擷取單一視窗:

1. 找第一個標題包含該引數的可見視窗(不分大小寫；每 250 ms 重試、最多 5 秒；per-monitor DPI aware v2)。
2. **Windows Graphics Capture**(D3D11 device、free-threaded frame pool),最多等 750 ms,直到某一幀至少 2% 的像素
   非黑(非黑:B、G、R 任一大於 8)。
3. 否則用 `PrintWindow(..., PW_RENDERFULLCONTENT)`。

wincap 把視窗矩形、exstyle、cloaked 狀態與 display affinity 記到 PNG 旁的 `*-wincap.log`。exstyle `0x200000`
(`WS_EX_NOREDIRECTIONBITMAP`)代表 Direct Composition 視窗。結束碼 1 為找不到視窗,3 為影像非黑像素低於 2%;
screenshot.zsh 在寫出影像但被判不合格時回傳 4。加 `-w` 時失敗即失敗、不退回;不加 `-w` 則以 `ffmpeg -f gdigrab`
擷取桌面。

`ensure_wincap` 在原始碼較新時重建 wincap.exe:先以 Windows SDK 10.0.22621.0 的 cppwinrt(路徑寫死),再以
clang++ -std=c++20 編譯。

## 為何不只用 gdigrab 或 PrintWindow

- 以標題呼叫 gdigrab 要求完全相符、用 BitBlt、有時卡住、找不到視窗時以 0 結束，且對 DComp 視窗(使用 GL 的 GTK、
  WinUI 的 swap chain)回傳全黑。
- 只用 PrintWindow 時，對 GTK GL 視窗回傳 TRUE 卻是全黑影像。

## 如何運用

- **數非黑像素；永遠不要相信結束碼。** 冷啟動的第一次 present 可能是 0.0%(P17-DOE;重試得到 91.1%)。小的 PNG
  也可能有效:5000 位元組的下限現在只在 wincap 記錄低於 2% 時才適用(P95,一張 4531 位元組、88.8% 的擷圖)。
- 非黑像素數說的是「這是一張真的擷圖」,不是「內容改變了」(P34:真正捲動前後的數值完全相同)。
- **彈出視窗不在視窗擷取裡**:GTK popover、WinUI 的 ContentDialog sheet 與覆蓋、選單。請用
  `TEST_FINAL_CAPTURE=desktop`、桌面擷取或 UIA([harness-uia-measure.md](harness-uia-measure.md))。
- **工作站鎖定時視窗擷取仍然有效**,而且 app 畫得好好的；判斷鎖定要看桌面擷取(全黑或鎖定畫面)或注入失敗。
  螢幕關閉時,WGC 與 PrintWindow 都是 0.0%(P100,2026-10-20)。
- 影片與動畫用 `videoshot.zsh` 錄下合成後的桌面。
