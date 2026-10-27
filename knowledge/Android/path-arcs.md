# AndroidBackend: arcs continue the path

Fixed in c7961de5 (2026-10-24). Found on P110 in the iOS and Android Pairs
deck.

## Symptom

P110's fourth shape, an unfilled `Capsule` under a linear-gradient
`.foregroundStyle`, drew on Android as a "<" on the left and a sliver on the
right. iOS draws it whole, green to blue.

## Cause

`Capsule` is a `RoundedRectangle` with the corner radius at half the height.
When the radius is more than about 44% of a side (`rMin` in
RoundedRectangle.swift), the shape is built from four 90-degree `addArc` calls
joined by lines, with zero-length sides in a capsule's case.

AndroidBackend turned each `.arc` into `android.graphics.Path.addArc`. That
call **starts a new contour**. CoreGraphics' `addArc`, which the shapes are
written against, continues the current one. On Android the path came apart
into separate contours, each closed on its own when filled: wedges, and in a
capsule the "<" and the sliver.

Affected: every `Capsule`, and every `RoundedRectangle` whose radius is over
~44% of a side. Smaller radii take the cubic-curve branch and were never
affected, which is why P110's `RoundedRectangle(cornerRadius: 12)` looked
right.

## Fix

`Path.arcTo(left, top, right, bottom, startDegrees, sweepDegrees,
forceMoveTo: false)` continues the contour (AndroidBackend+Paths.swift).
`arcTo` takes the sweep modulo 360 degrees, so a full turn would vanish; it
goes in as two halves.

Verified: P110's capsule is whole on the api36b emulator, and P107's
line-semicircle-line track is unchanged (RUN DONE err=0.000 pt, track length
588.495).

---

# AndroidBackend:圓弧接續路徑

c7961de5(2026-10-24)修正，在 iOS and Android Pairs 簡報的 P110 上發現。

## 症狀

P110 的第四個圖形是套用線性漸層 `.foregroundStyle`、沒有填色的 `Capsule`,在 Android 上畫成左邊一個「<」、右邊一條細片。
iOS 畫得完整，由綠到藍。

## 原因

`Capsule` 是圓角半徑等於一半高度的 `RoundedRectangle`。半徑超過邊長約 44%(RoundedRectangle.swift 的 `rMin`)時，
形狀由四段 90 度的 `addArc` 以直線相接組成，膠囊的側邊直線長度為 0。

AndroidBackend 把每個 `.arc` 轉成 `android.graphics.Path.addArc`,而這個呼叫會**另起一個輪廓**。形狀是照 CoreGraphics
的 `addArc` 寫的，它會接續目前的輪廓。在 Android 上路徑因此散成幾段各自獨立的輪廓，填色時各自封閉：成為楔形，在膠囊上
就是那個「<」與細片。

受影響的範圍：所有 `Capsule`,以及半徑超過邊長約 44% 的 `RoundedRectangle`。半徑較小的走三次曲線的分支，從未受影響，
這也是 P110 的 `RoundedRectangle(cornerRadius: 12)` 看起來正常的原因。

## 修正

`Path.arcTo(left, top, right, bottom, startDegrees, sweepDegrees, forceMoveTo: false)` 會接續輪廓
(AndroidBackend+Paths.swift)。`arcTo` 把掃過的角度取 360 度的餘數，整圈會消失，所以分成兩半放入。

已驗證:P110 的膠囊在 api36b 模擬器上是完整的，P107 的「直線、半圓、直線」軌跡沒有改變(RUN DONE err=0.000 pt,
路徑長度 588.495)。
