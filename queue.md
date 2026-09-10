# queue

由 `heartbeats/heartbeat.zsh` 讀取。**未完成寫 `- [ ]`,完成改成 `- [x]`。**
順序即優先序:第一個未完成項就是下一件事。

Read by `heartbeats/heartbeat.zsh`. Order is priority: the first unchecked
item is the next thing. This file exists because the queue used to live in the
conversation, where it faded with compaction and its absence looked exactly like
an empty queue -- mistakes.md entry 1.

- [x] **1. iOS 動作檔的點擊沒抵達按鈕** — 已解決。按鈕實際在 (55, 218) 點,先前的 y=100 是從縮圖估的。runner 現在會說出它解析到哪個視窗與正規化後的座標
- [x] **2. 動作檔無法定址第二個視窗** — 已解決。新增 `focus` 動作(第十欄 `target` 放標題),並補上 AppKit 缺少的 `currentWindowIdentity()`——沒有它,geometry 永遠不會重新量測
- [x] **1. P50 macOS:「Show title B」按了標題沒變** — 已修。狀態改變若不改變尺寸,就不會有人告訴視窗 preference 變了;新增 `onWindowChromeChange` 通道
- [ ] **2. P50 macOS:「按下 press me 後文字位移」尚未重現** — 2026-09-10 以像素差異量測:開啟面板只改變 popover 那塊,遮掉它之後 `getbbox()` 為 `None`(主視窗零位移);面板開著把計數 0→1 只改變標籤與計數那一行。**先前「內容溢出、左緣被切」的判定是錯的**,那是我裁切邊界造成的假象。需要你補充:位移是發生在面板內、還是主視窗?按下時面板有沒有關閉?
- [x] **2b. P50:一次 light dismiss 觸發兩次 `onDismiss`** — 已修。`NSPopover` 會把「實作通知形狀方法的 delegate」自動註冊為該通知的觀察者,於是同一個方法被送達兩次
- [ ] **2c. 動作檔無法驅動 AppKit 的 popover** — synthesiser 把事件投遞到主視窗,因此點在面板上會把它關掉;這正是 Windows 上 `origin=popover` 存在的理由,AppKit 需要對應的東西
- [x] **3. P32:Toggle 沒有可見的開啟狀態** — 已修。`onStateBezelColor` 來自 `environment.toggleColor`,app 沒設就是 nil,於是「開」什麼都不畫;改為退回 `.controlAccentColor`
- [x] **4. P44:vertical stack 空間耗盡** — 已修:那是誤報。`offered 643 / took 643` 相等,什麼都沒不夠;是 `Spacer` 在沒有餘裕時正確地拿到 0。回報條件補上「確實溢出」,與它自己的訊息一致
- [ ] **5. P28:點擊到「Clicks received」更新約 1 秒** — **先量再改**;單一觀察不足以定位
- [ ] **6. P25:多檔選取是設計問題** — 一律支援多檔,還是加 API 控制單/多檔?需要你決定
- [ ] **7. P33:大量功能缺失** — 先盤點才知道規模
- [ ] **8. P34 macOS:多數 API 缺失** — 先盤點
- [ ] **8b. #126 `onEditingChanged`(由 Mac 端承接,2026-09-10 指派)** — 全樹 `grep` 零命中,從頭寫。五個 backend 都要;這台機器建得了 AppKit / UIKit / Android,GTK 與 WinUI 的**驗證**要交給 Windows,但實作仍由此處寫出(CLAUDE.md:不得留下未實作的 backend)
- [ ] **9. `DocumentGroup`** — 三項缺失 API 的最後一項
- [ ] **10. Q12:#28 動畫 / #32 手勢**
- [ ] **11. #117 phase 3(依需求建列)** — 症狀已修,剩記憶體 400 列 114 MB vs 10,000 列 423 MB

## 為什麼缺陷排在功能之前 / Why the defects moved above the features

