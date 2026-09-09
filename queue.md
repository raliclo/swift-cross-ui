# queue

由 `heartbeats/heartbeat.zsh` 讀取。**未完成寫 `- [ ]`,完成改成 `- [x]`。**
順序即優先序:第一個未完成項就是下一件事。

Read by `heartbeats/heartbeat.zsh`. Order is priority: the first unchecked
item is the next thing. This file exists because the queue used to live in the
conversation, where it faded with compaction and its absence looked exactly like
an empty queue -- mistakes.md entry 1.

- [x] **1. `SceneStorage`** — 已完成並驅動 (P59)。`@SceneStorage` 以視窗 id 為範圍,經由既有的 `AppStorageProvider` 存於 `scene.<id>.<key>`——**沒有新的 backend requirement**
- [ ] **2. `Settings` scene** — 需要先決定單視窗平台那條路(見下方 Q8 註記)。`environment.window` 與 `AnyView` 都存在,因此 sheet 那條路可行;`presentSheet` 需要一個具體的 `Window`,而 `AlertScene` 用的是 `window: nil` 讓 backend 自己選
- [ ] **3. `DocumentGroup`** — 三項中最大的一項,但它蓋在既有的 `FileDialogs` 之上,而不是蓋在新的 requirement 上
- [ ] **4. Q12:#28 動畫 / #30 focus 無障礙 / #32 手勢** — 三項各自獨立,可分開驗證
- [ ] **5. #117 phase 3:依需求建立列** — **刻意降級。** 它原本的症狀(視窗隨列數長大)已經在五個 backend 上都被 phase 2/4/5 修掉了,剩下的是 10,000 列時的記憶體。檢驗標準已經是精確的:RSS 必須停止隨列數增長(400 列 114 MB,10,000 列 423 MB)
- [ ] **6. #74 `-GPU` on macOS** — 被擋:等 Windows 端的輸入
- [x] #117 phase 5: GTK 與 WinUI 由 Windows 完成並量測(`53c4a660`;WinUI 400 列 656x16224 → 656x739)
- [x] #117 phase 2: AppKit list viewport (`1ff4f3cf`)
- [x] #117 phase 4a: UIKit 與 Android list viewport (`c88e3994`)
- [x] Review 4: 兩個 ScrollViewReader,在 AppKit 與 Android 上雙向驅動 (P58, `6c417aaf`)
- [x] Review 6: parity survey #33 主表與細節列一致化
- [x] Remote session ping: heartbeats/ —— 兩台機器皆以 session id 送達並實測

## 這次重排的理由 / Why this order changed

**#117 phase 3 從第 2 位降到第 5 位。** 它要解的問題已經不是原本那個問題了:phase 2/4/5 落地之後,
「視窗隨列數長大」在五個 backend 上都不再發生,而那才是使用者看得見的症狀。剩下的是 10,000 列時
423 MB 對 114 MB 的記憶體差,那是一個真實但不流血的成本。

**三項缺失的 SwiftUI API 升上來。** `Settings`、`SceneStorage`、`DocumentGroup` 是**根本不存在**的
東西——以宣告形狀的 grep 查證過(`public struct <名稱>`),三者皆為 0,而同一個 grep 找得到
`AppStorage`、`StateObject` 與 `EnvironmentObject`。一個不存在的 API 比一個已經可用但在極端規模下
較貴的 API,離「功能對等」更遠。

**`SceneStorage` 排在 `Settings` 之前,而不是照編號。** `Settings` 卡在一個尚未決定的設計問題上
(Android 的 `createWindow` 回傳一個假的視窗),而 `SceneStorage` 沒有這個問題:它有一個現成的
模型可以照抄,而且不需要任何新的 backend requirement。

Phase 3 dropped from second to fifth because the problem it addresses is no
longer the problem it was: the visible symptom is fixed on all five backends,
and what remains is 423 MB against 114 MB at ten thousand rows -- real, but not
bleeding. The three absent SwiftUI APIs moved up, verified absent by a
declaration-shaped grep that finds AppStorage and StateObject and finds none of
them. SceneStorage leads because Settings is blocked on a design decision and it
is not.

## Q8 note — what was measured before writing any code

`Settings` cannot simply be a second window. Measured 2026-09-09:

| backend | `supportsMultipleWindows` | what a second window does |
| --- | --- | --- |
| AppKit | true | a real window |
| Gtk | true | a real window |
| WinUI | true | a real window |
| UIKit | **false** | `createWindow` builds a second `UIWindow` |
| Android | **false** | `createWindow` returns a fresh `Window()` value with a `TODO` beside it — **nothing appears** |

So a window-based `Settings` would be silently invisible on Android, which is
the shape CLAUDE.md forbids. `AlertScene` takes `window: nil` and lets the
backend choose; `presentSheet` needs a concrete `Window`. The single-window path
is the design question, and it is the whole of the work — not the scene struct.
