# Letting a shape be filled with something other than a flat colour

`Circle().fill(LinearGradient(...))` does not compile, and the reason is one
function signature. This is task #66, and it is the thing #31 (`ShapeStyle`)
is waiting on.

`Circle().fill(LinearGradient(...))` 無法編譯，原因就在一個函式簽章上。此為任務 #66，也是 #31
（`ShapeStyle`）正在等待的前置。

## Status

**Design only. Nothing here is implemented.** Written 2026-09-01. Every claim
about existing code below was checked against the tree that day and carries a
`file:line`; anything not checked is marked as an assumption.

**僅為設計，未實作任何內容。** 2026-09-01 撰寫。以下關於既有程式碼的每一項陳述都在當日對照過原始碼
並附上 `file:line`；未經查證者均標示為假設。

## What exists today

`BackendFeatures.Paths` requires exactly one drawing call
(`Sources/SwiftCrossUI/Backend/BackendFeatures/Paths.swift:56-62`):

```swift
func renderPath(
    _ path: Path,
    container: Widget,
    strokeColor: Color.Resolved,
    fillColor: Color.Resolved,
    overrideStrokeStyle: StrokeStyle?
)
```

`Color.Resolved` is four `Float`s — red, green, blue, opacity
(`Values/Color/Color+Resolved.swift:3-11`). There is no case, no existential,
no brush. **Two flat colours is the whole vocabulary**, and it is the signature
that limits it, not any backend:

| Backend | Path drawn with | Could it take a gradient? |
|---|---|---|
| Gtk | Cairo, `cairo_pattern_create_rgba` at `GtkBackend.swift:3564`, `:3574` | Yes, directly — `cairo_pattern_create_linear/radial/mesh/for_surface` replaces those two calls |
| WinUI | XAML `Path.Fill`/`.Stroke` = `SolidColorBrush`, `WinUIBackend.swift:2414-2415` | Yes — those are `Brush` properties; `LinearGradientBrush` is already used at `WinUIBackend+Gradient.swift:35` |
| Android | `Paint.setColor`, `AndroidBackend+Paths.swift:73-74` | Yes — `Paint.setShader` |
| AppKit | `NSColor.set()` + `path.fill()`, `AppKitBackend+Path.swift:205-210` | Needs restructuring: `NSGradient.draw(in:)` under `path.addClip()` |
| UIKit | `CAShapeLayer.fillColor`, `UIKitBackend+Path.swift:168-169` | Hardest — `CGColor` only; needs a `CAGradientLayer` masked by the shape |

Three of the five could take a richer fill with a local change. The signature is
what stops all five.

**Gradients do exist, and they bypass this entirely.** `LinearGradient`,
`RadialGradient` and `AngularGradient` are `ElementaryView`s with their own
backend protocols (`BackendFeatures/Gradients/`), whose vocabulary is
`createLinearGradientWidget() -> Widget`. A gradient is therefore *a whole
rectangular widget*, and **there is no way to clip one to a `Circle()`**. That
is the user-visible shape of the gap.

**`ShapeStyle` does not exist.** `grep ShapeStyle Sources/` returns nothing. The
only styling entry points take a concrete `Color`
(`Views/Shapes/StyledShape.swift:49-55`).

## The constraint that decides the design

**Changing `renderPath`'s signature breaks five backends at once, and two of
them cannot be compiled on this machine.** AppKitBackend and UIKitBackend need
a Mac; that is the same wall as #59. A signature change would therefore be
written blind for 40% of the implementations and land as a build break for
whoever pulls next.

So the design has to be **additive**: existing backends keep compiling
untouched, and each opts in when someone can build and see it.

**改動 `renderPath` 的簽章會同時破壞五個 backend，其中兩個在本機無法編譯。** AppKitBackend 與
UIKitBackend 需要 Mac，與 #59 是同一道牆。因此簽章變更等於為其中 40% 的實作盲寫，並且會讓下一個
pull 的人拿到一個建置失敗。設計因此必須是**加法式的**：既有 backend 原封不動仍可編譯，各自在有人
能建置並親眼確認時再選擇加入。

