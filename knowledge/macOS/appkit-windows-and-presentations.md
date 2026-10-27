# AppKitBackend: windows, popovers, alerts and sheets

Root causes found on macOS that are easy to reintroduce. Each was measured on
a test app; the commit or results.csv2 row is given.

## Saved window frames override `.defaultSize`

`createWindow` calls `setFrameAutosaveName(id)` (Sources/AppKitBackend/AppKitBackend.swift),
so AppKit restores `NSWindow Frame <id>` from user defaults over the scene's
`.defaultSize`, as SwiftUI does. The id is derived from the root view's type
(`TupleView1<HotReloadableView>-0` for most test apps). Consequences seen:

- raising P50's `defaultSize` from 700 to 900 changed nothing until
  `defaults delete` (results.csv2: mac, P50, 2026-09-18);
- on 2026-10-22 P41 opened at 1202x799 against 1340x888 on GTK and P92 kept a
  460-point frame after its `defaultSize` became 640.

The harness drops these keys before every launch (see
`debugtarget-bundle.md`, 4b268536). Any window-size measurement must clear
them first.

## A window AppKit constrains while showing it

AppKit can resize a window synchronously inside `makeKeyAndOrderFront` when
its frame is larger than the screen. `WindowReference` cleared `isFirstUpdate`
only after showing, so the resize handler updated and showed again: P103
recursed through `windowWillResize` until it ran out of memory and never had a
window (6f4f94a2, 2026-10-19). `isFirstUpdate` is now cleared before the show
(Sources/SwiftCrossUI/Scenes/WindowReference.swift).

## Popovers

- **Edge mapping.** `NSPopover.show(relativeTo:of:preferredEdge:)` reads the
  edge in AppKit's y-up screen space, not in the backend's flipped views. The
  first mapping followed a comment and was inverted (P50, 2026-09-17).
- **Default edge.** A popover with no preference opens below its anchor, as on
  the other four backends; it had carried `.maxY` (above) under a comment
  claiming below (P50, 2026-09-17).
- **`popoverDidClose` twice.** NSPopover registers a delegate that implements
  a notification-shaped method as an observer of that notification, so the
  method arrives once by delegation and once from the notification centre.
  A per-presentation flag stops `onDismiss` running twice
  (Sources/AppKitBackend/AppKitBackend+Popover.swift; P50, 2026-09-10).
- **Placement.** Setting the content view controller's view origin to `.zero`
  overrode AppKit's own placement and pushed 26 pt of margin to two edges; the
  view is no longer repositioned (P50, 2026-09-11).

## Alerts and sheets

- `NSAlert` binds Escape only to a button titled Cancel. A one-button alert
  ignored Escape, so action files press Return (first button), and the backend
  now answers Escape for a one-button alert (P5 2026-09-18; P31 2026-09-28).
- Alerts stack on the topmost sheet instead of queuing behind it: after A+B+C
  the dismissal order is C, B, A (P5, 2026-09-28).
- `sheet(onDismiss:)` runs on programmatic dismissal too (8a6f2aa8,
  2026-10-20; P49-close-the-cover read 0 dismissals without it).
- A sheet is a second, untitled window: the harness's final capture by title
  does not show it (see `screenshot-capture.md`).

## Scenes

- Launch windows follow SwiftUI: only the first `WindowGroup` opens at launch
  (P93, `SceneLaunch.swift`, 2026-10-14).
- `Settings { }` opens a separate window titled Settings (P60, 2026-09-09).
- Cmd-Q quits (P10 control run, 2026-09-29).
- `refreshable` is a floating Refresh button: `addSubview` put it behind the
  clip view; `addFloatingSubview` shows it (P54, 2026-09-09).

## Limits

- A test of window restoration itself needs `SCUI_KEEP_WINDOW_FRAME=1`; by
  default the harness throws the frames away.

---

# AppKitBackend:視窗、popover、alert 與 sheet

在 macOS 上找到、而且容易再犯的根本原因。每一項都在測試 app 上量過，附上 commit 或 results.csv2 列。

## 儲存的視窗框會蓋過 `.defaultSize`

