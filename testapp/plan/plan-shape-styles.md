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
