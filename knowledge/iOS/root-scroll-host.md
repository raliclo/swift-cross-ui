# RootScrollHost: desktop-sized apps on a phone

Every UIKitBackend window hosts its content in `RootScrollHost`, a
`UIScrollView`, with a floating actualView/rwdView button. The rules below
decide where an app appears and whether taps land. Checked against
Sources/UIKitBackend/RootScrollHost.swift and UIKitBackend+Window.swift on
2026-10-24. AndroidBackend follows the same rules.

## Why it exists

The test apps are laid out at desktop widths; on 2026-09-02 fourteen of 46 apps
overflowed the phone horizontally and were clipped at both edges. Content that
cannot be reached cannot be tested.

## The two modes

- **actualView** (default): the app is laid out at its scene's `.defaultSize`,
  as on a desktop, and the host scrolls to reach it (since 2026-10-09,
  90f5aba3). A shipped app would size to the screen; this mode shows the layout
  the app asked for, so iOS (440 pt) and Android (411 dp) wrap alike.
- **rwdView**: the screen size is kept and the finished layout is scaled down to
  fit the width. It scales, it does not reflow.
- The button is a debug affordance: shown in a `SCUI_DEBUG` build, hidden in
  release unless the app is launched with `-allow-rootscroll`
  (`DebugFeatures.allowsRootScrollControl`). `testapp/test_rootscroll_ios.zsh`
  checks all three cases by building twice and probing the top-left corner of
  three screenshots.
- A file that measures screen-width behaviour (P14 rotation) switches to rwdView
  first: in actualView the width is the default size whichever way the device is
  held.

## Placement rules (current)

- Vertically the content always starts at the top (2026-10-12).
- Horizontally a layout narrower than the screen is centred; a root that fits
  the screen while its layout does not is centred on the screen (P89,
  2026-10-12).
- A layout larger than the screen starts at its root (keeping the root's own
  `.padding`), not at the blank its centring left (2026-10-11, P50). The blank
  is hidden by moving the content by a fixed amount, not by a negative inset.
- Content that would start under the button's resting place starts below it.
- A root `ScrollView` with more content than the `.defaultSize` height grows to
  the screen (2026-10-12, P21). `test_support/root_scroll_warning.py`, run by
  test.zsh before an `--ios`/`--android` build, prints a compiler-style warning
  for that case; it never fails a build.

## Root causes that could come back

- **Only a negative extent is shifted.** Until 2026-09-27 a positive one was
  too. The first layout pass ran before children were placed (box at 0,0), the
  first touch triggered another pass (box at 26,30), and the whole column jumped
  under the first tap: "only the first interaction lands" (91e0b600).
- **Overflow goes into `contentInset`; the content never moves per pass.**
  Shifting by the overflow moved P10's column sideways whenever a label grew
  ("Click me" from x 20.6 to about 145 after three taps).
- **The content box stops at controls, scroll views and clipping views, and a
  view that draws nothing counts only its children.** A centred 872-wide empty
  container once moved P17's text 241 pt right; a UISwitch's animating internals
  pushed the box to x -172 and every later tap missed (P15, 2026-09-28).
- **Widget moves invalidate the host.** `setPosition`/`setSize` call
  `RootScrollHost.invalidate(containing:)`; before 2026-09-28 the host measured
  once from an unbuilt hierarchy and kept it. It must not invalidate while it is
  itself laying out: that loop hung P2 and P53 in rwdView and XCUITest waited
  600 s for an idle app.
- **`delaysContentTouches = false`** (917edb78, 2026-10-12). A scrollable
  `UIScrollView` holds a touch for about 150 ms and delivers a quick tap's down
  and up together: P55's pressed state was never drawn (pressed draws 0, was 6)
  and P70's focus refusal check failed. `touchesShouldCancel(in:)` lets a drag
  that starts on a button still scroll.

---

# RootScrollHost:手機上的桌面尺寸 app