`createWindow` 會呼叫 `setFrameAutosaveName(id)`(Sources/AppKitBackend/AppKitBackend.swift),
所以 AppKit 會從 user defaults 還原 `NSWindow Frame <id>`,蓋過 scene 的 `.defaultSize`——與 SwiftUI 相同。
id 取自 root view 的型別(大多數測試 app 是 `TupleView1<HotReloadableView>-0`)。看過的後果:

- 把 P50 的 `defaultSize` 從 700 改成 900 沒有任何變化，直到 `defaults delete`(results.csv2:mac、P50、2026-09-18);
- 2026-10-22 P41 開成 1202x799(GTK 是 1340x888),P92 在 `defaultSize` 改成 640 之後仍留著 460 點寬的視窗框。

harness 每次啟動前都會刪掉這些鍵(見 `debugtarget-bundle.md`,4b268536)。任何視窗大小的量測都要先清掉它們。

## AppKit 在顯示視窗時就約束它

當視窗框比螢幕大時,AppKit 會在 `makeKeyAndOrderFront` 裡同步改變視窗大小。`WindowReference` 原本在顯示之後才清掉
`isFirstUpdate`,於是 resize handler 又更新、又顯示一次:P103 經 `windowWillResize` 一路遞迴到記憶體耗盡，始終沒有視窗
(6f4f94a2,2026-10-19)。現在 `isFirstUpdate` 在顯示之前就清掉(Sources/SwiftCrossUI/Scenes/WindowReference.swift)。

## Popover

- **邊的對應。** `NSPopover.show(relativeTo:of:preferredEdge:)` 以 AppKit 的 y 向上螢幕座標解讀邊，不是 backend 翻轉過的
  view 座標。第一版照著註解寫，結果相反(P50,2026-09-17)。
- **預設邊。** 沒有指定偏好的 popover 開在錨點下方，與其他四個 backend 相同;原本帶的是 `.maxY`(上方),註解卻寫下方
  (P50,2026-09-17)。
- **`popoverDidClose` 兩次。** NSPopover 會把實作了「通知形狀」方法的 delegate 自動註冊為該通知的觀察者，所以方法一次經
  delegate、一次經通知中心送到。以每次呈現一個旗標防止 `onDismiss` 跑兩次
  (Sources/AppKitBackend/AppKitBackend+Popover.swift;P50,2026-09-10)。
- **位置。** 把 content view controller 的 view 原點設成 `.zero` 會蓋掉 AppKit 自己的擺放，把 26 pt 的邊距全推到兩側;
  現在不再重設該 view 的位置(P50,2026-09-11)。

## Alert 與 sheet

- `NSAlert` 只把 Escape 綁給標題為 Cancel 的按鈕。單一按鈕的 alert 不理 Escape,所以動作檔改按 Return(第一顆按鈕),
  backend 現在也會替單一按鈕的 alert 回應 Escape(P5 2026-09-18;P31 2026-09-28)。
- alert 疊在最上層的 sheet 上，而不是排在它後面:A+B+C 之後關閉順序是 C、B、A(P5,2026-09-28)。
- `sheet(onDismiss:)` 在程式關閉時也會執行(8a6f2aa8,2026-10-20;少了它 P49-close-the-cover 讀到 0 次關閉)。
- sheet 是第二個、沒有標題的視窗:harness 依標題拍的最終擷圖看不到它(見 `screenshot-capture.md`)。

## Scene

- 啟動時的視窗與 SwiftUI 相同：只開第一個 `WindowGroup`(P93,`SceneLaunch.swift`,2026-10-14)。
- `Settings { }` 開一個標題為 Settings 的獨立視窗(P60,2026-09-09)。
- Cmd-Q 會結束 app(P10 對照執行,2026-09-29)。
- `refreshable` 是浮動的 Refresh 按鈕:`addSubview` 會把它放到 clip view 後面;`addFloatingSubview` 才看得到
  (P54,2026-09-09)。

## 限制

- 要測試視窗還原本身，需要 `SCUI_KEEP_WINDOW_FRAME=1`;預設情況下 harness 會丟掉儲存的視窗框。
