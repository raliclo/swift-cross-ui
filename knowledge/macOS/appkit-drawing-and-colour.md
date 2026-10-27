# AppKitBackend: colour, shapes, effects and frame timing

## Colours are sRGB

`Color.Resolved.nsColor` is `NSColor(srgbRed:...)` and `cgColor` is
`CGColor(srgbRed:...)`. Until 2026-10-14 they were `calibratedRed` and
`CGColor(red:green:blue:alpha:)`, which are Generic RGB: P95's swatch
(0.4, 0.9, 1) read 117 234 255 in an sRGB capture instead of 101 230 255
(c8a533e8, a6d20dcc; Sources/AppKitBackend/AppKitBackend+Color.swift).
Compare colours only in sRGB captures; GtkBackend on macOS needed the same
fix on its NSWindow (see `gtk-css-and-metrics.md`).

## Shapes and gradients

- **Strokes outside the shape.** SwiftUI draws the half of a stroke that lies
  outside the shape. The path view clipped to its bounds, so P43's gradient
  ring was cut flat on four sides at 120 pt; it is 134 x 134 pt now, the same
  as GTK (results.csv2: mac, P43, 2026-10-19).
- **Hit testing where drawn.** `NSBezierPathView.hitTest` answered for its
  whole frame, so a field-border overlay took every click on P41's row
  steppers (abcc9105, 2026-10-20). A geometric-effect container was hit-tested
  at its layout frame, so P108's thrown card could only be picked up at its
  old position (results.csv2: mac, P108, 2026-10-19).
- **Gradient redraw.** `LinearGradientView` and `RadialGradientView` redrew
  only on a size change, so a changed gradient at the same size stayed as it
  was (P109, 2026-10-19).
- **Angular gradients** use `CGContextDrawConicGradient` (macOS 14+); the
  720-wedge fallback for older systems has not been run
  (AppKitBackend+PathGradients.swift; P112, 2026-10-20).
- **Radial radii are points**, as in SwiftUI, not fractions of the shorter
  side (P112, 2026-10-20).

## Effects

- `VisualEffects` is one `CIFilter` chain on a layer-backed container, rebuilt
  on every call; adding to `layer.filters` would compound the effect on each
  update (AppKitBackend+VisualEffects.swift).
- `grayscale` through `CIColorMonochrome` in Core Image's linear space is the
  reference grey for every backend (queue item 24b, 2026-10-16; 5c5f29b2).
- `GeometricEffects` is a `CATransform3D`. The incoming matrix is top-left,
  y-down; a CALayer under a non-flipped view is bottom-left, y-up, and
  transforms about its centre, so the matrix is converted twice. A wrong
  conversion still looks like *a* transform, off by a reflection or half the
  view (AppKitBackend+GeometricEffects.swift).

## Frame clock

`FrameClocks` uses `NSView.displayLink` on macOS 14 and later, locked to the
display (120 Hz on ProMotion), and a fixed 60 Hz timer below 14
(AppKitBackend+FrameClock.swift). Measured: 121 ticks in 2.00 s, median gap
16.7 ms on a 60 Hz display (P64, 2026-09-10); P96 60.3 fps driven, 60.0 fps
dots alone (2026-10-22).

## Graphics adapters

`GraphicsAdapters` lists Metal devices, system default first (`name`,
`isRemovable`, `isLowPower`). Choosing one records it for the app's own GPU
work; it does not move the window, which the window server composites on the
GPU driving its display (AppKitBackend+GraphicsAdapters.swift; P68,
2026-09-11).

## Limits

- The conic-gradient fallback below macOS 14 and the 60 Hz timer path are
  unexercised in any recorded run; the Mac checked on 2026-10-24 runs macOS 27.

---

# AppKitBackend:顏色、形狀、效果與幀時序

## 顏色一律 sRGB