## Design

### 1. A resolved style value, not a protocol yet

SwiftUI's `ShapeStyle` is a protocol with a large conformance surface. Adding
that first would be building the wide part before the narrow part works. Start
with the value the backend actually needs:

```swift
public enum ResolvedFillStyle {
    case color(Color.Resolved)
    case linearGradient(Gradient, startPoint: UnitPoint, endPoint: UnitPoint)
    case radialGradient(Gradient, center: UnitPoint, startRadius: Double, endRadius: Double)
}
```

`Gradient` already exists (`Values/Gradient.swift:4`) with stops and locations,
and `RadialGradient` already exposes `@_spi(Backends) var adjustedStops`
(`Views/Gradients/RadialGradient.swift:98`), so the backends already have the
shape of data they need. Angular is deliberately left out of the first cut:
XAML has no conic brush, which is why `WinUIBackend+AngularGradient.swift`
exists as a workaround, and dragging that into the path layer would make the
first step carry the hardest case.

### 2. An additive requirement with a fallback default

```swift
extension BackendFeatures.Paths {
    func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?
    ) {
        // Default: flatten each style and call the existing two-colour method,
        // so a backend that has not opted in still compiles and still draws.
    }
}
```

**The fallback must be loud.** Project policy is that a silent no-op is not an
acceptable implementation of an advertised feature, and flattening a gradient to
one colour is a visible downgrade, not a no-op — it draws *something*, which is
worse, because it looks like a rendering bug rather than a missing feature. So
the default implementation logs once per backend through the mechanism
`GtkBackend.scrollBarWidth` already uses for exactly this reason
(`GtkBackend.swift:96-101`: "otherwise this branch is a number no one can see").

Flatten to the **midpoint stop**, not the first: a two-stop gradient flattened
to its first colour looks like the gradient was ignored, whereas the midpoint
reads as an approximation. Assumption, not measured.

### 3. Opt in where it can be seen

Order matters, and it is dictated by what can be verified here:

1. **GtkBackend** — one call site each for fill and stroke, and WSL builds a
   test app in seconds. Verify on WSLg with a capture.
2. **WinUIBackend** — assign a `LinearGradientBrush` instead of a
   `SolidColorBrush`. Verifiable here too, at the cost of a ~20 minute build.
3. **AppKit, UIKit, Android** — leave on the fallback. They are not broken by
   this and can be done by whoever can run them. Record in the coverage matrix
   that they degrade, so it is not mistaken for "implemented".

### 4. The public API

```swift
extension StyledShape {
    public func fill(_ gradient: LinearGradient) -> some StyledShape
    public func fill(_ gradient: RadialGradient) -> some StyledShape
}
```

