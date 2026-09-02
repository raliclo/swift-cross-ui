# UIKitBackend — open defects and gaps

Measured on the iOS Simulator (iPhone 16, iOS 18.4, Xcode 27.0) unless a line
says otherwise. Everything here came from a run, not from reading code.

## Open: `BackendFeatures.VisualEffects` — six of seven effects have no path yet

`opacity` works, through `UIView.alpha`. The other six — blur, saturation,
brightness, contrast, grayscale, hueRotation — do not, because
**`CALayer.filters` does not composite on iOS**.

That last sentence is measured, not assumed. I asserted it once from memory,
declined to implement the feature on the strength of it, and was told that a
platform limitation is a claim to verify rather than a conclusion. So the
`CIFilter` chain was written exactly as AppKitBackend has it, built for the
simulator, and P39 — nine cells, each applying one effect to the same angular
gradient — was photographed and measured:

| cell | mean chroma | verdict |
| --- | --- | --- |
| `grayscale 1` | 174.6 | full colour — must be near 0 |
| `saturation 2.5` | 174.3 | identical to grayscale |
| `opacity 0.35` | 61.5 | applied |

`grayscale 1` and `saturation 2.5` ask for opposite things and produce the same
image to within 0.3 of a chroma unit. The filter chain is attached and ignored.

`Sources/UIKitBackend/UIKitBackend+VisualEffects.swift` carries that
implementation. It is kept rather than deleted because `opacity` is genuinely
served by it and because the file is the record of what was tried.

### The three routes that remain

| Route | Covers | Cost |
| --- | --- | --- |
| `UIVisualEffectView` | Blur only, in system styles, and it blurs what is *behind* the view rather than its content | Wrong semantics — `.blur` is about the view's own pixels |
| Rasterise the subtree, filter with Core Image | All seven | Loses live interaction and dynamic updates; every content change needs a re-capture |
| `CAMetalLayer` or a custom shader | All seven, and live | A large increase in backend complexity and in what has to be maintained |

None has been attempted. The second is the likely candidate and its cost is the
one to measure first: whether a rasterised subtree can still be laid out and
hit-tested, and what a re-capture costs on every state change.

### 尚未解決：`BackendFeatures.VisualEffects` — 七項效果中有六項尚無可行路徑

`opacity` 可運作，透過 `UIView.alpha`。其餘六項——模糊、飽和度、亮度、對比、灰階、色相旋轉——
不行，因為 **`CALayer.filters` 在 iOS 上不參與合成**。

最後那句話是量出來的，不是假設。我曾憑印象斷言它，並據此拒絕實作本項功能，而後被告知「平台限制是
一項待查證的主張，而非結論」。因此我照 AppKitBackend 的寫法把 `CIFilter` 鏈完整寫出、為模擬器建置，
並對 P39 拍照量測——該 app 有九個格子，各對同一張角度漸層套用一種效果。數據見上方英文表格。

`grayscale 1` 與 `saturation 2.5` 要求的是相反的效果，產生的影像卻在 0.3 個色度單位之內完全相同。
filter 鏈確實掛上去了，然後被忽略。

剩下的三條路徑與其代價見上方英文表格。三者皆尚未嘗試。第二條是最可能的候選，而應先量測的正是它的
代價：光柵化後的子樹是否仍能參與版面與 hit test，以及每一次狀態變更所需的重新擷取成本為何。

## Open: one `List` in P7 does not respond to taps, while others do

Measured 2026-09-02 on the iPhone 16 simulator. The first version of this entry
said list taps do not select on iOS at all. That was wrong, and the way it was
wrong is worth keeping: it generalised from one list in one app before looking
at a second.

| app, which list | tap | result |
| --- | --- | --- |
| P3, detail list | "Detail C" | selected — grey highlight |
| P7, split view sidebar | Cherry, (326, 486) | selected — grey band measured at px y 1404-1504, x 880-1176 |
| P7, plain top-level list | Cherry, (76, 639) then (143, 637) | nothing, twice |
| P7, plain top-level list | "Select Cherry" button, which sets the binding from code | selected — grey highlight |

So `UIKitBackend+List.swift` is not the problem: taps select in two of the three
lists, and the fourth row shows that this list renders a selection perfectly
well once something else sets it. What does not arrive is the touch.

The two coordinates tried for the plain list were both inside the rectangle the
button went on to highlight, so this is not a missed target. Two things about
that list stand out and neither has been chased yet:

- Its label, `Text("Plain List (#476)")`, does not appear on screen at all.
  Something about where that `VStack` ends up is already wrong before any touch
  is involved.
- P7's content is much wider than the phone, so it is offset inside
  `RootScrollHost`. The split view sidebar, which does respond, is offset by the
  same amount, so the offset alone is not the answer — but a sibling laid out
  over the plain list would be, and a missing label is consistent with a
  container being somewhere unexpected.

`testapp/actions/ios/P7-select-cherry-from-code.csv` uses the button rather than
a row tap for this reason. A file that taps a row and claims nothing is a file
that passes while the feature is broken.

## 未解：P7 中有一個 `List` 對點按沒有反應，其他的則有

2026-09-02 於 iPhone 16 模擬器上量測。本條目的第一版寫的是「在 iOS 上點按 list 完全不會選取」。
那是錯的，而它錯的方式值得保留：它在看第二個 list 之前，就從「一支 app 中的一個 list」推及全體。

| app、哪一個 list | 點按 | 結果 |
| --- | --- | --- |
| P3，detail list | 「Detail C」 | 已選取——灰色標示 |
| P7，分割視圖的 sidebar | Cherry，(326, 486) | 已選取——量到灰帶位於 px y 1404-1504、x 880-1176 |
| P7，頂層的純 list | Cherry，先 (76, 639) 再 (143, 637) | 兩次都毫無反應 |
| P7，頂層的純 list | 「Select Cherry」按鈕，由程式碼設定 binding | 已選取——灰色標示 |

因此問題不在 `UIKitBackend+List.swift`：三個 list 中有兩個點按可選取，而第四列顯示，一旦有別的東西
設定了選取，這個 list 完全能把它算繪出來。沒有抵達的是那次觸控。

為該純 list 嘗試的兩個座標，都落在該按鈕稍後所標示的矩形之內，因此這不是沒點中。關於那個 list，
有兩件事顯眼，而兩者都尚未追查：

- 它的標籤 `Text("Plain List (#476)")` 根本沒有出現在畫面上。在任何觸控介入之前，那個 `VStack`
  最終落在哪裡就已經是錯的了。
- P7 的內容遠比手機寬，因此它在 `RootScrollHost` 中被平移。而確實有反應的分割視圖 sidebar 被平移了
  同樣的量，所以單靠平移並不能解釋——但「有一個兄弟元件被排在該純 list 之上」可以，而「標籤消失」
  與「某個容器位於意料之外的地方」是一致的。

`testapp/actions/ios/P7-select-cherry-from-code.csv` 之所以使用按鈕而非點按列，正是為此。一份
「點了一列卻不主張任何事」的檔案，會是一份在功能損壞時依然通過的檔案。

## Fixed 2026-09-02

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
