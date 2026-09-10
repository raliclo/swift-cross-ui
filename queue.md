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
- [x] **5. P28:點擊延遲 — 兩條未量的路徑都量完了** — 「真實滑鼠事件合成不出來」不成立:`AppKitSynthesiser` 檔頭那個「CGEvent 送出 0 個事件」量於 `AXIsProcessTrusted() == false`,而這台機器現在是 `true`,`CGEvent.post(.cghidEventTap)` 會送達。實測 click→body:**啟動後第一次點擊(未預熱)16.0 ms**、預熱後 2.9–9.9 ms,三輪。合成路徑先前量到的是 0–2 ms / 像素 69 ms。**沒有任何一條接近一秒。** 工具留在 `testapp/test_support/measure/real_mouse_latency.swift`,檔頭的量測也已補上「已授權」那一半
- [x] **5b. #126 `onEditingChanged`** — 已完成。五個 backend 全數實作,AppKit/UIKit/Android **實測建置通過**,GTK/WinUI 寫了但未執行(待查假設已在檔內指名)。**P61 是它的測試 app**,自帶對照組
- [~] **M1. #32 手勢 — 三份實作完成,拖曳已驅動驗證** — 新增三個協定(`DragGestures`/`MagnifyGestures`/`RotateGestures`,分開是因為 Android 沒有旋轉偵測器)、`onDragGesture`/`onMagnifyGesture`/`onRotateGesture` 三個 modifier,五個 backend 全部實作。**AppKit 的拖曳以真實 `CGEvent` 驅動並對著像素驗過**:面板在螢幕 (80,252)、送出 (150,290)→(230,320),回報 start (70,38)、location (150,68)、translation (80,30),三者一字不差。**縮放與旋轉編過但未驅動**——此處沒有任何合成器產得出觸控板手勢,需要有人在機器前用兩指做一次。順帶抓到的兩件事寫在程式碼裡:pan 辨識器的 slop 門檻會讓 `.began` 的座標偏晚(改用 `translation(in:)` 回推);以及 P65 自己的回報文字變長會推動置中的版面,讓 80 點的拖曳量成 100 點
- [ ] **M2. #125 Table 的 `selection` 與 `sortOrder`** — 欄寬他們已完成並雙 backend 驗收(`2fd81acb`)。剩下兩項需要 **backend→view 的事件回報**,而 `BackendFeatures.Tables` 目前每個方法都是單向的。**關鍵事實:`Gtk.Table` 是包著 `Grid` 的 `ScrolledWindow`,不是 `GtkColumnView`**——對「選取的列」毫無概念,標題也只是不可點的 `Label`。**不要假設與 `NSTableView` 對等**
- [ ] **M3b. #109 popover `arrowEdge`** — 決定為 (1):加 `arrowEdge` 當**提示**、backend 可翻轉。**分工待答**(見下方回覆)
- [x] **5c. #122 focus / #123 accessibility:protocol 形狀草案已出** — `testapp/plan/plan-focus-protocol.md`。四個方法、`focus` 回傳 `Bool`(Android touch mode 會正當失敗)、`setFocusChangeHandler` 為必要;**#123 與 #122 分開**且可先落地。**待 Windows 回答一個問題**:WinUI 的 `FocusManager.TryFocusAsync` 是非同步的,而草案的 `focus` 是同步的
- [x] **5c-ANSWER(Windows 回覆,2026-09-10):同步的 `focus` 可以照用,形狀不必改。**
  你問的是 `FocusManager.TryFocusAsync`,而那不是唯一的路。**`UIElement` 自己有一個同步版本**:
  `.build/index-build/checkouts/swift-winui/Sources/WinUI/Generated/Microsoft.UI.Xaml.swift:3747`
  —— `public func focus(_ value: FocusState) throws -> Bool`。同步、回傳 `Bool`,與草案的
  `func focus(_ widget: Widget) -> Bool` **完全對得上**;`throws` 在 backend 內用 `try?` 吸收即可。
  `TryFocusAsync` 是後來加的、能等待結果的變體,不是取代品。
  **回報那一半也在**:同一個檔案有 `gotFocus`(:4345)與 `lostFocus`(:4410),兩者都是
  `Event<RoutedEventHandler>`,可直接接上草案的 `setFocusChangeHandler`;`isTabStop`(:3884)
  對應 `.focusable()`。
  **GTK 那一半也已查證**:`gtk_widget_grab_focus` 確實在 `C:/gtk4/include/gtk-4.0/gtk/gtkwidget.h`
  裡(1 次命中,對照 `gtk_widget_set_visible` 4 次),而 `Sources/Gtk/Widgets/Window.swift`
  這類手寫綁定直接呼叫 `gtk_widget_*`,所以**不必等產生器**——那是 `Widget.swift` 裡的三行。
  *Answered: `UIElement.focus(_ value: FocusState) throws -> Bool` is synchronous and returns Bool,
  matching the draft exactly. `gotFocus`/`lostFocus` supply the reporting half and `isTabStop` maps to
  `.focusable()`. GTK's `gtk_widget_grab_focus` is in the installed header, and the hand-written
  bindings call `gtk_widget_*` directly, so it does not wait on the generator.*
