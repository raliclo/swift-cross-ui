# Hit testing in UIKitBackend

Two overrides of `UIView.hitTest` that make taps land where SwiftCrossUI and
AppKit say they should. Checked against Sources/UIKitBackend/Widget.swift and
UIKitBackend+Container.swift on 2026-10-24.

## 1. Children outside their container's bounds

- **Problem.** `UIView.hitTest` returns nil for a point outside the view's
  bounds before asking any subview. SwiftCrossUI containers routinely have
  children outside them (content wider than its container is centred, so half
  sits at negative x) and nothing clips them: drawn and untouchable.
- **Measured 2026-09-02.** P7's plain List inside an HStack wider than the phone
  ignored taps inside its rows; P30's "Use wide frame" ignored a tap on its
  centre. Apps that fit (P16, P21, P23, P26) responded.
- **Rule now.** Children are asked even when the point is outside, topmost
  first. Only clipping (`clipsToBounds`, `masksToBounds`, set by
  `setCornerRadius`) stops that. Hidden views, views with alpha <= 0.01 and
  disabled views return nil.

## 2. Transparent layers do not swallow taps (#454)

- **Problem.** A plain `UIView` takes every touch inside its bounds whatever its
  background alpha, so a `Color.clear` overlay or an empty container over a
  button swallowed taps. P10, 2026-09-02: "Covered clicks" stayed 0 while the
  overlay was present; AppKit measured the same day reported Direct 2, Covered
  2, Hidden 2.
- **Rule now.** A backend container with no child claiming the point returns nil
  (as `AppKitHitTestingContainer` does), unless it has a gesture recogniser
  (`onTapGesture` on a `Color`). `ColorableRectangleWidget` is hit-testable only
  if its background colour is itself not transparent; a rectangle inside a
  faded parent is still hittable. This is SwiftUI's rule too, and why
  `.contentShape` exists.

## Related

- Visual effects hide the original child with an empty `CALayer` mask, not
  `alpha` or `isHidden`, because `hitTest` skips alpha <= 0.01
  ([visual-effects-and-colour.md](visual-effects-and-colour.md)).
- A long press on non-selectable text reaches its ancestor: an emoji TextView's
  own copy-menu `UILongPressGestureRecognizer` won every hold until it was made
  to begin only on selectable text (1826f799, P103, 2026-10-19).
- A pan recogniser begins only after its slop, so its `.began` location is a few
  points into the drag; the press point is recovered as location minus
  `translation(in:)` (measured 2026-09-10: (80, 42) recorded where the press was
  (70, 38)).

---

# UIKitBackend 的點擊判定

兩處 `UIView.hitTest` 覆寫，讓點擊落在 SwiftCrossUI 與 AppKit 認定的位置。2026-10-24 對照
Sources/UIKitBackend/Widget.swift 與 UIKitBackend+Container.swift 確認。

## 1. 位於容器範圍外的子 view

- **問題。** `UIView.hitTest` 對 view 範圍外的點，在詢問任何子 view 之前就回傳 nil。SwiftCrossUI 的容器常有位於其外的
  子 view(比容器寬的內容會置中，所以一半位於負的 x),而且沒有東西裁切它們：看得到卻點不到。
- **2026-09-02 實測。** 在比手機還寬的 HStack 中,P7 的一般 List 忽略列內的點擊;P30 的「Use wide frame」忽略點在
  其中心的點擊。符合螢幕的 app(P16、P21、P23、P26)都有反應。
- **現行規則。** 即使點在範圍外也會詢問子 view,從最上層開始。只有裁切(`clipsToBounds`、由 `setCornerRadius` 設定的
  `masksToBounds`)會阻止這件事。隱藏的 view、alpha <= 0.01 的 view 與停用的 view 回傳 nil。

## 2. 透明圖層不吞掉點擊(#454)

- **問題。** 一般的 `UIView` 不論背景 alpha 為何，都會接下範圍內的每個觸控，所以蓋在按鈕上的 `Color.clear` 或空容器
  會吞掉點擊。P10,2026-09-02:覆蓋層存在時「Covered clicks」維持 0;同日 AppKit 實測為 Direct 2、Covered 2、Hidden 2。
- **現行規則。** 沒有子 view 認領該點的 backend 容器回傳 nil(與 `AppKitHitTestingContainer` 相同),除非它有手勢辨識器
  (`Color` 上的 `onTapGesture`)。`ColorableRectangleWidget` 只有在背景色本身不透明時才可點擊;位於半透明父 view 中的
  矩形仍然可以點。這也是 SwiftUI 的規則，以及 `.contentShape` 存在的原因。

## 相關

- 視覺效果以空的 `CALayer` mask 隱藏原本的子 view,而不是用 `alpha` 或 `isHidden`,因為 `hitTest` 會略過 alpha <= 0.01
  的 view([visual-effects-and-colour.md](visual-effects-and-colour.md))。
- 在不可選取文字上的長按會傳到它的祖先 view:emoji TextView 自己的複製選單 `UILongPressGestureRecognizer` 曾贏走每一次
  按住，直到改成只在可選取文字上才開始(1826f799,P103,2026-10-19)。
- pan 辨識器要超過容許距離才開始，所以 `.began` 時的位置已經在拖曳中幾點之外;按下的點以位置減去 `translation(in:)` 求回
  (2026-09-10 實測：按在 (70, 38) 卻記錄為 (80, 42))。
