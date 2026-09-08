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

## RootScrollHost shifts content right by however far it extends left

`RootScrollHost.contentBounds` seeds its box with
`CGRect(origin: .zero, size: view.bounds.size)` and unions the subview boxes
into it. Because the seed always contains the origin, `box.minX` can never be
positive, and `layoutSubviews` then sets
`content.frame.origin = CGPoint(x: -box.minX, y: -box.minY)` -- so the content
is always shifted RIGHT, by exactly how far it reaches to the left.

Measured 2026-09-08 on the iPhone 16 simulator: P17's content occupies
x 260..393 pt while P15, P46 and P47 all begin at 12..16. The design's own left
edge is only reachable by scrolling, and 260 pt of the window is blank at scroll
position zero.

**The shift itself is intentional and the commit that added it says why** -- a
scroll view cannot reach negative coordinates, so content overflowing to the
left is unreachable however large `contentSize` is. What is not established is
whether a 260 pt shift is the right answer for P17 or whether the box is being
widened by a subview that draws nothing. That question is open.

Scrolling works: a rightward scroll moves 618,358 px on P17 and 287,205 on P10.
An earlier note here said it did not, which was a probe that scrolled left
against content already flush left; that is recorded in `mistakes/mistakes.csv2`
rather than repeated as a defect.

**Sixteen other scenarios are clipped at the right edge** and have not been
looked at individually. Only P17 (260 pt) and P13 (132 pt) show a large left
offset; the other 46 start at 0..40.

### RootScrollHost 會把內容往右推,推的距離等於它向左延伸多遠

`RootScrollHost.contentBounds` 以 `CGRect(origin: .zero, size: view.bounds.size)`
起算,再把各子 view 的框聯集進去。由於起始框永遠包含原點,`box.minX` 不可能為正;而
`layoutSubviews` 接著設定 `content.frame.origin = CGPoint(x: -box.minX, y: -box.minY)`
——於是內容永遠**向右**位移,距離恰為它向左延伸的長度。

2026-09-08 於 iPhone 16 模擬器實測:P17 的內容佔據 x 260..393 點,而 P15、P46、P47 都是從
12..16 開始。該設計自身的左緣只能靠捲動觸及,而在捲動位置 0 時,視窗有 260 點是空白的。

**這個位移本身是刻意的,加入它的那筆 commit 也說明了理由**——捲動視圖無法觸及負座標,因此向左溢出的
內容無論 `contentSize` 多大都構不到。尚未確立的是:260 點對 P17 而言是否為正確答案,還是那個框被一個
「什麼都不畫」的子 view 撐大了。該問題仍然開放。

捲動是正常的:P17 向右捲動移動 618,358 像素、P10 為 287,205。此處先前有一條說它捲不動,那是一次
「對已貼齊左緣的內容向左捲」的探測;那件事記在 `mistakes/mistakes.csv2`,不在此處重述為缺陷。

**另有十六個情境在右緣被裁切**,尚未逐一檢視。左偏移較大的只有 P17(260 點)與 P13(132 點),
其餘 46 個都從 0..40 開始。

---

## Reported: a 6 ms delay on button presses -- not yet measured here

Recorded 2026-09-08 at the user's request, for investigation when there is time.

**What is known: only that it was reported.** No measurement of mine is behind
this line -- not the 6 ms, not which platform it was seen on, not whether it is
input latency, a layout pass, or the gap between a press and its visible
response. Writing it down with a number I did not take would make it look
investigated.

What would settle it, when someone picks it up: a press-to-repaint measurement
on one backend, against the same measurement with the button's action body
emptied. That separates the framework's dispatch from whatever the action does.

### 回報:按鈕按下有 6 毫秒延遲——此處尚未量測

2026-09-08 依使用者要求記下,待有時間時調查。

**已知的只有「它被回報過」這件事。** 這一行背後沒有任何我自己的量測——不是那 6 毫秒、不是它出現在
哪個平台、也不是它究竟屬於輸入延遲、一次版面計算,還是「按下」與「可見反應」之間的間隔。把一個我沒有
量過的數字寫下來,會讓它看起來像是已經被調查過了。

日後接手時能夠定案的做法:在單一 backend 上量測「按下到重繪」,再與「把按鈕 action 主體清空」的同一
量測相比。那能把框架的派送與 action 本身所做的事分開。

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