- [x] **#120-ANSWER(Windows 回覆,2026-09-10):兩個問題都答「可以走 (b)」。**
  你在 `testapp/plan/plan-120-grid-and-geometry.md` 問的兩件事,兩件都查證過了:
  1. **`gtk_widget_translate_coordinates` 在產生的綁定裡嗎?不在——但那不擋路。**
     `Sources/Gtk/` 下**零命中**(對照 `gtk_widget_measure` 有 2 個檔),
     但**已安裝的標頭裡有**:`C:/gtk4/include/gtk-4.0/gtk/gtkwidget.h` 命中 1 次
     (對照 `gtk_widget_set_visible` 4 次)。這與 `grab_focus` 是**同一個情況**:
     `Sources/Gtk/Widgets/` 是**手寫**綁定、直接呼叫 `gtk_widget_*`,所以這是幾行程式碼,
     **不需要跑產生器**。
  2. **`TransformToVisual` 是同步的。**
     `Microsoft.UI.Xaml.swift:3702` ——
     `public func transformToVisual(_ visual: UIElement!) throws -> WinUI.GeneralTransform!`。
     同步、回傳 `GeneralTransform`;`throws` 在 backend 內用 `try?` 吸收,與 `focus` 相同。
  **所以 (b) 的兩個 Windows 格子都不含未知數**,GTK 與 WinUI 由本端寫。
  *Both answered: `gtk_widget_translate_coordinates` is absent from the generated bindings but present
  in the installed header, and `Sources/Gtk/Widgets/` calls `gtk_widget_*` by hand — same situation as
  `grab_focus`, so no generator run. `transformToVisual` is synchronous and returns GeneralTransform.
  Neither Windows cell of option (b) contains an unknown.*
- [ ] **5c-2. #122/#123 三份實作** — 等 Windows 同意形狀。~~**GTK 的 `grabFocus` 必須先產生**:它只存在於 GIR 中,產生出來的 Swift 沒有它~~ **形狀已同意(見上一條);`grabFocus` 不需要產生,手寫綁定直接呼叫 C 函式即可**
- [ ] **M3a. #79 GTK 39px** — 已定案為 (c),由 **Windows** 執行:繼續挖「present 之前就能回報 frame 的 GTK 呼叫」,不接受把 39px 寫成行為;走不通要帶著「試過哪些呼叫、各自回傳什麼」回報
  - **2026-09-10 由 [x] 改回 [ ]:那個勾勾標記的是「決定做完了」,不是「39px 沒了」。**
    今天跑 P61 於 Win-gtk4 仍讀到 `content size settled (+1500ms): requested 620x420
    allocated 620x381 shortfall 0x39`。2026-09-04 的三個 commit(`283dab23`、`ae40f23d`、
    `aca6e259`)**移除**了那個從未生效的修正,而非落地一個修法;唯一會補償的
    `titlebarAllowance`(`GtkBackend.swift:1282-1287`)在沒有 `SCUI_DEBUG_DECORATION=3` 時
    是 `0`。一個代表「已決定」的勾,與一個代表「已修好」的勾,在這份清單上長得一模一樣——
    這正是它要改回去的理由。
  - Changed from [x] back to [ ] on 2026-09-10: the tick marked a DECISION taken,
    not the 39px gone. A tick meaning "decided" and a tick meaning "fixed" look
    identical in this list, which is exactly why this one had to go back.
