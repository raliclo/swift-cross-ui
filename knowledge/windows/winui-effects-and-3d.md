# WinUIBackend: visual effects, gradients, SVG text and Mesh3D

Written 2026-10-24 from Sources/WinUIBackend, Sources/WinUIInterop, commits
1d47d395, 8d018f3e, a54893b9, c1a18b4e, 34677da8, a94c68af, and results.csv2
(windows, winui: P39 2026-10-19; P72, P76, P77 2026-10-07; P85, P86, P112
2026-10-20).

## Visual effects are a Win2D effect graph

- Blur is `GaussianBlurEffect`; saturation and brightness are
  `ColorMatrixEffect` (Win2D `SaturationEffect` rejects values above 1 with
  E_INVALIDARG); hue rotation is `HueRotationEffect`; opacity alone takes a fast
  path.
- **Contrast** is a linear colour matrix. Win2D's `ContrastEffect` gave nearly
  the control colour (16,147,200 against 93,137,154 by the formula; 1d47d395).
- **Grayscale** is AppKit's linear-light grey with an amount (decode,
  luminance, overlay against 0.5 grey, encode). Win2D's `GrayscaleEffect` has no
  amount, so `grayscale(0.5)` drew fully grey. Composition needs a tree, so the
  upstream is built once per branch (8d018f3e; P39 within 2 levels).
- testapp/todo/todo_winUI.md's "Win2D types don't exist" is stale.

## Gradients and text

- `RadialGradient` radii are in points; `AngularGradient` is a
  `ConicGradientBrush` (a `XamlCompositionBrushBase` over a
  `CompositionDrawingSurface`), for shape fills, strokes and text (a54893b9,
  P112).
- SVG text: DirectWrite layout (system font fallback) to outline geometry,
  filled or stroked by Direct2D on a WIC bitmap (`WinUIInterop/svg_text_mask.cpp`,
  c1a18b4e; P85 passes, Chinese included).
- Monospaced text uses Cascadia Mono, then Consolas, then Courier New.

## Mesh3D: Direct3D 11 in a SwapChainPanel

- `Mesh3DViews` draws with D3D11 into a `SwapChainPanel` (a94c68af,
  2026-10-07). P77: 1,002,001 vertices / 2,000,000 triangles in 30.1 ms on the
  RTX 4060, 76.7 ms on WARP.
- **Adapter:** when DXGI's default adapter is WARP (Basic Render Driver) while a
  hardware GPU exists, the GPU is chosen (34677da8). This happened with the AMD
  adapter disabled.
- **DPI:** a SwapChainPanel composes one buffer pixel per DIP. The swap chain is
  drawn at `XamlRoot.rasterizationScale` with the inverse
  `SetMatrixTransform`; without it the view was 1.25x too large and cut off
  (P86, 2026-10-20).
- `RenderTargetBitmap` cannot see swap-chain content, so snapshots read back
  from the D3D view.
- Translucent meshes: opacity in the pixel shader, a source-over blend, a depth
  state that tests without writing, opaque meshes first (P86).
- Resize: `setSize` must request a render, or the mesh does not redraw (P95).

---

# WinUIBackend:視覺效果、漸層、SVG 文字與 Mesh3D

2026-10-24 依 Sources/WinUIBackend、Sources/WinUIInterop、1d47d395、8d018f3e、a54893b9、c1a18b4e、34677da8、
a94c68af,以及 results.csv2(windows、winui:P39 2026-10-19;P72、P76、P77 2026-10-07;P85、P86、P112
2026-10-20)寫成。

## 視覺效果是 Win2D 效果圖

- 模糊用 `GaussianBlurEffect`;飽和度與亮度用 `ColorMatrixEffect`(Win2D 的 `SaturationEffect` 對大於 1 的值回
  E_INVALIDARG);色相旋轉用 `HueRotationEffect`;只有不透明度時走快速路徑。
- **對比**是線性色彩矩陣。Win2D 的 `ContrastEffect` 幾乎得到對照色(16,147,200,公式值為 93,137,154;1d47d395)。
- **灰階**是 AppKit 的線性光灰並帶強度(解碼、亮度、與 0.5 灰疊加、編碼)。Win2D 的 `GrayscaleEffect` 沒有強度，
  所以 `grayscale(0.5)` 畫成全灰。合成需要樹狀結構，所以上游在每個分支各建一份(8d018f3e;P39 誤差在 2 階內)。
- testapp/todo/todo_winUI.md 的「Win2D 型別不存在」已過時。

## 漸層與文字

- `RadialGradient` 半徑以 point 為單位;`AngularGradient` 是 `ConicGradientBrush`(在 `CompositionDrawingSurface`
  上的 `XamlCompositionBrushBase`),用於形狀填色、描邊與文字(a54893b9,P112)。
- SVG 文字:DirectWrite 排版(系統字型後備)轉成外框幾何，由 Direct2D 在 WIC bitmap 上填色或描邊
  (`WinUIInterop/svg_text_mask.cpp`,c1a18b4e;P85 通過，中文亦然)。
- 等寬文字依序用 Cascadia Mono、Consolas、Courier New。

## Mesh3D:SwapChainPanel 裡的 Direct3D 11

- `Mesh3DViews` 以 D3D11 畫進 `SwapChainPanel`(a94c68af,2026-10-07)。P77:1,002,001 個頂點 / 2,000,000 個三角形，
  在 RTX 4060 上 30.1 ms,WARP 上 76.7 ms。
- **Adapter:**DXGI 預設 adapter 是 WARP(Basic Render Driver)而存在硬體 GPU 時，改選 GPU(34677da8)。這發生在
  AMD 顯示卡被停用時。
- **DPI:**SwapChainPanel 以每 DIP 一個緩衝區像素合成。swap chain 以 `XamlRoot.rasterizationScale` 繪製，並套上反向
  的 `SetMatrixTransform`;少了它畫面大 1.25 倍且被裁掉(P86,2026-10-20)。
- `RenderTargetBitmap` 看不到 swap chain 的內容，所以快照從 D3D view 讀回。
- 半透明 mesh:不透明度放在 pixel shader、source-over 混色、只測試不寫入的深度狀態、不透明的 mesh 先畫(P86)。
- 改變大小:`setSize` 必須要求重繪，否則 mesh 不會重畫(P95)。