**上面八項是使用者在一個已發布的 backend 上親眼看到的。** 一個缺席的 API 不會讓人在畫面前困惑;
一個「按了沒反應的按鈕」會,而且它會讓人懷疑其餘每一樣東西。`DocumentGroup` 從第 3 位掉到第 9 位,
不是因為它變得不重要,而是因為它從來不曾造成任何人的困惑。

**其中的順序也不是照回報順序。** 前四項各自只有一個症狀、可重現、而且看得出對錯;第 5 項(P28 的
延遲)排在它們之後,是因為「大約一秒」是一次觀察而不是一個量測——CLAUDE.md 的關卡二明說單一樣本
不足以下結論。第 6 項是設計決定,需要你;第 7、8 兩項在盤點完成之前,連規模都還不知道。

The eight above were seen by a person using a shipped backend. A missing API does
not confuse anyone in front of a screen; a button that does nothing does, and it
casts doubt on everything else. Ordering inside them is not the order they were
reported: the first four each have one reproducible symptom, the latency one
needs a measurement before a cause, the multi-file one is a decision, and the
last two do not have a known size yet.

- [ ] **4. 鍵盤快捷鍵 step 2**(Windows 表的 #121)— **真的,而且已查證**:`ResolvedMenu.Item` 沒有任何 shortcut 欄位,所以要動四個 backend 的 `.button`。Windows 端把它標為「卡在 Mac」
- [ ] **5. focus / accessibility**(#122 / #123)— 任務自述「不可單機開始」,需要與 Windows 端協調
- [ ] **6. #74 `-GPU` on macOS** — `todo.md` 六項 Mac 工作中**唯一仍然開著**的一項,而它是一個決定、不是程式碼
- [ ] **7. Q12 #28 動畫 / #32 手勢** — 三項獨立(#30 focus 已併入上方第 5 項)
- [ ] **8. #117 phase 3(依需求建列)** — 刻意降級:症狀已在五個 backend 上修掉,剩 10,000 列時的記憶體(400 列 114 MB、10,000 列 423 MB)
- [ ] **9. #79 GTK 39px / #109 popover anchor API** — 需要你決定
- [ ] **10. #80 P42 縮放通知** — 需要人在機器前改顯示縮放
- [x] `SceneStorage`(P59)、`Settings` scene(P60)—— 即 Windows 表的 #35 前兩項
- [x] #117 phase 2 / 4a / 5:五個 backend 的 list viewport
- [x] Review 4:兩個 ScrollViewReader,AppKit 與 Android 雙向驅動(P58)
- [x] heartbeats/:兩台機器以 session id 送達並實測

## 這份佇列是怎麼來的 / Where this list comes from

**它現在合併了三個來源,而先前只有一個。** 2026-09-09 對照 `todo.md`(樹裡唯一的待辦檔)與 Windows
端貼過來的表之後重建;先前的版本只反映了 Mac 這一側自己推進的工作,因此 Windows 端正在追蹤的項目
一個都不在上面。

**對照的第一個結果是刪掉工作,不是加上工作。** `todo.md` 中「六項交給 Mac」的表裡,有**五項在讀到它
時就已經完成了**——Swift 6 語言模式(AppKit 與 UIKit 都已在 `migratedToSwift6`)、前景色寫死
(`resolvedForegroundColor` 在兩個 backend 共 8 處)、Android 的 `.onHover`(已有
`AndroidBackend+HoverGestures.swift`)、UIKit 的 popover `onDismiss`(已指派)、UIKit 與 Android 的
`.navigationTitle`(兩邊的 toolbar 都會畫)。那張表自己就寫著「若條目超過一兩天,請先對照程式碼再
相信它」,而那正是它們被查證、而不是被重做的原因。

The list now merges three sources where it used to reflect one. Reconciling
against `todo.md` first REMOVED work rather than adding it: five of the six
items that file assigns to the Mac were already done when it was read, and its
own warning is why they were checked instead of started. A list of work is a
claim about the code, and it drifts towards describing work nobody needs to do.

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