`Color.Resolved.nsColor` 是 `NSColor(srgbRed:...)`,`cgColor` 是 `CGColor(srgbRed:...)`。2026-10-14 之前它們是
`calibratedRed` 與 `CGColor(red:green:blue:alpha:)`,也就是 Generic RGB:P95 的色塊 (0.4, 0.9, 1) 在 sRGB 擷圖中讀到
117 234 255,而非 101 230 255(c8a533e8、a6d20dcc;Sources/AppKitBackend/AppKitBackend+Color.swift)。比較顏色只能用
sRGB 擷圖;macOS 上的 GtkBackend 也需要對它的 NSWindow 做同樣的修正(見 `gtk-css-and-metrics.md`)。

## 形狀與漸層

- **形狀外側的筆畫。** SwiftUI 會畫出筆畫落在形狀外的那一半。path view 原本裁切到自己的邊界，所以 P43 的漸層圓環在 120 pt
  處四邊被切平;現在是 134 x 134 pt,與 GTK 相同(results.csv2:mac、P43、2026-10-19)。
- **只在畫到的地方接受點擊。** `NSBezierPathView.hitTest` 原本對整個 frame 回應，於是欄位邊框的覆蓋層吃掉了 P41 那一列
  加減鈕的每一次點擊(abcc9105,2026-10-20)。幾何效果容器原本以排版 frame 做 hit test,P108 被拋出去的卡片只能在舊位置拿起
  (results.csv2:mac、P108、2026-10-19)。
- **漸層重繪。** `LinearGradientView` 與 `RadialGradientView` 只在大小改變時重繪，大小不變而漸層改變時畫面不動(P109,2026-10-19)。
- **角度漸層**使用 `CGContextDrawConicGradient`(macOS 14+);給舊系統的 720 扇形 fallback 還沒跑過
  (AppKitBackend+PathGradients.swift;P112,2026-10-20)。
- **放射漸層的半徑以點為單位**,與 SwiftUI 相同，不是短邊的比例(P112,2026-10-20)。

## 效果

- `VisualEffects` 是 layer-backed 容器上的一條 `CIFilter` 鏈，每次呼叫都重建;若是往 `layer.filters` 追加，效果會在每次更新時
  疊加(AppKitBackend+VisualEffects.swift)。
- 在 Core Image 線性空間中以 `CIColorMonochrome` 做的 `grayscale`,是所有 backend 的基準灰(queue 第 24b 項,2026-10-16;5c5f29b2)。
- `GeometricEffects` 是 `CATransform3D`。傳入的矩陣以左上為原點、y 向下;非翻轉 view 底下的 CALayer 以左下為原點、y 向上，
  並繞中心點變換，所以矩陣要轉換兩次。轉錯時看起來仍然「是個變換」,只是差了一次鏡射或半個 view
  (AppKitBackend+GeometricEffects.swift)。

## Frame clock

`FrameClocks` 在 macOS 14 以上使用 `NSView.displayLink`,跟著螢幕更新率(ProMotion 為 120 Hz);14 以下用固定 60 Hz 計時器
(AppKitBackend+FrameClock.swift)。量測:60 Hz 螢幕上 2.00 秒 121 次 tick,間隔中位數 16.7 ms(P64,2026-09-10);
P96 driven 60.3 fps、只有圓點時 60.0 fps(2026-10-22)。

## 繪圖介面卡

`GraphicsAdapters` 列出 Metal 裝置，系統預設排第一(`name`、`isRemovable`、`isLowPower`)。選定之後只記錄給 app 自己的 GPU
工作使用;不會移動視窗——視窗由 window server 在驅動該螢幕的 GPU 上合成(AppKitBackend+GraphicsAdapters.swift;P68,2026-09-11)。

## 限制

- macOS 14 以下的 conic 漸層 fallback 與 60 Hz 計時器路徑沒有紀錄顯示跑過;2026-10-24 檢查的這台 Mac 是 macOS 27。
