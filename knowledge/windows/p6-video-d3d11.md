# P6 video on WinUI: ffmpeg, Direct3D 11 and a SwapChainPanel

Written 2026-10-24 from Sources/WinUIBackend/D3D11VideoInterop.swift,
testapp/P6.swift, testapp/P6_findings/, commits 360bcad2, 84718ee6, b250da26,
bafbc949, 7697dbe6, 8dc6380b, 30f1d69c, and results.csv2 (windows, winui, P6,
2026-10-20).

## Pipeline

ffmpeg decodes in a **separate process** (no Media Foundation). Raw frames come
through a pipe and are read straight into mapped D3D11 staging textures, then
shown by a composition swap chain inside a `SwapChainPanel`. Audio is a separate
`ffplay -nodisp -autoexit`. P6 builds only as WinUI; P6-v2 is the GTK
counterpart ([p6-v2-video-gtk.md](p6-v2-video-gtk.md)).

## Why a SwapChainPanel, driven by raw COM

- A child-HWND swap chain is never visible: XAML composes through Direct
  Composition and draws over it (airspace).
- swift-winui does not project SwapChainPanel, and its wrappers resolve COM
  interfaces lazily behind `try!`, which traps (0xc000001d). `RawSwapChainPanel`
  drives the panel through vtables and does every QueryInterface up front.
- `CreateSwapChainForComposition`, then `ISwapChainPanelNative::SetSwapChain`,
  which is **UI-thread only**. Map, CopyResource and Present run on the decode
  thread (the D3D11 device is not SINGLETHREADED, so the immediate context is
  serialised internally).
- Swap chain: 2 buffers, FLIP_SEQUENTIAL, STRETCH, ALPHA_MODE_IGNORE; 3 staging
  textures; `Present(1, 0)`. The buffer is in physical pixels, mapped back with
  `SetMatrixTransform(viewport DIPs / buffer pixels)`.
- A WinUI Canvas reports DesiredSize 0: without its own `sizeThatFits` the
  video sat in the bottom-right quarter (360bcad2).

## NV12 is what makes 4K60 work

NV12 goes into a staging texture, is copied to a DEFAULT twin, and an
`ID3D11VideoProcessor` converts and scales it into the back buffer (84718ee6).

- Colour spaces must be set: in `YCBCR_STUDIO_G22_LEFT_P709`, out
  `RGB_FULL_G22_NONE_P709`. Wrong values give washed-out or green video, not an
  error.
- The chroma plane starts at `rowPitch * height`; the input texture needs
  `D3D11_BIND_DECODER` (BIND_SHADER_RESOURCE gives E_INVALIDARG); the source
  rect is the whole buffer.
- NV12 support is probed by creating the converter **on the presenting
  adapter**. WARP cannot, so it stays on RGBA (`-rgba` forces RGBA as a control).

Measured 2026-08-12 (P6_findings/gpu-modes.csv): RGBA 4K60 0.9-25.7 fps
(transport-bound); NV12 4K60 49-52 fps whichever GPU decodes; Present 0-6 ms.
**The pixel format matters, the GPU choice does not.**

## Adapters and decoding

- `GPUPreference`: `.display` (default), `.amd`, `.nvidia`, `.software`
  (WARP), and `-both-gpu` (decode on NVIDIA with `-hwaccel cuda`, present on the
  display adapter). Matched by vendor ID through `EnumAdapters1`; an explicit
  adapter needs `D3D_DRIVER_TYPE_UNKNOWN`. Presenting from a non-display adapter
  makes DXGI copy every frame across PCIe.
- Decode is software by default; `-amd` -> `-hwaccel d3d11va`, `-nvidia` -> `cuda`.

## Root causes that can come back

- **Pipe size.** Foundation's `Pipe` on Windows calls `CreatePipe(..., 0)`: a
  buffer of a few KB. P6 makes its own pipe (two frames, capped at 32 MB) and
  `ReadFile`s into the mapped texture. A bigger buffer does not help (25 MB 49.9
  fps, 2 GB 45.3).
- **Per-frame `@Published` costs about 100 ms on WinUI**; publishing every
  frame capped playback at 7-8 fps. Status is published at 2 Hz (7697dbe6).
- **Closing a FileHandle inside its own readabilityHandler** is a same-queue
  `dispatch_sync` that traps (0xc000001d); close from another queue (8dc6380b).
- Child processes are started with `CREATE_NO_WINDOW` (`P6WindowlessProcess`)
  and tied to a Job Object with KILL_ON_JOB_CLOSE.

## Testing and capture

- Ready marker: `d3d11 surface: first present ok`.
- D3D/DComp content can capture black in a window capture; `videoshot.zsh`
  records the composited desktop with gdigrab.
- `actions/win/P6-transport-toggles.actions` needs a 6 s start: at 2 s the
  transport row had not moved down yet and every click seeked (2026-10-20).

## Open (checked 2026-10-24)

- The video area is a fixed 960x540 and does not follow the window.
- `.display` takes DXGI's default adapter with no WARP-to-hardware fallback
  (Mesh3D has one, 34677da8).
- No zero-copy decode; A/V sync is anchored at start only and drifts at 3x.
- No backend-agnostic video view in SwiftCrossUI.

---

# WinUI 上的 P6 影片:ffmpeg、Direct3D 11 與 SwapChainPanel

2026-10-24 依 Sources/WinUIBackend/D3D11VideoInterop.swift、testapp/P6.swift、testapp/P6_findings/、360bcad2、
84718ee6、b250da26、bafbc949、7697dbe6、8dc6380b、30f1d69c,以及 results.csv2(windows、winui、P6、2026-10-20)
寫成。

