# GtkBackend on Windows: Direct Composition, the GPU, and the first frame

Written 2026-10-24 from Sources/GtkBackend/GtkBackend.swift
(`enableDirectCompositionIfRequested`), GtkBackend+RendererWarmUp.swift, commits
c3137522, daaea4ae, d93cd3ce, 27449b63, and results.csv2 (windows, gtk4: P40,
P66, P96, P97, P107; 2026-10-19 to 2026-10-23).

## Direct Composition is on by default

GtkBackend appends `dcomp` to `GDK_DEBUG` before GTK starts (since c3137522,
2026-09-05). That gives `GskGLRenderer` on WGL OpenGL 4.6. Without DComp, GDK
on Windows falls back to `GskCairoRenderer`, which is software. It draws a
transform node only from category 2D up, and a transform handed over as a matrix
is filed UNKNOWN and painted hotpink (P40 drew 47,873 hotpink pixels on Cairo
before the 2026-10-28 fix, 0 with DComp).

- Opt out: `-GPU 0` or `SCUI_GTK_DCOMP=0`. Since 2026-10-28 `setGeometricEffect`
  applies the transform on Cairo too (`AffineTransform2D` writes the matrix as
  translate, rotate and scale steps). Verified on macOS GTK with
  `GSK_RENDERER=cairo`; the Windows `-GPU 0` run is still pending (the Windows
  machine was unreachable on 2026-10-27/28).
- **Crash guard:** requesting DComp without GL segfaults rather than degrading.
  The request is skipped when `GDK_DISABLE` contains `gl`, and when the only
  adapters are the Microsoft Basic Display Adapter / Basic Render Driver.
- `GSK_RENDERER=vulkan` is silently ignored: gvsbuild builds without Vulkan.
  `GSK_RENDERER=cairo` works.
- DComp windows have `WS_EX_NOREDIRECTIONBITMAP`, so BitBlt/gdigrab capture
  black; see [harness-wincap.md](harness-wincap.md).

## Choosing the GPU

OpenGL picks its adapter only through the per-exe policy in
`HKCU\Software\Microsoft\DirectX\UserGpuPreferences` (`GpuPreference=2;` for
high performance). With no entry, an exe gets the AMD iGPU on Win11.

- `-GPU N` (N >= 2) writes the policy and relaunches; `-GPU list` prints the
  adapters.
- `test.zsh` (`-render hw`, the default) writes `GpuPreference=2;` for a
  `-gtk4` exe for the run and restores the old value afterwards (daaea4ae,
  2026-10-19). `TEST_GPU=default` leaves the system default.
- `GDK_DEBUG=opengl` / `GSK_DEBUG=renderer` show which renderer and GPU GTK got.

## The NVIDIA dGPU wakes late (P107) — accepted, not fixed

On the RTX 4060 (Optimus laptop), the first frame after the dGPU has idled
about 0.3 s waits for it to wake: 97-158 ms, growing with the idle time
(0.05 s idle -> 16-21 ms; 3 s -> 153-158 ms). It sits between the GDK frame
clock's layout and paint of that one frame, with every GPU renderer (gl, ngl,
vulkan 121-138 ms) and not with Cairo (14 ms). Shader compilation and the
frame-clock timestamps were measured and ruled out. On the default GPU (AMD
iGPU) it never appears. Closed 2026-10-23 as a hardware property (queue row 32).
Use `TEST_GPU=default` for timing tests.

## First-frame warm-up

The GPU renderer's first frame costs about 0.2 s, which delayed animations
started in `onAppear` (P97 starts 0.39-0.45 s; Cairo 0.17-0.19 s).
`GtkBackend+RendererWarmUp.swift` renders one offscreen frame in a **throwaway
window** at window creation (Windows only, `SCUI_GTK_WARMUP=0` turns it off):
P97 starts 0.20-0.31 s with it, 0.50 s without (2026-10-23).

Do not realize the app's own window for the warm-up. d93cd3ce did, and the app
lost its menu bar (P92, fixed in 27449b63).

## Limits

- A cold direct launch still spends about 0.3 s in the window's first hardware
  present inside GTK: P97 0.42-0.48 s with DComp against 0.19-0.23 s with
  `GDK_DISABLE=dcomp`. DComp cannot be dropped (no OpenGL for `GLArea` without it). Open in
  GTK, last checked 2026-10-20.
- With the AMD display adapter disabled in Device Manager, DXGI listed WARP
  first and WGL fell back to "GDI Generic" OpenGL 1.1; a `GLArea` then reports
  no GL implementation (P72, 2026-10-07; 34677da8, 08939ad9). Check the adapter
  state before reading a GL failure as a backend bug.

---

# Windows 上的 GtkBackend:Direct Composition、GPU 與第一幀

