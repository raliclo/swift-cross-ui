# UIKitBackend — open defects and gaps

Measured on the iOS Simulator (iPhone 16, iOS 18.4, Xcode 27.0) unless a line
says otherwise. Everything here came from a run, not from reading code.

Defects in the backend, not errors in what I said about it. A claim of mine that
turned out to be false goes in `mistakes/mistakes.csv2`, whose subject is me;
this file's subject is the backend. The two get confused because an expensive
mistake feels like it belongs somewhere permanent -- it does, and that somewhere
is the other file. See `flow.md` section 3h.

本檔收的是 backend 的缺陷，不是「我對它說錯的話」。我說過而後來被證明為假的主張，屬於
`mistakes/mistakes.csv2`——那一份的主詞是我，本檔的主詞是這個 backend。兩者容易混淆，是因為一個
代價高昂的錯誤會讓人覺得它該被永久記下來；它確實該，只是該記在另一份檔案裡。見 `flow.md` 第 3h 節。

## Nothing open

Both entries that used to be here — `VisualEffects` having no path for six of
its seven effects, and one `List` in P7 not responding to taps — were closed on
2026-09-02 and moved to the section below, with what was measured and what the
first diagnosis got wrong.

The `VisualEffects` entry is worth keeping in mind rather than in this file. It
recorded a measurement (`CALayer.filters` does not composite on iOS) together
with a conclusion drawn from it (therefore six effects have no path). The
measurement was right and the conclusion was not: the route iOS does offer is to
apply the filters to a rendering of the subtree rather than to the live layer,
which is what `UIKitBackend+VisualEffects.swift` now does. "This platform has no
API for it" survived a real measurement here and was still wrong.

## 沒有未解項目

原本在此處的兩則條目——`VisualEffects` 七項效果中有六項無路可走，以及 P7 中有一個 `List` 對點按
沒有反應——都已於 2026-09-02 關閉，並移至下方一節，連同「量到了什麼」與「第一次診斷錯在哪裡」。

`VisualEffects` 那一則值得記在心裡而非記在本檔。它記錄的是一項量測結果（`CALayer.filters` 在 iOS 上
不參與合成），以及一個由它推出的結論（因此六項效果無路可走）。量測是對的，結論不是：iOS 確實提供的
路徑，是把 filter 套用在「子樹的算繪結果」上，而非套用在活的 layer 上——那正是
`UIKitBackend+VisualEffects.swift` 現在的做法。「這個平台沒有對應的 API」在此處通過了一次真實的
量測，卻依然是錯的。

## Fixed 2026-09-02

- **Content outside a container's bounds was drawn but could not be touched.**
  `UIView.hitTest` returns nil for a point outside the view's own bounds
  *before* it looks at any subview. That is right for a view that clips and
  wrong for a SwiftCrossUI container, whose children routinely sit outside it:
  content wider than its container is centred, so half of it is at negative x,
  and nothing clips it, so it draws there.

  It took three measurements to see, and the first conclusion drawn from them
  was wrong. P7's plain `List` did not select on a tap; the entry here said list
  taps do not select on iOS, which generalised from one list in one app. P3's
  detail list selects and so does P7's own split view sidebar, so it was not
  `UIKitBackend+List.swift`. P30's "Use wide frame" then behaved identically --
  the label stayed at 120 after a tap on its measured centre -- and P30 has no
  list in it. What P7 and P30 share is horizontal overflow; P16, P21, P23 and
  P26 fit the phone and every control in them responded.

  `BaseViewWidget.hitTest` now asks its children whatever the point, honouring
  `clipsToBounds`/`masksToBounds` so a rounded-corner container and a scroll
  view still clip. After the fix P7's Cherry row highlights on a tap and P30
  reads "frame width: 260".

- **`VisualEffects` was seven effects of which one worked.** `CALayer.filters`
  is read by the AppKit compositor and ignored by UIKit's, so the chain that
  works on macOS did nothing here. P39 measured it: `opacity 0.35` faded and
  `blur 3`, `saturation 2.5`, `brightness 0.4`, `grayscale 1` and
  `hueRotation 120` were identical to the control. The effects now run over a
  `CALayer.render(in:)` bitmap through Core Image, with the result as the
  contents of a layer over the child and the child hidden by an empty mask so
  it stays hit-testable. All nine of P39's cells now differ from the control as
  they should. `opacity` stays on `alpha` and stays live; the rest are a
  rendering refreshed on layout, which is stated in the file.

- **`createToggle` was a `fatalError`.** Six apps — P12, P13, P16, P21, P23,
  P26 — died within a second of launch. `createSwitch` was implemented, so
  switch-styled toggles worked and default-styled ones did not, which is what
  made the largest gap look like a niche one.
- **`BackendFeatures.Tables` was missing.** P7 aborted; P23 now renders four
  columns and eight rows.
- **A container swallowed touches.** `UIView.hitTest` returns any view whose
  bounds contain the point, so a transparent overlay took the clicks meant for
  the button beneath it — #454. `BaseViewWidget` now returns nil when the hit
  resolves to the container itself. P10's `Covered clicks` went 0 → 1.
- **Content wider than the screen was unreachable.** Fourteen apps were clipped
  at both edges. The root is now hosted in a scroll view; see
  `RootScrollHost.swift` for `actualView` and `rwdView`.

## Not a defect

- **`allowsHitTesting(false)` letting a click through is correct.** P10's own
  comment: "the layer here is fully opaque, so nothing about how it is drawn
  could let a click through. Only the modifier can... If the counter rises, the
  click reached a button nobody could see, which is the whole claim." macOS
  measures Direct 2, Covered 2, Hidden 2. An earlier version of the macOS action
  file said Hidden must stay 0; that was wrong and is corrected.
- **Horizontal overflow is not a layout bug.** P10's three columns with 24pt
  spacing and a 200pt block exceed 600 points against a 393-point safe area.
  The test apps are drawn at desktop widths and SwiftUI overflows in the same
  situation. What was wrong was that the overflow could not be reached.
