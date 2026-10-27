# WSLg: the first frame with new draw state stalls (Mesa d3d12)

Written 2026-10-24 from queue.md row 27 and matrix_coverage/results.csv2
(wsl, gtk4, P96, 2026-10-23). The full Mesa issue draft is
[mesa-d3d12-issue.md](mesa-d3d12-issue.md) (not filed as of 2026-10-24); the
standalone reproduction is [first-frame-stall.c](first-frame-stall.c).

## What

Under WSLg, GTK 4 draws through OpenGL on Mesa's d3d12 Gallium driver, which
translates to Direct3D 12 on the Windows GPU. The first frame that draws a
combination of state not drawn before in that process waits while the driver
compiles: P96's first moving frame waited 870 ms (866-985 ms, every run)
between GTK's `layout` and `paint` phases. Every later frame took 16.9 ms
(59 fps, the WSLg 60 Hz rate).

## Why

Read from Mesa 26.0.8, `src/gallium/drivers/d3d12`:

- shader variants are kept only in memory (`select_shader_variant`,
  `d3d12_compiler.cpp`); each miss runs `nir_to_dxil` again;
- the d3d12 screen implements no `get_disk_shader_cache`, so Mesa's disk cache
  does not apply to this driver;
- every PSO is created with `CachedPSO.pCachedBlob = NULL`
  (`d3d12_pipeline_state.cpp`), so the NVIDIA driver compiles each PSO again;
- the PSO cache lives on `d3d12_context`; GTK has one GL context per window.

So the work is repeated in every process. perf (Ubuntu `linux-perf`, DWARF
unwinding) during the wait: 51% `libgallium` (Mesa d3d12), 21% `libnvwgf2umx`
(NVIDIA user-mode driver), 5% `libnvidia-gpucomp`, the rest off the CPU. It is
a Mesa limitation, not an NVIDIA defect.

## What is in place

`GtkBackend+RendererWarmUp.swift` runs on Linux too since add249b9
(2026-10-23): before the content exists, a throwaway window renders one
offscreen frame of common GSK nodes (colour, rounded clip, gradient, border,
shadow, text, a filled and a stroked `GskPath`, a fill under the
`Fixed.setChildMatrix` transform). The wait drops to about 560 ms; P96's first
3 s rise from 41.0-41.7 fps to 48.3-49.0 fps (interleaved, two rounds).
`SCUI_GTK_WARMUP=0` turns it off for measuring.

Before this, P96's driven panel ran at about 30 fps on WSL for a different
reason: every update reloaded unchanged CSS into a display-wide provider.
7ad78a1a fixed that (WSL 29-30 to 36.7 fps).

## How to apply

- A slow first animated frame under WSLg is expected; check frames after it
  before calling a frame-rate regression.
- Do not warm the app's own window: it saves about another 120 ms (the
  per-context PSO cache) but realizing the window that early hid P92's menu
  bar on Windows GTK (d93cd3ce to 2026-10-23).
- `-render sw` (llvmpipe) waits 443 ms for its own JIT; it is not a fix.
- Profile with `linux-perf` from Ubuntu; WSL's own perf under
  `/usr/lib/linux-tools/*-microsoft-standard-WSL2` resolves no symbols.
  `libgallium` has no symbols without its debug package.

## Limits

- Open as of 2026-10-24: what remains is draw state the warm-up does not
  reach, which an application cannot enumerate. The real fix is a persistent
  d3d12 cache in Mesa (`get_disk_shader_cache`, or `GetCachedBlob` passed back
  through `CachedPSO`).
- Measured on Mesa 26.0.8, GTK 4.22.4, NVIDIA RTX 4060 Laptop with Windows
  driver 617.42. Re-check after any of those changes.
- The first paragraph of the `RendererWarmUp` comment still says "Mesa keeps a
  shader cache on disk" for WSLg; the later paragraph of the same comment and
  the Mesa source show that cache does not cover d3d12 variants.

---

# WSLg:第一個帶有新繪圖狀態的幀會卡住(Mesa d3d12)

