# SwiftCrossUIMetal: the mesh renderer on AppKit and UIKit

## What

`Sources/SwiftCrossUIMetal/Mesh3DMetalView.swift` is the renderer behind
`BackendFeatures.Mesh3DViews` for both Apple backends: one `MTKView`
subclass, one set of shaders, buffer packing and camera arithmetic
(fe144f76). It is declared for every host in Package.swift because SwiftPM
cannot make a target conditional; its file is wrapped in
`#if canImport(MetalKit)`, so on Linux and Windows it compiles to an empty
module. Only AppKitBackend and UIKitBackend depend on it.

## Decisions that are easy to undo by mistake

- **Drawn on request, not on its own timer.** `enableSetNeedsDisplay = true`
  is the line that stops the view drawing by itself; with it false the view
  drew 90 frames in 1.5 s after the frame clock had stopped, with it true 1
  (P72, 2026-09-19). The framework's `FrameClocks` is the only clock.
- **Vertices uploaded as nine packed floats.** `SIMD3<Float>` has a stride of
  16, so `Mesh3DVertex` is 48 bytes while the shader's three `packed_float3`
  are 36. Copying the Swift struct draws a scatter of stretched triangles
  that looks like a projection bug (measured 2026-09-19).
- **Shaders compiled from source text at run time**, not from a `.metal` file:
  a default library would have to be found through `Bundle.module` from
  whichever bundle the library was linked into, which fails on one platform
  and not the other.
- **Geometry compared without transforms.** A mesh's transform is a uniform,
  so the upload is skipped when only transforms or the camera change; P72's
  60 Hz spinning cube uploads once.
- **Each index range names its mesh.** Until 2026-10-05 ranges were matched
  by position while an empty mesh got no range, which shifted every later
  mesh onto its predecessor's transform; line and point meshes made that
  common.
- **Opaque first, then translucent** meshes blended over them with no depth
  write (`Mesh3D.opacity`, 2d779a3e).
- **Depth range `.zeroToOne`** for Metal; the GL renderers use
  `.minusOneToOne`. The matrices themselves live in
  `Sources/SwiftCrossUI/Views/Mesh3DMatrix.swift` (since 2026-09-22) so
  Android uses the same conventions.
- **Snapshots render one more frame into an owned `.managed` texture**, not
  the drawable: a drawable's texture is recycled after presentation and is
  `framebufferOnly`. The managed texture must be synchronised before
  `getBytes`, or the read returns zeroes (a plausible black image). BGRA is
  swapped to RGBA (c6a33f38).

## Evidence

P76's orthographic and perspective captures (results.csv2: mac, P76,
2026-10-05); P72 frame counts read twice to show the pipeline runs, not just
compiles; P86 translucent meshes captured 2026-10-15.

## Limits

- The renderer's render-time measurement waits for the command buffer, so a
  scene that asks for it (`Mesh3DScene.measuresRenderTime`) gives up frame
  overlap.

---

# SwiftCrossUIMetal:AppKit 與 UIKit 上的網格算繪器

## 是什麼

`Sources/SwiftCrossUIMetal/Mesh3DMetalView.swift` 是兩個 Apple backend 上 `BackendFeatures.Mesh3DViews` 背後的算繪器：一個
`MTKView` 子類別、一套著色器、緩衝區打包與相機運算(fe144f76)。它在 Package.swift 中對所有主機宣告，因為 SwiftPM 無法讓 target
帶條件;檔案整份包在 `#if canImport(MetalKit)` 中，所以在 Linux 與 Windows 上編成空模組。只有 AppKitBackend 與 UIKitBackend 依賴它。

## 容易被不小心改回去的決定

- **有要求才畫，不靠自己的計時器。** 讓 view 不自行繪製的是 `enableSetNeedsDisplay = true` 這一行;設成 false 時，frame clock
  停止後 1.5 秒內畫了 90 幀，設成 true 時只有 1 幀(P72,2026-09-19)。框架的 `FrameClocks` 是唯一的時鐘。
- **頂點以九個緊密排列的 float 上傳。** `SIMD3<Float>` 的 stride 是 16,所以 `Mesh3DVertex` 是 48 位元組，而著色器的三個
  `packed_float3` 是 36。直接複製 Swift struct 會畫出一團拉長的三角形，看起來像投影錯誤(2026-09-19 實測)。
- **著色器在執行時從原始碼文字編譯**,不用 `.metal` 檔：預設 library 必須經 `Bundle.module` 從該 library 被連結進去的 bundle
  找出來，這在一個平台上可行、在另一個平台上失敗。
- **比較幾何時不含變換。** 網格的變換是 uniform,只有變換或相機改變時略過上傳;P72 以 60 Hz 旋轉的立方體只上傳一次。
- **每段索引範圍標明它所屬的網格。** 2026-10-05 之前範圍依位置對應，而空網格沒有範圍，於是之後每個網格都套用前一個的變換;
  線與點網格讓這種情況變得常見。
- **先畫不透明網格**,再把半透明網格混合在上面、不寫入深度(`Mesh3D.opacity`,2d779a3e)。
- Metal 用 **深度範圍 `.zeroToOne`**;GL 算繪器用 `.minusOneToOne`。矩陣本身自 2026-09-22 起放在
  `Sources/SwiftCrossUI/Views/Mesh3DMatrix.swift`,讓 Android 使用相同慣例。
- **快照會多畫一幀到自己擁有的 `.managed` texture**,而不是讀 drawable:drawable 的 texture 在呈現後會被回收，且是
  `framebufferOnly`。managed texture 在 `getBytes` 之前必須同步，否則讀到全零(一張看似合理的黑圖)。BGRA 要換成 RGBA
  (c6a33f38)。

## 證據

P76 的正交與透視擷圖(results.csv2:mac、P76、2026-10-05);P72 的幀數讀兩次，證明管線在跑而不只是編得過;
P86 半透明網格於 2026-10-15 擷圖。

## 限制

- 算繪耗時量測會等待 command buffer,所以要求量測的場景(`Mesh3DScene.measuresRenderTime`)會失去幀與幀之間的重疊。
