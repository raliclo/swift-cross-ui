# Pointer, hover and cursors on iOS

How hover and cursor styles work without a mouse, and how they are tested on
the simulators. Checked against UIKitBackend+PointerHover.swift,
UIKitBackend+Cursors.swift, ActionFileUITests.swift and results.csv2 (ios,
P88/P72/P80, 2026-10-13 to 2026-10-15) on 2026-10-24.

## Hover

- With a pointer (iPad): `UIHoverGestureRecognizer`, with `modifierFlags`.
- On a touch screen a held finger is hover: a `UILongPressGestureRecognizer`
  (0.5 s, direct touches, cancels no touches) in `PointerHoverWidget`; moving
  the finger moves the hover point and lifting ends it (decision of
  2026-10-15, queue item 10). The same rule holds on Android and GTK.
- iPhone simulator, P88: a finger held 1 s and dragged 100 pt gave
  "hover reports: 22" (0 before). The runner cannot capture during a hold; a
  capture loop from outside the runner (`simctl io screenshot`) showed the
  panel orange in 9 of 30 frames during a 3 s press.

## Driving hover from the runner

- **`XCUICoordinate.hover()` is unreliable** on the iPad simulator (iOS 27.0,
  2026-10-13): the first call of a run reached the app, later calls mostly did
  not, and `perform(withKeyModifiers:)` never showed Command.
- The runner sends one synthesized pointer path per `hover` row, from the
  previous point; it reaches the app on every row and carries held modifiers
  (P88: "hover reports" 13, 9, 14; "last with cmd: x=155 y=80").
- The pointer leaves about 100 ms after the path ends. A row with `micros`
  rests it and the runner captures halfway into `IOS_SHOT_DIR`; test_ios.zsh
  moves those captures to `output/screenshots/<pn>-ios-hover-L<line>-*.png`.
- On iPhone, `hover()` failed the whole test ("Pointer events are not supported
  for this device"); the runner now skips hover rows there and says so.

## Cursors (iPad)

- `UIPointerInteraction` has no crosshair. Crosshair, the resize shapes and
  notAllowed are drawn paths; text maps to `.verticalBeam`, pointingHand to
  `.highlight`. Without a pointer the interaction is inert, so the iPhone cannot
  test it.
- iPadOS draws its pointer into the framebuffer, so `simctl io screenshot`
  shows the cursor. `xcrun simctl ui` has no pointer option.
- Verified on the iPad Pro 11-inch (M5) simulator: P72 crosshair over the mesh
  view and the system pointer over text (2026-10-13); P80 one style request each
  for pointingHand, crosshair, text, resizeHorizontal, resizeVertical and
  notAllowed (2026-10-14). The first hover of a run is captured before any style
  shows.

## Open (checked 2026-10-20)

- A physical iPad with a trackpad has not been tried.

---

# iOS 上的指標、懸停與游標

沒有滑鼠時懸停與游標樣式如何運作，以及如何在模擬器上測試。2026-10-24 對照 UIKitBackend+PointerHover.swift、
UIKitBackend+Cursors.swift、ActionFileUITests.swift 與 results.csv2(ios,P88/P72/P80,2026-10-13 至 2026-10-15)確認。

## 懸停

- 有指標時(iPad):`UIHoverGestureRecognizer`,帶 `modifierFlags`。
- 在觸控螢幕上，按住的手指就是懸停:`PointerHoverWidget` 中的 `UILongPressGestureRecognizer`(0.5 秒、直接觸控、不取消
  任何觸控);移動手指會移動懸停點，放開則結束(2026-10-15 的決定，佇列第 10 項)。Android 與 GTK 也遵循同樣規則。
- iPhone 模擬器上的 P88:手指按住 1 秒再拖 100 點，得到「hover reports: 22」(之前是 0)。runner 無法在按住期間擷圖;
  在 runner 之外以 `simctl io screenshot` 連續擷圖，按住 3 秒期間 30 幀中有 9 幀面板是橘色。

## 由 runner 驅動懸停

- **`XCUICoordinate.hover()` 不可靠**(iPad 模擬器，iOS 27.0,2026-10-13):一次執行中第一次呼叫會到達 app,之後大多不會，
  `perform(withKeyModifiers:)` 也從未帶出 Command。
- runner 為每個 `hover` 列從上一個點送出一條合成的指標路徑;每一列都會到達 app,並帶著按住的修飾鍵
  (P88:「hover reports」13、9、14;「last with cmd: x=155 y=80」)。
- 路徑結束約 100 毫秒後指標離開。帶 `micros` 的列會讓指標停留，runner 在中途擷圖到 `IOS_SHOT_DIR`;test_ios.zsh 再把那些
  擷圖搬到 `output/screenshots/<pn>-ios-hover-L<行號>-*.png`。
- 在 iPhone 上 `hover()` 會讓整個測試失敗(「Pointer events are not supported for this device」);runner 現在在那裡略過
  hover 列並明白說出來。

## 游標(iPad)

- `UIPointerInteraction` 沒有十字游標。十字、調整大小的形狀與 notAllowed 是自行繪製的路徑;text 對應 `.verticalBeam`,
  pointingHand 對應 `.highlight`。沒有指標時這個互動不起作用，所以 iPhone 無法測試。
- iPadOS 把指標畫進 framebuffer,所以 `simctl io screenshot` 會拍到游標。`xcrun simctl ui` 沒有指標相關選項。
- 已在 iPad Pro 11-inch (M5) 模擬器上驗證:P72 在網格 view 上是十字、在文字上是系統指標(2026-10-13);P80 對 pointingHand、
  crosshair、text、resizeHorizontal、resizeVertical 與 notAllowed 各請求一次樣式(2026-10-14)。一次執行中的第一次懸停會在
  任何樣式出現前就被擷圖。

## 未解(2026-10-20 確認)

- 尚未試過帶觸控板的實體 iPad。