2026-10-24 依 queue.md 第 27 列與 matrix_coverage/results.csv2(wsl、gtk4、P96、2026-10-23)寫成。完整的
Mesa issue 草稿在 [mesa-d3d12-issue.md](mesa-d3d12-issue.md)(至 2026-10-24 尚未提交);獨立重現程式在
[first-frame-stall.c](first-frame-stall.c)。

## 是什麼

WSLg 下,GTK 4 經由 OpenGL 繪製，底層是 Mesa 的 d3d12 Gallium 驅動，再轉成 Windows GPU 上的 Direct3D 12。
一個行程中第一次畫出某種狀態組合的幀，要等驅動編譯完:P96 第一個移動的幀在 GTK 的 `layout` 與 `paint`
階段之間等了 870 毫秒(866–985 毫秒，每次都是)。之後每一幀 16.9 毫秒(59 fps,即 WSLg 的 60 Hz)。

## 為什麼

讀 Mesa 26.0.8 的 `src/gallium/drivers/d3d12`:

- shader 版本只存在記憶體(`d3d12_compiler.cpp` 的 `select_shader_variant`),每次沒命中都重跑 `nir_to_dxil`;
- d3d12 screen 沒有實作 `get_disk_shader_cache`,Mesa 的磁碟快取對這個驅動不適用;
- 每個 PSO 建立時都是 `CachedPSO.pCachedBlob = NULL`(`d3d12_pipeline_state.cpp`),NVIDIA 驅動每次都重新編譯;
- PSO 快取放在 `d3d12_context` 上，而 GTK 每個視窗一個 GL context。

所以每個行程都重做一遍。perf(Ubuntu 的 `linux-perf`,DWARF 回溯)在等待期間:`libgallium`(Mesa d3d12)51%、
`libnvwgf2umx`(NVIDIA 使用者模式驅動)21%、`libnvidia-gpucomp` 5%,其餘不在 CPU 上。這是 Mesa 的限制，不是
NVIDIA 的缺陷。

## 目前的做法

自 add249b9(2026-10-23)起,`GtkBackend+RendererWarmUp.swift` 在 Linux 上也執行：內容出現之前，用一個用完即丟
的視窗在螢幕外畫一幀常見的 GSK 節點(色塊、圓角裁切、漸層、邊框、陰影、文字、填色與描邊的 `GskPath`、
`Fixed.setChildMatrix` 變換下的填色)。等待降到約 560 毫秒;P96 前 3 秒由 41.0–41.7 fps 升到 48.3–49.0 fps
(交錯量測兩輪)。`SCUI_GTK_WARMUP=0` 可關閉，供量測用。

在此之前,P96 的 driven 面板在 WSL 上約 30 fps,原因另有其事：每次更新都把沒變的 CSS 重新載入整個 display
共用的 provider。7ad78a1a 修好了(WSL 由 29–30 升到 36.7 fps)。

## 怎麼用

- WSLg 下第一個動畫幀慢是預期的；判定幀率退化之前，先看它之後的幀。
- 不要預熱 app 自己的視窗：可再省約 120 毫秒(每個 context 的 PSO 快取),但那麼早 realize 視窗曾讓 Windows GTK
  上 P92 的選單列消失(d93cd3ce 到 2026-10-23)。
- `-render sw`(llvmpipe)為自己的 JIT 等 443 毫秒；不是解法。
- 用 Ubuntu 的 `linux-perf` 分析;WSL 自帶、位於 `/usr/lib/linux-tools/*-microsoft-standard-WSL2` 的 perf 解不出
  任何符號。`libgallium` 沒有除錯套件就沒有符號。

## 限制

- 至 2026-10-24 仍未解決：剩下的是預熱沒涵蓋到的繪圖狀態，app 無法列舉。真正的修法是 Mesa 為 d3d12 提供持久
  快取(`get_disk_shader_cache`,或把 `GetCachedBlob` 的結果經 `CachedPSO` 傳回)。
- 量測環境為 Mesa 26.0.8、GTK 4.22.4、NVIDIA RTX 4060 Laptop、Windows 驅動 617.42。其中任一改變後要重新查證。
- `RendererWarmUp` 註解的第一段仍寫著 WSLg「Mesa 在磁碟上保留 shader 快取」;同一註解的後段與 Mesa 原始碼都
  顯示那個快取不涵蓋 d3d12 版本。