## 管線

ffmpeg 在**獨立行程**中解碼(沒有 Media Foundation)。原始影格經 pipe 傳來，直接讀進已 map 的 D3D11 staging
texture,再由 `SwapChainPanel` 內的 composition swap chain 顯示。聲音是另一個 `ffplay -nodisp -autoexit`。P6 只能
建成 WinUI;P6-v2 是 GTK 對應版([p6-v2-video-gtk.md](p6-v2-video-gtk.md))。

## 為何用 SwapChainPanel,並以原始 COM 驅動

- 子 HWND 的 swap chain 永遠看不見:XAML 透過 Direct Composition 合成，蓋在它上面(airspace 問題)。
- swift-winui 沒有 project SwapChainPanel,而它的包裝在 `try!` 後面延遲解析 COM 介面，會 trap(0xc000001d)。
  `RawSwapChainPanel` 透過 vtable 驅動面板，並預先做完所有 QueryInterface。
- 先 `CreateSwapChainForComposition`,再 `ISwapChainPanelNative::SetSwapChain`,後者**只能在 UI 執行緒**。Map、
  CopyResource 與 Present 在解碼執行緒上執行(D3D11 device 不是 SINGLETHREADED,immediate context 內部會序列化)。
- swap chain:2 個緩衝區、FLIP_SEQUENTIAL、STRETCH、ALPHA_MODE_IGNORE;3 個 staging texture;`Present(1, 0)`。
  緩衝區以實體像素計，用 `SetMatrixTransform(viewport DIP / 緩衝區像素)` 對應回去。
- WinUI 的 Canvas 回報 DesiredSize 為 0:沒有自己的 `sizeThatFits` 時，影片落在右下四分之一(360bcad2)。

## 讓 4K60 可行的是 NV12

NV12 放進 staging texture,複製到 DEFAULT 的對應 texture,再由 `ID3D11VideoProcessor` 轉換並縮放到 back buffer
(84718ee6)。

- 色彩空間必須指定：輸入 `YCBCR_STUDIO_G22_LEFT_P709`,輸出 `RGB_FULL_G22_NONE_P709`。設錯會得到泛白或綠色的
  畫面，而不是錯誤。
- 色度平面起點是 `rowPitch * height`;輸入 texture 需要 `D3D11_BIND_DECODER`(BIND_SHADER_RESOURCE 會得到
  E_INVALIDARG);來源矩形是整個緩衝區。
- 是否支援 NV12,是以**在負責 present 的 adapter 上**實際建立轉換器來探測。WARP 做不到，因此維持 RGBA
  (`-rgba` 強制 RGBA 作為對照)。

2026-08-12 量測(P6_findings/gpu-modes.csv):RGBA 4K60 0.9–25.7 fps(受限於傳輸);NV12 4K60 不論哪顆 GPU 解碼
都是 49–52 fps;Present 0–6 ms。**重要的是像素格式，不是 GPU 的選擇。**

## Adapter 與解碼

- `GPUPreference`:`.display`(預設)、`.amd`、`.nvidia`、`.software`(WARP),以及 `-both-gpu`(以
  `-hwaccel cuda` 在 NVIDIA 上解碼、在顯示用 adapter 上 present)。透過 `EnumAdapters1` 以 vendor ID 配對；指定
  adapter 時需用 `D3D_DRIVER_TYPE_UNKNOWN`。從非顯示用 adapter present,DXGI 會把每一幀經 PCIe 複製過去。
- 預設軟體解碼;`-amd` -> `-hwaccel d3d11va`,`-nvidia` -> `cuda`。

## 可能再發生的根本原因

- **Pipe 大小。** Windows 上 Foundation 的 `Pipe` 呼叫 `CreatePipe(..., 0)`:緩衝區只有幾 KB。P6 自建 pipe(兩幀
  大小，上限 32 MB),並以 `ReadFile` 直接讀進已 map 的 texture。更大的緩衝區沒有幫助(25 MB 49.9 fps,2 GB 45.3)。
- **WinUI 上每次 `@Published` 約 100 ms**;每幀發布讓播放卡在 7–8 fps。狀態改為 2 Hz 發布(7697dbe6)。
- **在 FileHandle 自己的 readabilityHandler 裡關閉它**,是同一佇列上的 `dispatch_sync`,會 trap(0xc000001d);
  要從另一個佇列關閉(8dc6380b)。
- 子行程以 `CREATE_NO_WINDOW` 啟動(`P6WindowlessProcess`),並綁到帶 KILL_ON_JOB_CLOSE 的 Job Object。

## 測試與擷取

- 就緒標記:`d3d11 surface: first present ok`。
- D3D/DComp 內容在視窗擷取中可能是黑的;`videoshot.zsh` 以 gdigrab 錄下合成後的桌面。
- `actions/win/P6-transport-toggles.actions` 需要 6 秒的起始等待:2 秒時傳輸列尚未下移，每次點擊都變成跳轉
  (2026-10-20)。

## 未解決(檢查於 2026-10-24)

- 影片區域固定為 960x540,不隨視窗變化。
- `.display` 採用 DXGI 的預設 adapter,沒有從 WARP 改用硬體的後備(Mesh3D 有,34677da8)。
- 沒有零複製解碼；影音同步只在開始時對齊，3 倍速時會漂移。
- SwiftCrossUI 沒有與 backend 無關的影片 view。
