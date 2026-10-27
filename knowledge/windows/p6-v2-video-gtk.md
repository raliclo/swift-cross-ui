# P6-v2 video on GTK under Windows: NV12 in a GLArea

Written 2026-10-24 from testapp/P6-v2.swift, testapp/P6-v2-features.md,
Sources/Gtk/Widgets/NV12GLView.swift, Sources/GtkCHelpers/gtk_nv12_gl.c,
commit b6a8a6ee, and results.csv2 (windows, gtk4, P6-v2, 2026-10-20).

## Pipeline

ffmpeg in a separate process writes NV12 frames to a pipe; a `GtkGLArea`
uploads them and a GL fragment shader converts to RGB. Audio is a separate
`ffplay`. Build with `compile.zsh -gtk4` (P6 itself is refused there).

## Facts

- **Hardware decode is chosen by whether the first frame arrives**, trying
  `d3d11va, cuda, dxva2, qsv`, then software. `ffmpeg -hwaccels` lists what was
  compiled in, not what works. `-gpu` refuses to fall back; `-cpu` forces software.
- **Frame handover:** a one-slot mailbox drained by a GTK frame-clock tick
  callback, with back-pressure when two frames are undrawn. `g_idle_add` did
  not work at either priority: 0 starved redraws (~10 renders/s), 200 never ran.
- Throughput, 1080p60 (2026-08-20): RGBA through `GdkMemoryTexture` 42-44 fps,
  falling to 23 over 60 s; NV12 through GL 51.9 fps (peaks 61).
- At 3x, audio needs `atempo=1.5,atempo=2.0`: a single `atempo=3` makes ffplay
  exit at once, which looks like "no sound". `-seek2any 1` fixed A/V drift after
  a seek.
- GTK's GPU on Windows is chosen by the per-exe registry policy, see
  [gtk-renderer-and-gpu.md](gtk-renderer-and-gpu.md); `GDK_DEBUG=opengl` shows it.

## Testing

`actions/win/P6-v2-transport-toggles-gtk4.actions` passed on 2026-10-20 (Frame
drop on, Speed 2x, FPS 60). With `--actionfile` the app runs 40 s: at
`-seconds 12` it exited before the final capture of a ~12 s replay (b6a8a6ee).

## Open (checked 2026-10-24)

- The P6-v2 file pickers on Windows GTK open a window that does not come to the
  front and does not close after a selection. Not diagnosed.
- No zero-copy path (`glImportMemoryWin32HandleEXT` is available but unused).

---

# Windows 上以 GTK 播放 P6-v2 影片:GLArea 中的 NV12

2026-10-24 依 testapp/P6-v2.swift、testapp/P6-v2-features.md、Sources/Gtk/Widgets/NV12GLView.swift、
Sources/GtkCHelpers/gtk_nv12_gl.c、b6a8a6ee,以及 results.csv2(windows、gtk4、P6-v2、2026-10-20)寫成。

## 管線

獨立行程中的 ffmpeg 把 NV12 影格寫進 pipe;`GtkGLArea` 上傳後由 GL fragment shader 轉成 RGB。聲音是另一個
`ffplay`。以 `compile.zsh -gtk4` 建置(P6 本身在那裡會被拒絕)。

## 事實

- **硬體解碼依「第一幀是否抵達」來決定**,依序嘗試 `d3d11va, cuda, dxva2, qsv`,最後軟體解碼。`ffmpeg -hwaccels`
  列出的是編入了什麼，不是什麼能用。`-gpu` 拒絕退回;`-cpu` 強制軟體解碼。
- **影格交接：**單格信箱，由 GTK frame clock 的 tick callback 取走；有兩幀未畫時施加背壓。`g_idle_add` 在兩種優先序
  下都不行:0 讓重繪餓死(每秒約 10 次),200 從未執行。
- 吞吐量,1080p60(2026-08-20):經 `GdkMemoryTexture` 的 RGBA 42–44 fps,60 秒內降到 23;經 GL 的 NV12 51.9 fps
  (峰值 61)。
- 3 倍速時聲音需要 `atempo=1.5,atempo=2.0`:單一的 `atempo=3` 會讓 ffplay 立刻結束，看起來像「沒有聲音」。
  `-seek2any 1` 修正了跳轉後的影音漂移。
- Windows 上 GTK 的 GPU 由逐 exe 的登錄原則決定，見 [gtk-renderer-and-gpu.md](gtk-renderer-and-gpu.md);
  `GDK_DEBUG=opengl` 會顯示。

## 測試

`actions/win/P6-v2-transport-toggles-gtk4.actions` 於 2026-10-20 通過(Frame drop 開、Speed 2x、FPS 60)。加
`--actionfile` 時 app 執行 40 秒：用 `-seconds 12` 時，它在約 12 秒的重放結束前就退出，拍不到最後的擷圖(b6a8a6ee)。

## 未解決(檢查於 2026-10-24)

- Windows GTK 上 P6-v2 的檔案選擇器開出的視窗不會到最前面，選完也不會關閉。尚未診斷。
- 沒有零複製路徑(`glImportMemoryWin32HandleEXT` 可用但未使用)。