UIKitBackend 的每個視窗都把內容放在 `RootScrollHost`(一個 `UIScrollView`)中，並有一個浮動的 actualView/rwdView
按鈕。下列規則決定 app 出現在哪裡、點擊是否點得到。2026-10-24 對照 Sources/UIKitBackend/RootScrollHost.swift 與
UIKitBackend+Window.swift 確認。AndroidBackend 遵循相同規則。

## 為何存在

測試 app 以桌面寬度排版;2026-09-02 時 46 支 app 中有 14 支在手機上水平溢出，兩側都被裁掉。到不了的內容就無法測試。

## 兩種模式

- **actualView**(預設):app 以 scene 的 `.defaultSize` 排版，如同在桌面上，由 host 捲動到達(自 2026-10-09,
  90f5aba3)。正式出貨的 app 會配合螢幕大小;這個模式顯示的是 app 要求的版面，讓 iOS(440 pt)與 Android(411 dp)
  的換行一致。
- **rwdView**:保持螢幕大小，把完成的版面縮小到符合寬度。它是縮放，不是重新排版。
- 按鈕是除錯用的：在 `SCUI_DEBUG` 建置中顯示，在 release 中隱藏，除非 app 以 `-allow-rootscroll` 啟動
  (`DebugFeatures.allowsRootScrollControl`)。`testapp/test_rootscroll_ios.zsh` 建置兩次，檢查三張截圖左上角，
  驗證這三種情況。
- 量測螢幕寬度相關行為的檔案(P14 旋轉)要先切到 rwdView:在 actualView 中，不論裝置怎麼拿，寬度都是預設大小。

## 擺放規則(現行)

- 垂直方向，內容一律從頂端開始(2026-10-12)。
- 水平方向，比螢幕窄的版面置中;根 view 符合螢幕但版面不符合時，根 view 在螢幕上置中(P89,2026-10-12)。
- 比螢幕大的版面從它的根 view 開始(保留根 view 自己的 `.padding`),而不是從置中留下的空白開始(2026-10-11,P50)。
  空白以固定量移動內容來隱藏，而不是用負的 inset。
- 會從按鈕停放處底下開始的內容，改從按鈕下方開始。
- 內容多於 `.defaultSize` 高度的根 `ScrollView` 會長到螢幕高度(2026-10-12,P21)。test.zsh 在 `--ios`/`--android`
  建置前執行 `test_support/root_scroll_warning.py`,對這種情況印出編譯器格式的警告;它從不讓建置失敗。

## 可能復發的根本原因

- **只位移負的範圍。** 2026-09-27 之前正的範圍也會位移。第一次排版在子 view 放好之前執行(範圍在 0,0),第一次觸控
  觸發另一次排版(範圍在 26,30),整欄在第一次點擊時跳動:「只有第一次互動點得到」(91e0b600)。
- **溢出放進 `contentInset`;內容不會每次排版都移動。** 以溢出量位移時，只要標籤變長,P10 的整欄就往旁邊移
  (三次點擊後「Click me」從 x 20.6 移到約 145)。
- **內容範圍止於控制項、捲動 view 與會裁切的 view,而且什麼都不畫的 view 只計入它的子 view。** 一個置中、872 寬的
  空容器曾把 P17 的文字往右移 241 點;UISwitch 動畫中的內部 view 把範圍推到 x -172,之後每次點擊都落空
  (P15,2026-09-28)。
- **widget 移動會讓 host 失效。** `setPosition`/`setSize` 會呼叫 `RootScrollHost.invalidate(containing:)`;
  2026-09-28 之前 host 只從尚未建好的階層量一次就保留結果。它自己排版時不可以再失效：那個循環讓 P2 與 P53 在 rwdView
  中卡住,XCUITest 等了 600 秒等 app 閒置。
- **`delaysContentTouches = false`**(917edb78,2026-10-12)。可捲動的 `UIScrollView` 會把觸控按住約 150 毫秒，
  並把快速點擊的按下與放開一起送出:P55 的按下狀態從未畫出(pressed draws 0,原本是 6),P70 的焦點拒絕檢查失敗。
  `touchesShouldCancel(in:)` 讓從按鈕上開始的拖曳仍然可以捲動。