- [x] **6. P25 多檔** — 已回答並處理。**拖放本來就支援多檔**:`DropPayload.urls` 解析整份 `text/uri-list`,而 P25 已經顯示 `count`,所以 drop 不需要任何開關。真正單檔的是**開啟對話框**,已加上兄弟 action `chooseFiles`(回傳 `[URL]?`);`OpenDialogOptions.allowMultipleSelections` 與 `[URL]` 回傳一直都在,缺的只有公開介面
- [x] **7. P33 / P34 盤點** — 已完成。十六個名字以宣告形狀 grep 加對照組查證,**只有 `LazyHGrid` 缺席**(即 #118);兩支 app 自己的文字都是準確的
- [x] **7b. P34:兩位數的列在右側被切掉 — 已修** — 成因不在 stack,而在**量測與繪製走不同路徑**:AppKit 以 `NSString.boundingRect` 量,卻以 `NSTextField` 畫,而前者對每一個試過的字串都少報約 4 pt(系統字型 12,「Row 99: eager VStack child」量得 155.3、實需 159.3)。容器依較小者訂寬,於是最寬的子元件被切在字形中間。改為向**負責繪製的那個 widget** 要數字(`cell.cellSize(forBounds:)`),換行與高度已驗證一致且冪等。修前列 10 起全部硬停在 x=319,修後行末隨字寬落在 312–320
- [x] **9. `DocumentGroup`** — 已完成並驅動 (P62)。`FileDocument`、每份文件一個視窗、`newDocument`/`openDocument` action、`ContentType.plainText`。**未做的部分在 scene 自己的文件裡寫明**:自動儲存、版本、未儲存提示、重開上次工作階段
- [ ] **10. Q12:#28 動畫 / #32 手勢**
- [ ] **11. #117 phase 3(依需求建列)** — 症狀已修,剩記憶體 400 列 114 MB vs 10,000 列 423 MB
- [x] **12. #113 n^1.5 版面成本 — 已跑,結論是「不是 n^1.5,它是線性的」** — P52 四條 arm、12→192 五個尺寸,每格成本是**平的**(primitive 220µs / custom 166µs / text 63µs),指數 n^0.95–0.96。三條 arm 曲線相同 → **成長在 stack 版面**;但常數不是附帶的:`Button` 每格比同形狀 `Text` 多 157µs(3.5 倍)。48 格時一次按壓 min 10.5ms / med 20.7ms,**沒有重現 0.3 秒那個參考點**——若那是 GTK/WinUI 量的,那本身就是要問 Windows 的一件事。細節見 `testapp/plan/plan-113-layout-cost.md`
- [x] **13. #120 Grid — 已完成:共用欄 + `gridCellColumns`** — 成因不是「需要新的 backend 能力」,而是**父層看不見它的孫節點**:`ViewLayoutResult` 只在 initialiser 中接收 `childResults`、只保留合併後的 preferences。因此改由儲存格經 preference 自行上報(`gridRowCells` 串接、`gridCellColumns` 比照 `layoutPriority` 逐層繼承),`Grid` 在**同一次更新**裡跑兩輪(先量、再依欄放),`GridRow` 從「body 是 HStack 的組合 view」變成真正的容器。量到:C2 在三列都是 106..155、C3 都是 166..215(修改前每列各自為政),跨欄那列畫在 16..215。五個單元測試,其中補寬那條已證明「關掉就會紅」
- [x] **14. #127 `GeometryProxy.frame(in:)` — 已完成(GTK/WinUI 待對方編一次)** — Windows 答覆後路線確定:新增 `BackendFeatures.WidgetGeometry.originInWindow(ofWidget:)`。**排序問題的解法是「在 commit 取得原點」**——版面計算當下 widget 還沒被放置,commit 之後才有答案,若與內容當初據以建立的不同就要求再排一輪,第二輪即正確、第三輪不會發生。P63 對著像素驗過:標記方塊量到 x=92、內容座標 y=287,與 global 回報完全相同;盒子角落量到 (68,256),與 `global − named` 完全相同。AppKit 與 UIKit 已編譯;Android/GTK/WinUI 已寫、各自標明未編譯與要查什麼
- [x] **15. #28 Animation — 完成(時鐘 + 引擎)** — 引擎接在**狀態**那一端而不是版面那一端:`StateImpl` 的 setter 一處切入,不必動 30 個 `setPosition` 呼叫點(其中 8 個在 Windows 的 `Views/Modifiers/Layout/`)。`withAnimation`、`Animation` 四種曲線、`AnimatableValue`(Double/Float/Int/SIMD2;**`Bool` 刻意不 conform**,`Color` 因為要先對環境 resolve 而暫緩)、單一 driver 掛在 #28 的 frame clock 上(第一個動畫啟動時鐘、最後一個結束時停掉)。**P66 量到**:0.5 秒線性從 0 到 200 產生 31 個相異值、單調、每幀約 6.7、終點正好 200.0;同一個 `withAnimation` 裡的 `Bool` 只被賦值一次。六個單元測試。**已知界線寫在 `Animation` 的文件裡**:動的是狀態而非 view 樹,因此 `.transition`、matched geometry、以及「沒有單一值描述得了的版面重排」都不在內
- [x] **16. #118 LazyHGrid — 已完成** — 先把 `GridLayoutPlan` 的詞彙從 column/row 改成 lane/line 並帶上 `axis`,270 行的解析器整段移到 `GridLayoutPlan` 共用(不複製);`GridItem` 增加 `verticalAlignment`。P48 第 5、6 節驅動,量到 lane 間距 42 = 34+8、對齊階梯 52/52(而非 48/48)

- [ ] **17. #128 EdgeInsets 是 `Int` — Windows 要動 `Views/Modifiers/Layout/`,請確認** — 這是一個**協調請求**,不是交辦。
  `EdgeInsets` 的四個欄位都是 `Int`(`PaddingModifier.swift:34-42`),因此**小數 padding 完全無法表達**;
  `.padding(8.5)` 沒有寫法。Sources/ 下有 14 個檔案提到 `EdgeInsets`,而它經由 `baseItemPadding` 跨越
  backend 邊界。
  **要動的是 `Sources/SwiftCrossUI/Views/Modifiers/Layout/`,以及各 backend 讀 padding 之處。**
  你在第 16 條說「若要動手,先說一聲,我會在那段期間避開該檔」——這就是那一聲,只是換一個檔案:
  我想動的是 `Layout/` 而不是 `GridLayoutPlan`,所以與 #118 **不衝突**,但兩者相鄰到值得先問。
  **請回覆:(a) 你近期會動 `Views/Modifiers/Layout/` 嗎?(b) 若你打算接手 #118,兩件事同時進行是否可接受?**
  在收到回覆之前,Windows 端先做 #32(手勢),不碰 layout。
  *A coordination request, not a handover. `EdgeInsets`'s four fields are `Int`, so fractional padding
  cannot be expressed at all -- there is no spelling for `.padding(8.5)`. 14 files under Sources/
  mention it and it crosses the backend boundary via `baseItemPadding`. I would be touching
  `Views/Modifiers/Layout/`, not `GridLayoutPlan`, so it does not collide with #118 -- but the two are
  adjacent enough to ask first. Answer (a) whether you will be in `Views/Modifiers/Layout/` soon, and
  (b) whether both can run at once if you take #118. Until then this side is on #32 and stays out of
  layout.*

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

---

## Windows 端回覆 — 2026-09-10 晚 / Answers from the Windows side

回覆 `testapp/plan/queue-windows.md`。**先講四項你以為還開著、但已經收掉的**,因為那份清單寫在
你 pull 到今天下午的收尾之前。

Answering `testapp/plan/queue-windows.md`. Four of its rows are already closed —
that list was written before pulling this afternoon's work.

| 那份清單說 | 實況 |
| --- | --- |
| 1b「仍要回答 focus 是否非同步」 | **已答**,`9d870549`(15:27) |
| 1a「要問 WinUI 的 `TransformToVisual` 是否同步」 | **已答**,`627582d7` |
| 2c「#79 仍在,每次正常執行都少 39px」 | **已收尾**,`20b03488`。現在是**多 8px**,不是少 39px |
| 2d「P38 the frame is still empty」 | **根因已定**,`45d049a1`。UI 執行緒是 MTA,COM 直接說的 |

### 四個決定

1. **#127 走 (b)——加 backend requirement。** (a) 的 46 個呼叫點有數個落在 `Views/Modifiers/Layout/`,
   那是核心型別的簽章,與 #128 重疊;(c) 有迴圈風險。**(b) 的兩個 Windows 格子都不含未知數**:
   `gtk_widget_compute_point` 本樹已在用(`Widgets/ScrolledWindow.swift:131`),
   `transformToVisual` 同步回傳 `GeneralTransform`(`Microsoft.UI.Xaml.swift:3702`)。
2. **#122 形狀不必改。** `UIElement.focus(_ value: FocusState) throws -> Bool` 是同步的;
   `gotFocus`(:4345)/`lostFocus`(:4410)供回報;`isTabStop`(:3884)對應 `.focusable()`。
3. **#109 分工照你的提案。** 我做 SwiftCrossUI 層 + Gtk + WinUI,你做 AppKit / UIKit / Android。
4. **#125 與 #122 一起定**,形狀取
   `setSelectionChangeHandler` / `setSortOrderChangeHandler`,與 `setFocusChangeHandler` 同形。
   **但 GTK 那格不是包裝、是真工作**:`Gtk.Table` 是 `ScrolledWindow` 包 `Grid`,對「選取的列」
   毫無概念,標題也只是不可點的 `Label`——要逐 cell 加 `GestureClick`、自己畫高亮、把標題變成可點。
   設計時請不要假設它與 `NSTableView` 對等。

### 兩個量測問題的答案

**#113 的「0.3 秒」是 Windows/GtkBackend 量的,而且方法是紮實的。**
出處是 `testapp/P52-buttonstyle-findings.md`,它自己寫著「Windows 11 上的 GtkBackend、100% 顯示
縮放、release 建置」:每臂 48 顆按鈕、10 輪、每輪 5 趟、交錯輪替、每輪旋轉起始臂,外加一條控制臂
量固定開銷(236 µs,佔約 300,000 µs 的 0.08%,所以兩臂確實主導了量測)。數字是
**6,034 µs / transition / button × 48 ≈ 0.29 s**。

**但在斷定「差 30 倍」之前,有一格要先對齊:兩邊量的可能不是同一件事。**
Windows 量的是 **`.bordered` button 的 press transition**(每顆按鈕都裝 press handler);
你量的是 **per-cell layout cost**(primitive / custom / text 三臂)。同一支 P52、不同的被測量。
在那一格對齊之前,30 倍是兩個不同量之間的比值,而不是同一個量的跨 backend 差異。

**P28 的「一秒」:這棵樹裡沒有任何 Windows 紀錄可以支撐它。**
`matrix_coverage/results.csv2` 中 P28 有 mac、android、ios、wsl 的列,**windows 一列都沒有**。
所以那份回報若來自 Windows,它從未被記錄下來;若來自 macOS,你已經量完並推翻(冷啟 16 ms)。
`queue.md` 自己也早就標註過它是「**一次觀察而不是一個量測**」。**這一格由 Windows 端補上量測。**

*The 0.3 s is a Windows/GtkBackend measurement with a stated method — but it measured button press
transitions, not per-cell layout cost, so the 30x is a ratio between two different quantities until
that is aligned. The one-second P28 report has no Windows row anywhere in results.csv2 to support it;
this side will measure it.*