2026-10-24 依 Sources/GtkBackend/GtkBackend.swift(`enableDirectCompositionIfRequested`)、
GtkBackend+RendererWarmUp.swift、c3137522、daaea4ae、d93cd3ce、27449b63,以及 results.csv2(windows、gtk4:
P40、P66、P96、P97、P107;2026-10-19 至 2026-10-23)寫成。

## 預設開啟 Direct Composition

GtkBackend 在 GTK 啟動前把 `dcomp` 加進 `GDK_DEBUG`(自 c3137522,2026-09-05)。如此得到跑在 WGL OpenGL 4.6
上的 `GskGLRenderer`。沒有 DComp 時,Windows 上的 GDK 退回軟體的 `GskCairoRenderer`。它只畫類別為 2D 以上的
transform 節點，而以矩陣交出的變換一律被歸為 UNKNOWN 並畫成 hotpink(P40 在 2026-10-28 修正前於 Cairo 上
有 47,873 個 hotpink 像素，開 DComp 為 0)。

- 關閉:`-GPU 0` 或 `SCUI_GTK_DCOMP=0`。自 2026-10-28 起，`setGeometricEffect` 在 Cairo 上也會套用變換
  (`AffineTransform2D` 把矩陣寫成平移、旋轉與縮放步驟)。已在 macOS GTK 以 `GSK_RENDERER=cairo` 驗證;
  Windows 的 `-GPU 0` 執行仍待補(2026-10-27/28 Windows 主機無法連線)。
- **防當機：**沒有 GL 卻要求 DComp 會直接 segfault,而不是降級。`GDK_DISABLE` 含 `gl`,或唯一的 adapter 是
  Microsoft Basic Display Adapter / Basic Render Driver 時，就不提出要求。
- `GSK_RENDERER=vulkan` 會被靜默忽略:gvsbuild 建置時沒有 Vulkan。`GSK_RENDERER=cairo` 可用。
- DComp 視窗帶有 `WS_EX_NOREDIRECTIONBITMAP`,BitBlt/gdigrab 擷取為全黑；見 [harness-wincap.md](harness-wincap.md)。

## 選擇 GPU

OpenGL 只透過 `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` 的逐 exe 原則選 adapter(高效能為
`GpuPreference=2;`)。沒有設定時,Win11 上的 exe 會拿到 AMD 內顯。

- `-GPU N`(N >= 2)寫入原則並重新啟動;`-GPU list` 列出 adapter。
- `test.zsh`(預設 `-render hw`)在執行期間為 `-gtk4` exe 寫入 `GpuPreference=2;`,結束後還原(daaea4ae,
  2026-10-19)。`TEST_GPU=default` 維持系統預設。
- `GDK_DEBUG=opengl` / `GSK_DEBUG=renderer` 會顯示 GTK 拿到的算繪器與 GPU。

## NVIDIA 獨顯喚醒較慢(P107)——已接受，不修

在 RTX 4060(Optimus 筆電)上，獨顯閒置約 0.3 秒後的第一幀要等它喚醒:97–158 ms,隨閒置時間增加(閒置 0.05 秒
-> 16–21 ms;3 秒 -> 153–158 ms)。延遲位在那一幀的 GDK frame clock layout 與 paint 之間，所有 GPU 算繪器都有
(gl、ngl、vulkan 121–138 ms),Cairo 沒有(14 ms)。shader 編譯與 frame clock 時間戳都量過並排除。在預設 GPU
(AMD 內顯)上從未出現。2026-10-23 以硬體特性結案(queue 第 32 列)。計時測試請用 `TEST_GPU=default`。

## 第一幀暖機

GPU 算繪器的第一幀約需 0.2 秒，使在 `onAppear` 開始的動畫延遲(P97 起點 0.39–0.45 秒;Cairo 0.17–0.19 秒)。
`GtkBackend+RendererWarmUp.swift` 在建立視窗時於一個**用完即丟的視窗**裡畫一幀離屏畫面(僅 Windows,
`SCUI_GTK_WARMUP=0` 關閉):有暖機時 P97 起點 0.20–0.31 秒，沒有時 0.50 秒(2026-10-23)。

暖機不可 realize app 自己的視窗。d93cd3ce 這麼做，結果 app 失去了選單列(P92,27449b63 修正)。

## 限制

- 冷啟動仍有約 0.3 秒花在 GTK 內部視窗的第一次硬體 present:P97 開 DComp 為 0.42–0.48 秒,`GDK_DISABLE=dcomp`
  為 0.19–0.23 秒。DComp 不能拿掉(沒有它就沒有 OpenGL 可供 `GLArea` 使用)。屬 GTK 內部問題，仍未解決，最後檢查 2026-10-20。
- 在裝置管理員停用 AMD 顯示卡時,DXGI 把 WARP 列在第一個,WGL 退回「GDI Generic」OpenGL 1.1,`GLArea` 便回報
  沒有 GL 實作(P72,2026-10-07;34677da8、08939ad9)。把 GL 失敗當成 backend 錯誤之前，先確認顯示卡狀態。