Overloads rather than a `ShapeStyle` protocol, for the same reason as §1. The
protocol is #31 and should be introduced once something concrete is behind it —
`DatePickerStyle` and `ListStyle` were both converted to protocols *after* they
did something (#63, #64), and that order worked.

## Verification

A new `Pn` app is the wrong first step: this needs a picture, not a number.

1. Extend an existing shapes app (or add one) with a `Circle().fill(linear)`,
   a `RoundedRectangle` with a gradient stroke, and a flat-colour control shape
   beside them.
2. Build for GTK on WSL, capture with `screenshot.zsh -w`, and check by eye that
   the gradient is **clipped to the circle** — that is the whole point, and it is
   the one thing the existing widget-based gradients cannot do.
3. Check the control shape is unchanged, which is what proves the additive
   default did not disturb the flat path.
4. Run the same app on a backend still using the fallback and confirm the log
   line appears and the shape draws in the midpoint colour.
5. Only then record it in `matrix_coverage/coverage-matrix.csv2`, per backend,
   distinguishing implemented from degraded.

## What this does not do

- No angular/conic fills (see §1).
- No image or pattern fills, no materials.
- No dashed strokes: `StrokeStyle` carries only width, cap and join, confirmed
  by the exhaustive switches at `GtkBackend.swift:3536-3560` and
  `AppKitBackend+Path.swift:28-50`. Separate task.
- Does not touch `fillRule`, which is already plumbed everywhere except AppKit
  (`Values/Path.swift:281`; AppKit never sets `NSBezierPath.windingRule`, which
  is a real bug but a different one).

---

# The Mac half: AppKit and UIKit

Written 2026-09-01, after GtkBackend was implemented and verified
(`b0a93243`). **Design only, by someone who cannot compile either of these.**
Everything below is derived from the code in this tree plus the two
frameworks' documented behaviour. Where it is an assumption it says so. If the
compiler disagrees with this document, this document is what is wrong.

2026-09-01 撰寫，於 GtkBackend 實作並驗證之後。**僅為設計，且撰寫者無法編譯這兩者。** 以下推導自
本 tree 的現有程式碼與兩個框架的既有文件行為；屬於假設之處均已標示。若編譯器與本文不一致，錯的
是本文。

## Run P43 before writing anything

Nothing is broken on Mac today. Both backends take the additive default, so
`Circle().fill(gradient)` compiles and draws — a flat circle in the gradient's
midpoint colour, with one warning logged saying exactly that.

`testapp/P43.swift` already exists and uses only cross-platform API, so
building and capturing it on macOS gives the "before" picture: middle circle
green, left circle flat purple instead of a red-to-blue ramp. **If the left
circle is already a ramp, stop — something else is true and this design is
moot.**

Mac 上目前沒有東西是壞的：兩個 backend 都取得加法式預設，會畫出漸層中點顏色的平面色圓形並記錄
一次警告。請先跑 P43 取得「之前」的畫面。

## The obstacle, and the way around it

The direct route is different on each and awkward on both.

- **AppKit** draws with `fillColor.set(); path.fill()`
  (`AppKitBackend+Path.swift:7-18`). A gradient is not a colour, so this
  becomes save-state / clip / draw-gradient / restore.
- **UIKit** has nowhere to put one at all: `PathWidget` wraps a `CAShapeLayer`
  (`UIKitBackend+Path.swift:4-12`) whose `fillColor` is `CGColor` and nothing
  else. The direct route means replacing the layer with a custom `draw(_:)`,
  and `CAShapeLayer` currently carries `fillRule` (`:56`, `:136`), so that has
  to be reproduced too.

**The workaround: render the gradient into an image and wrap it as a pattern
colour.** `NSColor(patternImage:)` and `UIColor(patternImage:)` both produce an
ordinary colour, so:

- AppKit's four-line `draw` does not change at all.
- UIKit keeps `CAShapeLayer`; `fillColor` takes
  `UIColor(patternImage:).cgColor`. No layer replacement, `fillRule` untouched.
- **Stroke gradients come free.** `strokeColor` is also just a colour, and the
  pattern is clipped to whatever region is being painted — which for a stroke
  is the stroke itself. No stroked-outline geometry needed.

That last point is worth pausing on, because it removes the trap this document
would otherwise have to warn about: the direct route invites clipping to
`path.addClip()` for a *stroke*, which yields a shape **filled** with a
gradient where an outline was asked for — a plausible-looking wrong answer
rather than an error. With a pattern colour the question never arises.

**繞過的方法：把漸層算繪成一張圖，包成 pattern colour。** `NSColor(patternImage:)` 與
`UIColor(patternImage:)` 產生的都是一個普通的顏色，因此 AppKit 的四行 `draw` 完全不必動，UIKit
也能保留 `CAShapeLayer`、不必重現 `fillRule`。**描邊漸層也一併免費取得**——`strokeColor` 同樣只是
一個顏色，而 pattern 會被裁切到正在繪製的區域，對描邊而言那就是描邊本身。這一點順帶消除了直接
路線會招致的陷阱：對**描邊**使用 `path.addClip()` 會得到「填滿漸層的形狀」而非漸層輪廓——那是一個
看似合理的錯誤答案，而不是一個錯誤。

## What the workaround costs, stated so it is a choice

- **Resolution.** The image must be rendered at the backing scale or it is
  blurry on Retina. `UIGraphicsImageRenderer` uses the screen scale by default;
  on AppKit, give the `NSImage` a point size and back it with a CGImage at
  `window.backingScaleFactor`. **This is the one most likely to be got wrong
  and to look merely "a bit soft" rather than broken.**
- **Pattern origin.** Pattern colours tile from the *view's* origin, not the
  path's. Render the image at the **widget's** size, not the path's bounds, and
  place the gradient within it using the path's bounds — then it lines up by
  construction and never tiles visibly. Getting this wrong shifts the gradient
  by the path's offset, which on a centred shape looks like the gradient
  "starting in the wrong place".
- **An allocation per path per resize**, redone when the size or the gradient
  changes. Paths are already redrawn on update, so this is a new cost but not a
  new frequency.
- **Quality.** A pattern image is resampled; a real `CGGradient` under a clip is
  not. At these sizes the difference should not be visible, but this is the
  reason the direct route stays the better long-term answer.

假設，非實測：以上四點皆推導自框架文件，未在 Mac 上驗證。

## If the workaround is rejected, the direct route

Kept because it is the better end state and the traps are worth recording once.

- **AppKit stroke:** clip to the stroked outline, not the fill.
  `path.cgPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:)` gives it;
  `NSBezierPath` has no equivalent. **`NSBezierPath.cgPath` is macOS 14+** —
  check the deployment target before relying on it.
- **`NSGradient.draw` needs `[.drawsBeforeStartingLocation,
  .drawsAfterEndingLocation]`.** Without them it paints only between the two
  points and leaves the rest of the clip untouched, so a circle comes out with
  pale bands at top and bottom — which reads as the clipping being broken.
- **The y axis.** `updatePath`'s doc says `bounds` is passed to backends
  *because AppKit's y axis is flipped*. Check whether the path is already
  flipped when built before flipping the gradient too — doing both cancels out,
  and the gradient then looks right while everything else is upside down.
- **UIKit:** `context.replacePathWithStrokedPath()` gives the stroke outline in
  one call, which is the thing AppKit needs CGPath for. Do the flat case first
  and confirm P43's control circle is unchanged **before** adding the gradient,
  so a regression in the flat path is visible on its own.

## While you are in AppKitBackend+Path.swift

It **never sets `NSBezierPath.windingRule`**, so `fillRule` is silently dropped
there. Every other backend applies it — Gtk `GtkBackend.swift:3527-3534`, UIKit
`UIKitBackend+Path.swift:56`, WinUI `WinUIBackend.swift:2196-2202`, Android
`AndroidBackend+Paths.swift:43-50`. A real, separate bug; one line, in code
this work already touches. Its own commit.

## Verification

`testapp/P43.swift` is the test and needs no changes. Capture the window and
read three things:

1. **left circle** — a round red-to-blue ramp. Square means the clip or the
   pattern origin is wrong; flat purple means still on the fallback.
2. **middle circle** — plain green. The control. If the flat path broke, this is
   where it shows, and it matters as much as the gradient working.
3. **right rectangle** — the same ramp in a square, which confirms direction and
   extents rather than just clipping.

GTK reference to compare against:
`testapp/output/screenshots/p43-gradient-20260901-212410.png`.

**Then add a gradient *stroke* case to P43 before calling this done.** The app
only exercises fills today, so the stroke behaviour is untested on every
backend — including GtkBackend, which is already implemented.

**在宣告完成之前，請先為 P43 加上漸層「描邊」的案例。** 目前該 app 只測試填充，因此描邊行為在
每一個 backend 上都未經測試——包含已經實作完成的 GtkBackend。
