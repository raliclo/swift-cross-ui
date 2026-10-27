# Visual effects and colour on UIKitBackend

Why blur, saturation and similar effects are rendered through Core Image on
iOS, and the colour-space fix that made iOS colours match. Checked against
UIKitBackend+VisualEffects.swift and queue.md item 20 on 2026-10-24.

## `CALayer.filters` does nothing on iOS

- The first implementation copied AppKit's: a `[CIFilter]` on
  `view.layer.filters`. The property exists in both SDKs; only the AppKit
  compositor reads it.
- **Measured, not assumed** (iPhone 16 simulator, 2026-09-02, P39: one angular
  gradient drawn nine times, one effect each): `opacity 0.35` faded; `blur 3`,
  `saturation 2.5`, `brightness 0.4`, `grayscale 1` and `hueRotation 120` were
  pixel-identical to the control.

## How it is drawn now

1. `CALayer.render(in:)` draws the live child into a bitmap.
2. A `CIFilter` chain runs over the bitmap.
3. The result becomes the contents of a layer over the child, and the child is
   hidden with an empty `CALayer` mask. Not `alpha`/`isHidden`: `hitTest` skips
   alpha <= 0.01, so the child would stop taking touches.

`opacity` alone does not take this path.

## Limits

- The visible pixels are a rendering taken at the last layout. A state change
  reaches the screen (every SwiftCrossUI size or position write re-renders),
  but an animation run by Core Animation inside a filtered container freezes at
  whatever frame the last layout caught.
- Effects are computed on sRGB values, as Android and GTK (cef23e11,
  2026-10-10). `grayscale` is the exception: linear-light grey with a hand-made
  sRGB curve, to match AppKit's `CIColorMonochrome` (5c5f29b2, 2026-10-16):
  (255, 103, 49) -> 102, mid grey 127 -> 85.

## Colour: Generic RGB vs sRGB (fixed 2026-10-16)

- **Symptom.** P95's `LinearGradient` of (0.8, 0.3, 0.25) to itself read
  216 104 88 beside its 204 77 64 swatch on the iPhone 17 simulator.
- **Cause.** `Color.Resolved.cgColor` used `CGColor(red:green:blue:alpha:)`,
  which is Generic RGB. The gradient code was not at fault (an sRGB `CGGradient`
  and a `CAGradientLayer` both read 216 99 81). AppKit had the same conversion.
- **Fix.** `CGColor(srgbRed:...)`; the gradient reads 204 76 63 (a6d20dcc).
  Any new `CGColor` built from SwiftCrossUI components should use the sRGB
  initialiser.

## Gradients

- A gradient stroke draws in a sublayer sized to the stroked path, not in
  `draw(_:)`, which a view clips to its bounds; the P43 ring was cut flat
  before (2d74fbe2, 2026-10-19).
- `RadialGradient` radii as a shape style are points, as in SwiftUI
  (P112, 2026-10-20).

---

# UIKitBackend 的視覺效果與色彩

為什麼 iOS 上的模糊、飽和度等效果要經由 Core Image 繪製，以及讓 iOS 色彩對上的色彩空間修正。2026-10-24 對照
UIKitBackend+VisualEffects.swift 與 queue.md 第 20 項確認。

## `CALayer.filters` 在 iOS 上沒有作用

- 第一版照抄 AppKit:把 `[CIFilter]` 放在 `view.layer.filters`。兩個 SDK 都有這個屬性，但只有 AppKit 的合成器會讀它。
- **是實測，不是推測**(iPhone 16 模擬器,2026-09-02,P39:同一個角度漸層畫九次，各套一種效果):`opacity 0.35` 變淡了;
  `blur 3`、`saturation 2.5`、`brightness 0.4`、`grayscale 1` 與 `hueRotation 120` 與對照組逐像素相同。

## 現在的畫法

1. `CALayer.render(in:)` 把即時的子 view 畫進點陣圖。
2. 對點陣圖執行 `CIFilter` 鏈。
3. 結果成為蓋在子 view 上的圖層內容，子 view 以空的 `CALayer` mask 隱藏。不用 `alpha`/`isHidden`:`hitTest` 會略過
   alpha <= 0.01 的 view,子 view 就收不到觸控了。

單獨的 `opacity` 不走這條路。

## 限制

- 看得到的像素是上一次排版時的一張繪製結果。狀態改變會反映到畫面(SwiftCrossUI 每次寫入大小或位置都會重繪),但在套用
  濾鏡的容器內由 Core Animation 執行的動畫，會停在上一次排版捕捉到的那一幀。
- 效果以 sRGB 值計算，與 Android、GTK 相同(cef23e11,2026-10-10)。`grayscale` 例外：以線性光計算灰階並手動套用 sRGB
  曲線，以符合 AppKit 的 `CIColorMonochrome`(5c5f29b2,2026-10-16):(255, 103, 49) -> 102,中灰 127 -> 85。

## 色彩:Generic RGB 與 sRGB(2026-10-16 修正)

- **症狀。** 在 iPhone 17 模擬器上,P95 中 (0.8, 0.3, 0.25) 到自己的 `LinearGradient` 讀到 216 104 88,旁邊的色票是
  204 77 64。
- **原因。** `Color.Resolved.cgColor` 用的是 `CGColor(red:green:blue:alpha:)`,那是 Generic RGB。漸層程式碼沒有問題
  (sRGB 的 `CGGradient` 與 `CAGradientLayer` 都讀到 216 99 81)。AppKit 也有同樣的轉換。
- **修正。** 改用 `CGColor(srgbRed:...)`;漸層讀到 204 76 63(a6d20dcc)。今後任何由 SwiftCrossUI 分量建立的 `CGColor`
  都應該使用 sRGB 的初始化方法。

## 漸層

- 漸層描邊畫在大小與描邊路徑相同的子圖層中，而不是 `draw(_:)` 中(view 會把它裁到自己的範圍內);P43 的圓環之前被切平了
  (2d74fbe2,2026-10-19)。
- 作為 shape style 的 `RadialGradient` 半徑以點為單位，與 SwiftUI 相同(P112,2026-10-20)。
