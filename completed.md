# completed.md

Finished items moved out of queue.md by Scripts/archive_done.zsh once no line
of them had changed for a week. The text is as it was in queue.md; the
headings say which queue.md section each block came from.

由 Scripts/archive_done.zsh 從 queue.md 搬來的已完成項目：每一行都已一週沒有改動。文字與在 queue.md
時相同；標題標明每一塊原本位於 queue.md 的哪一節。

## Archived 2026-10-05 from queue.md

### 2026-09-27 found while driving iOS

- [x] **Re-measure the iOS action files: most of them no longer aim at their
  controls.** **DONE 2026-09-28**: full sweep `testapp/output/ios-sweep-full4.csv2`,
  74 of 74 replayed, every capture read against its file's assertion; the four
  misses that sweep still counted as passes (P29, P31, P46, P65) were re-aimed
  and re-run. Along the way RootScrollHost stopped disabling the pull under a
  refresh control (P54). Seven apps stay out of the matrix because the capture
  cannot evidence them -- see results.csv2 for 2026-09-28. The iOS sweep replayed and captured all 73 files, and that meant
  nothing, because a tap on empty space is not an error. Checked against the
  accessibility tree on the corrected layout (RootScrollHost 150446ef), only 15
  files have every positioned row landing on its named target; the rest land on
  nothing, or on the wrong thing -- a heading, a paragraph, the neighbouring
  button. They were measured on the old layout, which jumped under the first
  touch by an amount that depended on timing. The row-by-row table, with a
  candidate for each, is `testapp/measurements/ios-aim-20260927.txt`. Three
  kinds of fix: (1) a named control -- take the tree centre, minus the window's
  y origin of 2; (2) a toggle -- the Switch element, not its label; (3) content
  wider than 440 pt (P2, P3, P17, ...) -- a horizontal scroll first, because the
  corrected layout starts at the left edge and scrolls to reach the rest, where
  the old one centred the content and cut both sides. Check every file's
  assertion on its capture before counting it; results.csv2 carries
  `replay=misaimed` for the 49 apps still waiting, so coverage.md says so.
  **重新量 iOS 動作檔:它們大多已不再瞄準自己的控制項。**iOS sweep 重放並擷圖了全部 73 份檔案,而那
  什麼也沒證明,因為點在空白處不算錯誤。以修正後版面(RootScrollHost 150446ef)的無障礙樹核對,只有 15 份
  檔案的每一個定位動作都落在它所指名的目標上;其餘的落在空處,或落在錯的東西上。逐列對照表與候選座標在
  `testapp/measurements/ios-aim-20260927.txt`。
- [x] **FIXED 2026-09-28 (the lost model; the over-eager re-creation remains).**
  `ObservedObject.update` keeps its carried object when the incoming one is
  referenced by nothing but the wrapper's own storage -- an object built by the
  wrapper's `= Model()` during a re-creation, which cannot be a parent's next
  object -- and still adopts one a parent holds and passes. Tests:
  `ObservedObjectTests`, two directions, each shown to fail with its half of the
  rule removed (the first version passed either way: without `commit()` the layout
  cache returned before the new view was looked at). P45 model button on macOS:
  honest true, writes 1, presses 1, siblings kept. Android still compiles (with the
  26.5 SDK workaround). NOT changed: re-creation itself, so an initialiser used as
  a @State or @ObservedObject default still RUNS on every re-creation (SoftPCB-mac
  counted 28) -- that needs the parent to stop re-evaluating `body` on a child's
  resize, a layout-system change left open below.
- [x] **Core: a view's own @State change re-creates it from its parent, and an inline
  `@ObservedObject var m = Model()` is replaced each time.** Measured 2026-09-28 on
  macOS with P45 (a construction counter was added to P45Model): one run of
  P45-press-the-model-button.csv constructed the model 8 times -- at launch, on each
  seed button (@State), and on the model button, which also writes @State
  `presses`. The model button's flip lands on the old instance and the screen then
  shows the new one: button presses 1, setter writes 0. The toggles that only touch
  the model keep their state, because nothing re-creates the view. `bottomUpUpdate`
  propagates to the parent, the parent re-evaluates its body, `P45RootView()` is
  built anew, and `ObservedObject.update(previousValue:)` adopts the incoming
  object whenever it differs. `@State` and `@StateObject` carry their previous
  storage and survive (P45's own `presses`, P46). SwiftUI re-runs only the body.
  Fix candidates: stop a child's state change from re-evaluating an ancestor's body
  (the real deviation), or have ObservedObject keep its carried object when the
  incoming one was produced by the wrapped-value initialiser. Core, all backends;
  measured on macOS only. SoftPCB-mac's GeometryRenderTab reset with `@State var
  model = XModel()` (seen 2026-09-07) does NOT reproduce on 2026-09-28: with two
  extra @State properties changed in the same action, one model ObjectIdentifier
  throughout and the selection kept -- consistent with State carrying its storage.
  The 09-07 shape was never committed; cause unknown, closed on their side. Their
  side finding belongs here: `XModel.init` ran 28 times in one short run, because
  every re-creation of the view struct evaluates the @State initial-value
  expression. The stored object wins and the new one is discarded, but any side
  effect in an initialiser runs each time -- the same over-eager re-creation, seen
  from a wrapper that survives it. SwiftUI evaluates that expression on struct
  init too, but re-creates structs far less often.
  **核心:view 自己的 @State 改變會讓父層重建它,而內嵌的 `@ObservedObject var m = Model()` 每次都被換掉。**
  2026-09-28 以 P45 在 macOS 實測:一次執行建構了 8 次 model;按鈕的 flip 落在舊實例上,畫面上是新的那一個。
  @State 與 @StateObject 會沿用先前的 storage,不受影響。
- [x] **Read every macOS capture against its file's assertion, as was done for iOS.**
  **DONE 2026-09-28.** Every capture of the full macOS sweep read; the misses
  re-aimed or rewritten, three real defects fixed (open/save panels unreachable,
  scroll direction on SwiftCrossUI ScrollViews, Escape on one-button alerts, plus
  alert stacking), one core defect found (above). Second full sweep 83 of 83 with
  every capture read; results.csv2 for 2026-09-28 has the list.
  The 2026-09-27 macOS sweep (81 of 81) checked that each replay ran and took a
  capture, not what the capture shows. P2 proves that is not enough: its y values
  were 12-17 pt off, the capture read `options: 2` with the button row still
  disabled, and it was counted a pass and filled ✅ in the matrix. Fixed for P2 on
  2026-09-28; the other 80 files have not been read. Tell SoftPCB-mac before and
  after, since the runs take the screen.
  **像 iOS 那樣,把每一張 macOS 擷圖對照它檔案的斷言讀一遍。**2026-09-27 的 macOS sweep(81/81)只檢查
  重放有沒有跑、有沒有擷圖,不看擷圖內容。P2 證明那不夠:它的 y 值偏了 12-17 點,擷圖讀到 `options: 2`、
  按鈕列仍停用,卻被算成通過並在矩陣填了 ✅。P2 已於 2026-09-28 修好;其餘 80 份尚未讀過。
- [x] **WITHDRAWN 2026-09-28 -- not a defect.** Pop to root sets pushCount = 0
  (P24.swift), and the action file popped after recording. With the app's stdout
  captured (test_ios.zsh now launches through a pty) the record logs "push recorded
  at level 0" and the next Increment logs "pushes 1"; the capture reads 1. The file
  is rewritten to end at Level 1 / pushes 1 / counter 1, and passes. Original entry:
  **iOS P24: "Record a push" leaves `pushes recorded (outside the stack)` at
  0.** Found 2026-09-02, still so on 2026-09-28. The tap is at (180, 619) and the
  button is at about (183, 621) on p24-ios-final-20260928-054747.png, so it is
  probably not the aim -- but that is inferred, not shown: the app's `[P24]` lines
  (`push recorded at level ...`) do not reach ios-P24-debugTarget.log, so nothing
  says whether `onPush` ran. Next step: get the app's stdout on iOS, then tell
  "tap missed" from "state written inside a NavigationStack destination does not
  reach the view outside it".
  **iOS P24:「Record a push」讓 `pushes recorded (outside the stack)` 停在 0。**點擊在 (180, 619),
  按鈕約在 (183, 621),所以大概不是瞄準問題——但那是推論:app 的 `[P24]` 輸出沒有進到 log,沒有東西說明
  `onPush` 有沒有執行。下一步:在 iOS 上取得 app 的 stdout,再分辨「沒點到」與「stack 內寫入的狀態傳不到外面」。
- [x] **Core crash, ViewGraphNode.swift:13 (`_widget!`): a publish that arrives
  while the view graph is still being built.** **FIXED 2026-09-27 and verified on
  macOS and iOS; Android not built (toolchain, see the matrix note), GTK/WinUI
  are the Windows side's.** Reproduced here with testapp/P73 -- `.onAppear`
  publishes, then spins the run loop as `waitUntilExit` does: macOS 10/10
  crashed, 0/10 after the fix, control 0/10 both ways; iOS crashed before and
  shows the published value after. The nested run loop in SoftPCB-UI was its own
  `waitUntilExit` inside `body` (their full backtrace, frame 50); the fix is in
  `ViewGraphNode.bottomUpUpdate`: a node that has not had its first layout does
  not start a bottom-up update. The original report follows.
  Reported 2026-09-27 by the
  SoftPCB-mac session, measured THERE on AppKitBackend at 1113a310. This is the "empty ForEach" crash of 2026-09-08,
  and the diagnosis it had was wrong: it is timing, not structure.
  Backtrace, top down: `ViewGraphNode.widget.getter` <- `computeLayout` <-
  `bottomUpUpdate` <- `updateEnvironment` closure (~8 levels) <- closure in
  `ViewGraphNode.init(for:backend:snapshot:environment:)` <- closure in
  `Publisher.observeAsUIUpdater`. So an observer registered during init fires a
  bottom-up update that reaches a node whose `_widget` is not assigned yet.
  Evidence: an `.onAppear` job that publishes back via `DispatchQueue.main.async`
  crashes when it finishes at once and not when it sleeps 0.5 s or 2 s first;
  6/10 crash unchanged, 1/10 with one extra main-queue hop -- lower odds, same
  race. Guarding or moving the ForEach, or making every conditional non-empty,
  all still crashed in SoftPCB-UI. `ef26b83e`'s six static shapes cannot
  reproduce it because none publishes during init; keep them as negatives.
  Next: build a standalone Pn (a model whose `.onAppear` publishes almost at
  once, with enough views that construction spans more than one main-queue
  turn), reproduce, and only then fix -- probably by deferring or dropping
  bottom-up updates that reach an unbuilt node. The SoftPCB-UI recipe is kept in
  that session: SOFTPCB_ROOT holding only analysis/workflows.csv2, CLAUDE.md and
  an executable scripts/solver_preflight.zsh containing `exit 0`.
  **核心崩潰,ViewGraphNode.swift:13(`_widget!`):view graph 還在建構時就有一次發布抵達。**
  2026-09-27 由 SoftPCB-mac session 回報,在**那邊**以 AppKitBackend、1113a310 量到;**這棵樹裡尚未重現。**
  它就是 2026-09-08 的「空 ForEach」崩潰,而當時的診斷是錯的:它是時序,不是結構。證據:一個 `.onAppear`
  的工作透過 `DispatchQueue.main.async` 發布回來,立即結束就崩、先睡 0.5 秒或 2 秒就不崩;未修改 10 次崩 6 次,
  多一次主佇列跳轉 10 次崩 1 次——機率降低,同一個競態。`ef26b83e` 的六個靜態形狀重現不了它,因為沒有一個在
  init 期間發布;留著當反例。下一步:先寫一支獨立的 Pn 重現它,重現之後才修。
- [x] **WITHDRAWN 2026-09-27 -- there is no defect; the entry below was wrong.**
  P21 declares `@State var switchState = true`, so the switch STARTS on. A probe
  in `updateSwitch`/`setState` showed the whole sequence: `setState true` at
  launch, then on the click `onAction state=0` (on -> off), `onChange(false)`,
  `setState false`. The enabled switch flipped true -> false, the disabled one
  never fired an action, and `false` is exactly the readout a correct backend
  produces. The "defect" was read from the final state without checking the
  initial one; the HID-click "confirmation" looked at the same final state and
  could not have said otherwise. mistakes.md entry 30.
  **2026-09-27 撤回——沒有缺陷;下面這條是錯的。**P21 宣告 `@State var switchState = true`,所以開關
  一開始就是開的。探針顯示完整順序:啟動時 `setState true`,點擊時 `onAction state=0`(開 -> 關)、
  `onChange(false)`、`setState false`。啟用的開關從 true 翻到 false,停用的從未觸發 action,而 `false`
  正是正確的 backend 會產生的讀數。那個「缺陷」是只看最終狀態、沒有確認初始狀態就讀出來的。
  ~~**AppKit: an ENABLED `Toggle` with `.toggleStyle(.switch)` cannot be
  switched on.**~~ P21's readout stays `ToggleSwitch style -- false` after a click
  on the enabled NSSwitch, and the switch is drawn off. Not the coordinates:
  `-hittest: hit NSSwitch at (104,408)` for the synthesised click. Not the
  synthesiser either: a system-level CGEvent click through the HID tap, which is
  what a real mouse produces, hits the same NSSwitch and leaves it off too.
  `updateSwitch` does set `onAction`, so the fault is further down -- how
  `onAction` is wired for NSSwitch, whether `AppKitHitTestingContainer` keeps
  the tracking loop from reaching the switch, or an update resetting the state.
  The macOS sweep counts P21 as a pass (it replays and captures), which is
  exactly the limit sweep_apple.zsh's header states; the matrix row is amber.
  **AppKit:一個**啟用中**、套用 `.toggleStyle(.switch)` 的 `Toggle` 無法被打開。**點擊啟用的
  NSSwitch 之後,P21 的讀數仍是 `ToggleSwitch style -- false`,開關也畫成關的。不是座標:合成的點擊
  `-hittest: hit NSSwitch at (104,408)`。也不是合成器:經由 HID tap 的系統層級 CGEvent 點擊(也就是真實
  滑鼠產生的東西)命中同一個 NSSwitch,它一樣沒有打開。`updateSwitch` 確實設了 `onAction`,所以問題在更下層
  ——NSSwitch 的 `onAction` 怎麼接、`AppKitHitTestingContainer` 是否讓追蹤迴圈到不了開關、或某次更新把狀態
  重設了。macOS sweep 把 P21 算成通過(它有重放、有擷圖),而那正是 sweep_apple.zsh 檔頭所說的限制;
  矩陣那一列標為琥珀色。

### 2026-09-12 Windows / WSL handover

- [x] **#117 GTK ListView integration and P57 verification — 2026-09-16 完成**:
  GtkBackend now uses the native lazy factory. Release builds succeeded on
  WSL and Windows including the latest lifetime change.
  Initial WSL GL/D3D12 probes: 1/400/10,000 rows used 320/326/327 MB after
  settling; 10,000 model rows had 205 realized containers (206 after scrolling).
  Initial selection was nil and selecting the last row reported 9999.
  Final native probes on both platforms also confirmed Clear, revision updates
  and 10,000 -> 1 -> 10,000 rows; container counts changed 205/206 -> 1 -> 205.
  Wincap now uses Windows Graphics Capture. After restarting a stale WSLg COPY
  MODE bridge, final WSLg/Windows GL captures measured 92.2%/92.1% non-black;
  PIL confirmed matching 668x776 images and content bounds. Track current
  evidence and outstanding checks in
  `testapp/plan/plan-backend-followup-20260912.md`.
  GTK 接入、生命週期修正、兩端原生狀態及截圖驗證已完成；黑圖成因是過期的 WSLg
  COPY MODE bridge，加上舊 PrintWindow 路徑無法讀取 GPU surface。真實指標輸入與
  WinUI 回歸亦已完成，見以下 2026-09-16 更新。
  **2026-09-16 更新:GtkBackend 的 `LazyListRows` 已完成(`5739d453`),而一次原始碼掃描
  會說它沒有——它是由 `LazyListRowLifetimes` 繼承而來的,那個 extension 兩個方法都實作了。
  WinUI 的 `LazyListRowLifetimes` 也已完成並以對照組量過(release 146/150 MB 對
  control 221/222 MB,掃過 5000 列)。~~此條**唯一剩下的**是 P57 在 gtk4 上的指標重放。~~
  **18:58 那筆重放也完成了,20 個動作全數落地:`selection=1`;捲動六格後點**同一個 y** 得到
  `selection=8`(這就是本檔的主張——清單真的捲動了,不只是重畫);`revision=1`;`Clear` 後
  `selection=none`;`Toggle count` 走過 `rows=1 → rows=400`,而重建後 `Select last` 仍正確地
  回報 399。**此條可以關掉了。****
  *2026-09-16: GTK's `LazyListRows` is done and INHERITED, so a name-based sweep reports it
  missing; WinUI's `LazyListRowLifetimes` is done and measured against a control.
  The final GTK pointer replay also completed at 18:58: selection 1 -> 8 after
  scrolling, revision 1, cleared selection, rows 1 -> 400, and last selection 399.
  GTK pointer replay and WinUI regression are complete.*
- [x] **1. iOS 動作檔的點擊沒抵達按鈕** — 已解決。按鈕實際在 (55, 218) 點,先前的 y=100 是從縮圖估的。runner 現在會說出它解析到哪個視窗與正規化後的座標
- [x] **2. 動作檔無法定址第二個視窗** — 已解決。新增 `focus` 動作(第十欄 `target` 放標題),並補上 AppKit 缺少的 `currentWindowIdentity()`——沒有它,geometry 永遠不會重新量測
- [x] **1. P50 macOS:「Show title B」按了標題沒變** — 已修。狀態改變若不改變尺寸,就不會有人告訴視窗 preference 變了;新增 `onWindowChromeChange` 通道
- [x] **2. P50 macOS:「按下 press me 後文字位移」—— 不重現,三個 backend 數字一致(2026-09-19 結案)**
  - **量法由 Windows 那邊提供的對照決定**:`--auto-press 9` 把計數停在 9,再按一次到 10
    ——數字進位、按鈕寬度會變,是最可能推動東西的那一次。
  - **AppKit 的結果:唯一改變的是 33 x 21 像素,就是那幾個字元本身**(`9)` 變成 `10)`),
    面板**沒有**關閉,主視窗零位移。與 WinUI 的 30 x 29、GTK 的 35 x 34 是同一個形狀。
  - 因此**那兩個原本要你回答的問題,量測自己答了**:位移發生在**面板內**,而按下時面板**不會**關閉。
  - **量法本身出過兩次錯,都記在此處,因為兩次都會產生一個看起來合理的結論:**
    (1) 以牆鐘時間抓擷圖,兩張都落在按下**之後**,差異為零——那讀起來像「完全沒有位移」,而其實是
    「兩張一樣的圖」;(2) 第二次改了時間,before 那張落在面板**出現之前**,差異變成整個面板 325 x 203,
    那讀起來像「整個面板都動了」。正確做法是**以 app 自己的 log 行為準**去等
    (`popover alpha shown` → 拍 before;`popover counter 10` → 拍 after)。
  - **順帶修掉兩份過時的動作檔**:`P50-open-first-panel.csv` 與 `P50-panel-press-me.csv` 裡那顆
    「Open the first panel」按鈕座標由 (227,646) 改為 (231,677)。舊座標打在一個 `NSCustomTextField` 上,
    而**重放仍然以 0 結束**——唯一的跡象是事後那行 geometry 寫著 `popover=none`。兩份都已重放驗過。
- [x] **2b. P50:一次 light dismiss 觸發兩次 `onDismiss`** — 已修。`NSPopover` 會把「實作通知形狀方法的 delegate」自動註冊為該通知的觀察者,於是同一個方法被送達兩次
- [x] **2c. 動作檔已能驅動 AppKit 的 popover** — 兩件事要一起改:(1)`targetWindow()` 不再回傳 popover——popover 會取得 key,於是每一個**非** popover 的座標都在對它解析,而檔案照樣重放成功、每次點擊都落在某個看似合理的位置;(2)`origin=popover` 的事件投遞到 **popover 自己的視窗**,投給後方的視窗會把它 light-dismiss,而「被關掉的 popover」與「沒打中的點擊」是同一張圖。`popoverOrigin` 取的是**內容區**而非視窗框(框比畫出來的面板大 26 點,含箭頭與陰影)。實測:`P50-panel-press-me.csv` 讓 P50 記下 `popover counter 1`
- [x] **3. P32:Toggle 沒有可見的開啟狀態** — 已修。`onStateBezelColor` 來自 `environment.toggleColor`,app 沒設就是 nil,於是「開」什麼都不畫;改為退回 `.controlAccentColor`
- [x] **4. P44:vertical stack 空間耗盡** — 已修:那是誤報。`offered 643 / took 643` 相等,什麼都沒不夠;是 `Spacer` 在沒有餘裕時正確地拿到 0。回報條件補上「確實溢出」,與它自己的訊息一致
- [x] **5. P28:點擊延遲 — 兩條未量的路徑都量完了** — 「真實滑鼠事件合成不出來」不成立:`AppKitSynthesiser` 檔頭那個「CGEvent 送出 0 個事件」量於 `AXIsProcessTrusted() == false`,而這台機器現在是 `true`,`CGEvent.post(.cghidEventTap)` 會送達。實測 click→body:**啟動後第一次點擊(未預熱)16.0 ms**、預熱後 2.9–9.9 ms,三輪。合成路徑先前量到的是 0–2 ms / 像素 69 ms。**沒有任何一條接近一秒。** 工具留在 `testapp/test_support/measure/real_mouse_latency.swift`,檔頭的量測也已補上「已授權」那一半
- [x] **5b. #126 `onEditingChanged`** — 已完成。五個 backend 全數實作,AppKit/UIKit/Android **實測建置通過**,GTK/WinUI 寫了但未執行(待查假設已在檔內指名)。**P61 是它的測試 app**,自帶對照組
- [x] **M2. #125 Table 的 `selection` 與 `sortOrder` — 兩項都已完成於五個 backend(2026-09-16)** — selection:`BackendFeatures.TableSelection` 落地,Windows 兩個 backend 由此側實作、AppKit/UIKit/Android 由 Mac 實作,**兩個方向都以真實輸入驅動驗過**(探針寫 binding + 動作檔點擊,含「點標題列不得選取」的拒絕對照)。`sortOrder`:同樣五個 backend 到齊,細節見下方各條。以下為原始說明,保留作為背景:欄寬他們已完成並雙 backend 驗收(`2fd81acb`)。剩下兩項需要 **backend→view 的事件回報**,而 `BackendFeatures.Tables` 目前每個方法都是單向的。**關鍵事實:`Gtk.Table` 是包著 `Grid` 的 `ScrolledWindow`,不是 `GtkColumnView`**——對「選取的列」毫無概念,標題也只是不可點的 `Label`。**不要假設與 `NSTableView` 對等**

  - **`sortOrder` 已完成。** Windows 落地了協定 `BackendFeatures.TableColumnSorting`、`TableSortOrder`
    與兩個 Windows backend(`b308559a`);本機接著落地 AppKit / UIKit / Android,三個平台各以動作檔實測,
    七支新檔 + 先前五支 selection 檔全數重跑(P23 版面改過兩次,座標重量過兩次)。
  - **形狀以 origin 的為準,而我那份被丟棄。** 兩邊在同一段時間各自寫了一版:我的 `setSortHandler`
    回報 `TableSortOrder?`、由每個 backend 自行決定「同一欄反轉」;他們的回報 `column: Int`,由框架的
    `TableSortOrder.toggled(byClicking:)` 決定一次。**他們的比較好**——我那版等於讓那條規則在
    AppKit/UIKit/Android 各存在一份,而三份之間的任何差異,都會以「某個平台的標題行為不一樣」現身。
    這是 mistakes 第 12 條的第二次發生,而這次兩邊都先查過對面、對面當時是乾淨的。
  - **順手修掉 P23 自己的一個缺陷:** 排序讀數原本與按鈕同一行,`sort: column 3 ascending` 在手機上會
    折成兩行、把表格往下推,於是「在標題上點兩次」的動作檔第二次會落空——而擷圖看起來像是
    「backend 忘了自己的排序狀態」。已改為獨立一行,理由寫在 P23.swift 裡。
- [x] **M4. #121 在 iPhone 上已補上 — `UIResponder.keyCommands`(2026-09-16 完成並驅動驗證)** — UIKit 的 `#121` 目前是
  **iPad ✅ / iPhone ❌**,而那不是「平台沒有 API」。唯一的註冊路徑是 `buildMenu(with:)`
  (`UIKitBackend+Menu.swift:215`),而 iPhone 沒有選單列、`buildMenu` 從不以 `.main` 被呼叫
  ——2026-09-16 在 iPhone 17 Pro Max 上量過,寫在 `actions/ios/P71-shortcuts.csv` 的檔頭。
  `grep -rn keyCommands Sources/UIKitBackend` 回報 0:沒有任何地方覆寫 `UIResponder.keyCommands`,
  而那正是 iPhone 上「不需要選單列」的那條路。依 CLAUDE.md,這是待實作,不是可以記成 ✅ 的東西。
  - **同一個動作檔在兩種裝置上都通過:** iPhone(預設的 `swift-cross-ui` 模擬器,iOS 27.0)
    plain 1 / shifted 1 / disabled 0——**那正是今天之前回報三個零的那台裝置**;
    iPad Pro 13-inch (M5) 同樣是 1 / 1 / 0,而那才是真正要防的回歸:一個被公布兩次的快捷鍵會觸發兩次。
  - **`ApplicationDelegate` 現在覆寫 `keyCommands`。** 那些 command 在 `setApplicationMenu` 中
    由一次選單走訪造出——**帶著快捷鍵的是 `modifiedEnvironment` 那個 case**,一次略過它的走訪會找到
    每一個項目、卻一個按鍵都找不到——並在 `hasBuiltMainMenu` 被設起之後不再公布;
    那個旗標由 `buildMenu` 設定,而那裡是唯一能證明「存在一條選單列」的地方。
  - **closure 放在 `FallbackShortcutActions`,不是 `MenuShortcutActions`。** 兩者重建的時機不同:
    `buildMenu` 內的 `beginRebuild` 會默默作廢這條路所持有的每一個 token,而一個找不到東西的快捷鍵
    什麼也不做。
  - `actions/ios/P71-shortcuts.csv` 的檔頭原本寫著「只跑 iPad」,已更正。
- [x] **M5. `LazyListRowLifetimes` — 三個 backend 都已實作,而且三個都已驅動驗證(2026-09-16)**
  - **讀法是「建過幾個」對上「持有幾個」,而那讓一次小規模走訪就夠。** `rows built / held`:
    `held == built` 是「從未釋放」、`held < built` 是「釋放了 built − held 個」。那個差額不可能來自
    LRU:`List.swift` 給未 conform 的 backend 的上限是 200、給 conform 的是 4000。

    | 平台 | built / held | 被釋放 |
    | --- | --- | --- |
    | mac / AppKit | 38 / 19 | 19 |
    | iOS / UIKit | 500 / 6 | 494 |
    | Android | 190 / 3 | 187 |

  - **AppKit** 用 `didAdd`/`didRemove` 的 row view 生命週期;`didRemove` 自己的 `forRow:` 在
    「該列已不再有效」時是 -1,所以索引改在 `didAdd` 記下。只建過 38 列,是因為 NSTableView 在拖曳
    期間會合併版面、只算繪落點——把拖曳切細成 51 步得到**一模一樣的 38 / 19**,而那本身就是
    「這趟走訪要不要緊」的答案。
  - **UIKit** 用 `didEndDisplaying`,索引直接給,所以只需要「這一列是不是又在畫面上了」這一道防護。
  - **Android** 用 `AbsListView.RecyclerListener.onMovedToScrapHeap`(而不是 `getView` 的
    `convertView`——後者只在被丟棄的 view **回來**時才觸發);位置由 `CustomListAdapter` 的兩張表
    查出來,因為被丟棄的 `View` 身上沒有任何東西說明它先前是哪一列。
  - **量尺:`DebugFeatures.builtLazyListRows` / `liveLazyListRows`**,由 `List` 寫入、P57 顯示,
    並由一個只在 `--debug` 下啟動的計時器每秒重繪兩次——否則那個數字會停在啟動值,而
    「正確、活著、但沒動」與「壞掉」在截圖上完全一樣。
  - **先前那三筆「未驅動 / 只在小尺度觀察到」的紀錄已被取代,原因在我這邊**:`scroll` 欄位的單位是
    **滾輪格數**(一格 40 點,Android 再乘 density),而我填了像素大小的數字。見 mistakes 第 17 條。
- [x] **M6. 已修,而且它從來不是 AppKit 的缺陷 — 是測試合成器裡的兩個缺陷(2026-09-17)**
  - **滾輪 delta 的符號反了。** 格式裡 `dy` 為正代表向下,而 `NSEvent` 的 scrolling delta 講的是
    **手指**的方向——所以每一次「向下」都往上捲。
  - **那道退路無條件執行。** `NSScrollView` 是在**稍後一輪**才套用滾輪事件,因此同步檢查永遠讀到
    「沒有改變」,補償每次都開火,把 view 往下移了「事件剛剛往上移的同一個量」——兩者都以
    `lineScroll` 為單位、大小相同。**淨位移零**,而那與「一份忽略滾輪的清單」完全無法分辨。
  - **往上捲會畫空,是第三件事:** `contentView.scroll(to:)` 接受文件上方的點,而 AppKit 自己的
    處理會夾範圍、這條路徑沒有。量到 y=-192。
  - **修法:** 符號改正、退路先讓 runloop 跑 50 ms 再判斷、目標夾進可捲範圍,並讓 `postScroll`
    把命中的 view、scroll view、事件前後的原點與可捲範圍印到 stderr。
    **`before=(0,192) afterEvent=(0,0)` 那一行是整件事被打開的唯一原因。**
  - **成果:** P57 現在以滾輪走完五百列,讀數 `500 / 19`(481 列被釋放),擷圖停在第 481–490 列。
  - **順帶查到、與本項無關的兩個既有崩潰:** mac 上 P8 撞 `ForEach.commit` 的存取衝突、
    P4 撞 `AnyWidget used with incompatible widget type`。兩支在 mac 上都從未被動作檔驅動過。
  - 記為 mistakes 第 18 條。
- [x] **M7. P4 與 P8 在 macOS 上一啟動就崩潰 — 都已修(2026-09-17)**
  - **P4:** `AnyWidget used with incompatible widget type NSTextField; actual widget type is
    AppKitHitTestingContainer`。成因是 **`TextField` 在 `TextFieldStyle` 被開放之後就不再是
    elementary view**——它的 body 是 `AnyView(style.makeView(...))`,因此節點上的 widget 是容器,
    而 `.inspect` 的 `widget.into()` 轉成 `NSTextField` 會 trap。**P4 自己那個 closure 在 macOS 上
    是空的**(裡面全部包在 `#if canImport(WinUIBackend)`),所以崩潰來自一個根本沒事要做的 modifier。
    改為讓那些指名具體型別的 `inspect` 在子樹裡**搜尋**而不是直接轉型——這是嚴格推廣,本身就是該型別的
    widget 在第一行就會被回傳;找不到時仍然 trap,但會說出它要找什麼、以及那棵樹實際長什麼樣。
  - **P8:** `Simultaneous accesses ...`,而**兩次存取都被回報在 `ForEach.commit + 1388`**
    ——同一個函式、同一行,經由 `layoutableChild` 的 commit closure 進入了兩次。被持有的是
    `cache: &children.stackLayoutCache`:對 **class 屬性**取 `inout` 會在整個呼叫期間持有獨占存取,
    而那個呼叫會 commit 每一個子節點。改用 `withStackLayoutCache`(複製出來、傳副本、再寫回),
    四個位置全數套用(computeLayout 兩處、commit 兩處)。
  - **回歸:** P0 P2 P13 P16 P22 P23 P34 P57 全部啟動並存活;P34 與 P23 的動作檔重放結果不變;
    `Scripts/test.sh` rc=0。
- [x] **M8. `.inspect` 的同一個缺陷 — UIKit 已修並驗證;WinUI 與 GTK 於 2026-09-17 由 Windows 修好並驗證** — 三個 backend 的
  `InspectionModifiers.swift` 是同一個形狀:對指名具體型別的 overload 直接 `widget.into()`。
  由於 `TextField`(以及任何走 style 的控制項)的 widget 現在是容器,那些 overload 在該控制項上都會
  trap。AppKit 已改為搜尋子樹;**UIKit 可在本機驗證、WinUI 需要 Windows**。
  - **UIKit 已修(2026-09-17)。** 先驗證它真的會炸:P4 在模擬器上死於
    `AnyWidget used with incompatible widget type WrapperWidget<UITextField>; actual widget type is
    BaseViewWidget`。改為搜尋子樹之後,P4 在 iOS 上正常算繪。
  - **WinUI 仍待修。** `Sources/WinUIBackend/InspectionModifiers.swift` 是同一個形狀
    (指名具體型別的 overload 直接 `widget.into()`)。**這裡建不了 WinUI,因此沒有量測就不改**
    ——一個未經驗證的機械式修改,對一棵別人正在上面工作的樹,風險大於它解決的問題。
  - **WinUI 已修並驗證(2026-09-17,Windows)。** 先量它真的會炸:P4-WinUI 啟動即死於
    `AnyWidget used with incompatible widget type TextBox; actual widget type is Canvas`(exit 132)。
    改為搜尋子樹(先走 Panel/Border/ContentControl 的邏輯子節點,再走 VisualTreeHelper——`.onCreate`
    在掛上視窗之前執行,那時 visual tree 可能還是空的)之後,P4 正常執行,而且**closure 真的作用在
    TextBox 上**:它設的外框色 RGB(20, 70, 120) 在擷圖的上、下、左三邊量得一模一樣。
  - **GTK 也有,而上面沒有列到它。** P4-gtk4 啟動即死於
    `AnyWidget used with incompatible widget type Entry; actual widget type is PassthroughFixed`
    (exit 132)——closure 內容在 GTK 上是**空的**,與 UIKit 那次同一個形狀。改為走 Gtk 模組在 Swift
    端保存的子節點(`Fixed.children`、`Box.children`、ScrolledWindow/Viewport 的 child、Paned 兩側)
    之後正常執行;找不到會 `fatalError` 並印出樹,所以「沒當掉」本身就證明找到了 `Entry`。
  - **未驗**:`List` 與 `NavigationSplitView` 的 `.inspect`(兩個 Windows backend)仍是直接轉型,沒有
    任何 app 呼叫它們,所以沒有量測就沒改;`Examples/AdvancedCustomizationExample` 用得最多,是下一個
    該跑的地方。WSL 的 GTK 與 Windows -gtk4 共用同一份 GtkBackend 原始碼,未另外在 WSL 上跑。

  - **今天量到、值得下次照做的一件事(相關性,不是成因)**:**三次**成功的驅動,都是在
    **使用者剛與遠端桌面互動之後**的第一次嘗試(19:10 WinUI 排序、19:30 GTK 排序、19:36 指示符);
    而夾在中間那八次在完全沒有互動的情況下連續被拒。下次要驗證需要滑鼠的東西時,請對方動一下、
    然後**立刻**跑——這比重試迴圈有效得多:那個迴圈連跑八次都沒中,而互動後的第一次就中。
    *Both successful sort replays today began right after the user interacted with the remote
    session; eight consecutive attempts with no interaction were all refused. Correlation, not a
    proven cause -- but it is the cheapest thing to try first.*
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
- [x] **#123 三份實作完成,三個平台都以真實探針驗過** — 新增 `BackendFeatures.Accessibility`(四個單向 setter,conformance 檢查 + `warnOnce`)與 `.accessibilityLabel/Hint/Value/Hidden(_:)` 四個 modifier,AppKit / UIKit / Android 全部實作。**測試 app 是新的 P69**(與 P67 分開:P67 問「名字如何被推導」,P69 問「作者覆寫之後會怎樣」;放在一起時前者的正確推導會遮蔽後者的失敗)。三個讀數:macOS `ax_dump` 給 `desc='Close'`(按鈕上寫的是 X)、`help='Removes the file permanently'`、`value='40 percent'`、`decorative` 不存在;Android `uiautomator dump --compressed` 給同樣三項,且四個 TextView 全部不存在;iOS 由 app 自報 `'Close'/h''/v'' | 'Delete'/h'Removes...'/v'' | 'Volume'/h''/v'40 percent' | HIDDEN`。**四次靜默的失敗寫在原始碼裡**:(1) 在 `commit` 設標籤——`updateButton` 在下一幀的 `computeLayout` 重寫它;(2) 用 `isAccessibilityElement()` 找內層控制項——AppKit 上每個 `NSView` 預設都是 false;(3) 用「唯一的 `NSControl` 後代」——有兩個;(4) Android 用 `View.setTooltipText` 當 hint——節點的 `hint` 屬性仍是空的,要 `AccessibilityDelegate`。**順帶修掉一個既有缺陷**:AppKit 與 Android 的按鈕都被螢幕閱讀器唸兩次(`setAccessibilityElement(false)` 不會把 `NSTextField` 移出 AX 樹;`setAccessibilityChildren([button])` 才會)。**GTK/WinUI 尚未轉換。**
- [x] **#122 focus 三份實作完成,macOS 與 Android 以真實輸入驗過** — `BackendFeatures.FocusableViews`(四方法,`focus` 回傳 `Bool`)、`@FocusState`、`.focused(_:)` 與 `.focused(_:equals:)`,AppKit / UIKit / Android 全部實作。**測試 app 是新的 P70。** 讀數:macOS 以真實 `CGEvent` 點擊驅動,`changes` 1→2→3(其中 1 是 AppKit 自己給的初始 first responder),畫面上的 `focused field` 與焦點環一致;Android 以 `adb input tap` 驅動,`focused field: email`、`changes 2`,移開後 3;iOS 無輸入合成器(`actions/ios/` 是空的),因此那三步是 app 自己驅動的,並在 app 註解裡寫明「使用者造成的那一半在 iOS 上未涵蓋」。三個平台的拒絕檢查都是 `refused (correct)`。**P70 抓出兩個真的缺陷,都已修**:(1) 每一幀重建 focus observer 會**靜默吞掉**改變——它從 `computeLayout` 執行,新 observer 把 `lastValue` 取自當下狀態,於是拿改變跟自己比;畫面曾顯示 `focused field: name` 而焦點環明明不見了。(2) AppKit 上一顆 `.disabled(true)` 的按鈕**拿得到鍵盤**:`.disabled` 設的是 `NSCustomButton.isEnabled`,而 responder 搜尋直接越過那層 `NSView` 包裝、走到內層仍然啟用的 `NSButton`。**給 GTK/WinUI 的提醒**:Android 的 `View.setOnFocusChangeListener` 一開始什麼都沒回報——widget 是容器,而那個 listener 只為「被設定的那個 view」觸發;要用 `ViewTreeObserver.OnGlobalFocusChangeListener`,那是「觀察 AppKit 視窗 first responder」的對應物。**GTK/WinUI 尚未轉換。** — 等 Windows 同意形狀。~~**GTK 的 `grabFocus` 必須先產生**:它只存在於 GIR 中,產生出來的 Swift 沒有它~~ **形狀已同意(見上一條);`grabFocus` 不需要產生,手寫綁定直接呼叫 C 函式即可**
  - **上兩條末尾的「GTK/WinUI 尚未轉換」已經過期(2026-09-16 查證)。** 四份都在:
    `Sources/GtkBackend/GtkBackend+Accessibility.swift:6`、`GtkBackend+Focus.swift:6`、
    `Sources/WinUIBackend/WinUIBackend+Accessibility.swift:4`、`WinUIBackend+Focus.swift:4`,
    各自宣告 `BackendFeatures.Accessibility` 與 `BackendFeatures.FocusableViews`,
    commit 為 `ab2d1d51`(WinUI focus)、`38394d14`(GTK focus)、`4c7bbf12`(#122 驅動驗收)。
    原句留著不刪,因為它示範的正是「狀態宣告只在寫下的那一天為真」——**寫下它的那一側做完之後,
    沒有任何東西會回頭打開這份檔案把它改掉**。
- [x] **M3a. #79 GTK 39px — 已修好,且 2026-09-16 以 P61 驅動驗過 `shortfall 0x0`** — 已定案為 (c),由 **Windows** 執行:繼續挖「present 之前就能回報 frame 的 GTK 呼叫」,不接受把 39px 寫成行為;走不通要帶著「試過哪些呼叫、各自回傳什麼」回報
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
  - **2026-09-16:真的修好了,而且 39 是量出來的、不是寫死的。** `Sources/Gtk/Widgets/Window.swift`
    的 `probeGtkOwnDecorationHeight()` 會建一個視窗、**不**裝 titlebar、realize 之後在子元件中
    尋找 `GtkHeaderBar` 並量它的最小高度,得到 39;裝了 `GtkHeaderBar` 的則量到 47,差的 8 就是
    先前那個偏移。**那個數字現在有產生它的程式碼可對照**,這正是上面那條「已決定 vs 已修好」
    所要求的。
    *2026-09-16: fixed, and the 39 is measured rather than written down --
    `probeGtkOwnDecorationHeight()` builds a window with no titlebar, realizes it, finds the
    `GtkHeaderBar` among its children and measures it. The number now has code that produces it.*
  - **2026-09-16:已驅動驗收,`shortfall 0x0`。** 這一條先前兩次改狀態都只動到「決定」與「實作」,
    沒有動到「量過」——所以這次是同一個量測、不同的答案,而不是換了一個量測。P61 於 Win-gtk4、
    帶 `SCUI_DEBUG`,三個探測點一致:`content size: requested 620x420 allocated 620x420
    shortfall 0x0`,`+250ms` 與 `+1500ms` 同樣是 `0x0`;2026-09-10 同一支 app、同一個 backend
    讀到的是 `shortfall 0x39`。三個點而非一個,是因為**時序造成的假象會印出兩個不同的數字,
    真正的 no-op 會把同一個數字印兩次**。
  - **這次量測先被「單一實例」擋下來,值得記一筆。** P42 開著時啟動 P61,它以 0 結束、log 完全
    是空的——SwiftPM 的可執行檔沒有 metadata,於是每一支測試 app 共用
    `com.example.SwiftCrossUIApp`,而 GApplication 對同一識別碼只認一個實例。**空 log 讀起來
    與「啟動了但什麼都沒畫」一模一樣。** 已在 `GtkBackend.init` 加上 `SCUI_GTK_APP_ID` 覆蓋,
    本次量測就是在 P42 仍然跑著的情況下取得的。
- [x] **6. P25 多檔** — 已回答並處理。**拖放本來就支援多檔**:`DropPayload.urls` 解析整份 `text/uri-list`,而 P25 已經顯示 `count`,所以 drop 不需要任何開關。真正單檔的是**開啟對話框**,已加上兄弟 action `chooseFiles`(回傳 `[URL]?`);`OpenDialogOptions.allowMultipleSelections` 與 `[URL]` 回傳一直都在,缺的只有公開介面
- [x] **7. P33 / P34 盤點** — 已完成。十六個名字以宣告形狀 grep 加對照組查證,**只有 `LazyHGrid` 缺席**(即 #118);兩支 app 自己的文字都是準確的
- [x] **7b. P34:兩位數的列在右側被切掉 — 已修** — 成因不在 stack,而在**量測與繪製走不同路徑**:AppKit 以 `NSString.boundingRect` 量,卻以 `NSTextField` 畫,而前者對每一個試過的字串都少報約 4 pt(系統字型 12,「Row 99: eager VStack child」量得 155.3、實需 159.3)。容器依較小者訂寬,於是最寬的子元件被切在字形中間。改為向**負責繪製的那個 widget** 要數字(`cell.cellSize(forBounds:)`),換行與高度已驗證一致且冪等。修前列 10 起全部硬停在 x=319,修後行末隨字寬落在 312–320
- [x] **9. `DocumentGroup`** — 已完成並驅動 (P62)。`FileDocument`、每份文件一個視窗、`newDocument`/`openDocument` action、`ContentType.plainText`。**未做的部分在 scene 自己的文件裡寫明**:自動儲存、版本、未儲存提示、重開上次工作階段
- [x] **10. #28 動畫 / #32 手勢** — 見第 7 項;此處為重複條目,一併關閉。
- [x] **12. #113 n^1.5 版面成本 — 已跑,結論是「不是 n^1.5,它是線性的」** — P52 四條 arm、12→192 五個尺寸,每格成本是**平的**(primitive 220µs / custom 166µs / text 63µs),指數 n^0.95–0.96。三條 arm 曲線相同 → **成長在 stack 版面**;但常數不是附帶的:`Button` 每格比同形狀 `Text` 多 157µs(3.5 倍)。48 格時一次按壓 min 10.5ms / med 20.7ms,**沒有重現 0.3 秒那個參考點**——若那是 GTK/WinUI 量的,那本身就是要問 Windows 的一件事。細節見 `testapp/plan/plan-113-layout-cost.md`
- [x] **13. #120 Grid — 已完成:共用欄 + `gridCellColumns`** — 成因不是「需要新的 backend 能力」,而是**父層看不見它的孫節點**:`ViewLayoutResult` 只在 initialiser 中接收 `childResults`、只保留合併後的 preferences。因此改由儲存格經 preference 自行上報(`gridRowCells` 串接、`gridCellColumns` 比照 `layoutPriority` 逐層繼承),`Grid` 在**同一次更新**裡跑兩輪(先量、再依欄放),`GridRow` 從「body 是 HStack 的組合 view」變成真正的容器。量到:C2 在三列都是 106..155、C3 都是 166..215(修改前每列各自為政),跨欄那列畫在 16..215。五個單元測試,其中補寬那條已證明「關掉就會紅」
- [x] **14. #127 `GeometryProxy.frame(in:)` — 已完成(GTK/WinUI 待對方編一次)** — Windows 答覆後路線確定:新增 `BackendFeatures.WidgetGeometry.originInWindow(ofWidget:)`。**排序問題的解法是「在 commit 取得原點」**——版面計算當下 widget 還沒被放置,commit 之後才有答案,若與內容當初據以建立的不同就要求再排一輪,第二輪即正確、第三輪不會發生。P63 對著像素驗過:標記方塊量到 x=92、內容座標 y=287,與 global 回報完全相同;盒子角落量到 (68,256),與 `global − named` 完全相同。AppKit 與 UIKit 已編譯;Android/GTK/WinUI 已寫、各自標明未編譯與要查什麼
- [x] **15. #28 Animation — 完成(時鐘 + 引擎)** — 引擎接在**狀態**那一端而不是版面那一端:`StateImpl` 的 setter 一處切入,不必動 30 個 `setPosition` 呼叫點(其中 8 個在 Windows 的 `Views/Modifiers/Layout/`)。`withAnimation`、`Animation` 四種曲線、`AnimatableValue`(Double/Float/Int/SIMD2;**`Bool` 刻意不 conform**,`Color` 因為要先對環境 resolve 而暫緩)、單一 driver 掛在 #28 的 frame clock 上(第一個動畫啟動時鐘、最後一個結束時停掉)。**P66 量到**:0.5 秒線性從 0 到 200 產生 31 個相異值、單調、每幀約 6.7、終點正好 200.0;同一個 `withAnimation` 裡的 `Bool` 只被賦值一次。六個單元測試。**已知界線寫在 `Animation` 的文件裡**:動的是狀態而非 view 樹,因此 `.transition`、matched geometry、以及「沒有單一值描述得了的版面重排」都不在內
- [x] **16. #118 LazyHGrid — 已完成** — 先把 `GridLayoutPlan` 的詞彙從 column/row 改成 lane/line 並帶上 `axis`,270 行的解析器整段移到 `GridLayoutPlan` 共用(不複製);`GridItem` 增加 `verticalAlignment`。P48 第 5、6 節驅動,量到 lane 間距 42 = 34+8、對齊階梯 52/52(而非 48/48)
- [x] **17. #128 `EdgeInsets` — 已完成,這條協調請求已無須回覆(2026-09-17 查證)** — 原本是 Windows 端的一個**協調請求**(想動 `Views/Modifiers/Layout/`,在等 Mac 端確認),而它在等待期間就被做完了。
  **以下為原始請求的文字,保留作為背景;其中「四個欄位都是 `Int`」已不再成立。**
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
  - **本條的前提已經過期(2026-09-16 查證):`EdgeInsets` 已經是 `Double`。**
    `Sources/SwiftCrossUI/Views/Modifiers/Layout/PaddingModifier.swift:46-54` 的 `top`/`bottom`/
    `leading`/`trailing` 四個欄位都是 `Double`,`todo.md` 2026-09-12 的交接段也寫明「不要重做 Int → Double」。
    上面引用的 `PaddingModifier.swift:34-42` 是改動之前的行號。**仍然開著的只剩驗證**:`.padding(8.5)`
    在兩個 Windows backend 上從未被量過畫面——P36 有這個案例,但 `results.csv2` 只有 WSL(失敗、無擷圖)
    與 iOS 的紀錄。協調請求 (a)(b) 因此不再需要回覆。
  - **`cfe30184 "EdgeInsets is Double, so a padding can be a fraction of a point"`**,而
    `PaddingModifier.swift` 的四個欄位現在是 `Double`。小數 padding 可以表達了,而 Windows 今天的
    #128 量測(`P36`,以顏色量而非讀截圖)正是它的驗收。
  - 原本問 Mac 端的兩個問題,答案記在這裡以免它再被問一次:**(a) 沒有,我從未動過
    `Views/Modifiers/Layout/`**——`git log -- Sources/SwiftCrossUI/Views/Modifiers/Layout/`
    裡沒有我的 commit;**(b) 我沒有要接 #118。** 那個目錄是你們的。
- [x] **M9. magnify / rotate — 完成(2026-09-17):格式、iOS、Android 都已驅動;AppKit 與 X11 以寫明的理由拒絕**
  - **現況:** 五個 backend 都 conform `MagnifyGestures` / `RotateGestures`,Windows 已用
    `testapp/touch_gesture.zsh` 在兩個 backend 上驅動過——而那支工具的檔頭第一行就寫著
    **「Windows only」**。動作檔格式**沒有** pinch/rotate 動詞(`ActionFile.swift` 裡查無),
    iOS 的 XCUITest runner 也沒有。所以 mac/iOS 這一半不是「沒人做」,是**沒有路可以走**。
  - **打算加的形狀(先公開,再動手):** 兩個新動詞,沿用 `scroll` 既有的「重新詮釋 x/y」慣例
    ——那個欄位在 `scroll` 上已經是滾輪格數而非位置,而格式沒有多餘的欄位可用。

    | 動詞 | x | y |
    | --- | --- | --- |
    | `pinch` | 縮放比例 × 100(`200` = 放大兩倍) | 速度 × 100(0 = 由實作挑預設) |
    | `rotate` | 角度(度,正為順時針) | 角速度(度/秒,0 = 預設) |

  - **各平台打算怎麼回應:** iOS 用 `XCUIElement.pinch(withScale:velocity:)` 與
    `rotate(_:withVelocity:)`;Android 以雙指 `MotionEvent` 合成;**macOS 明確拒絕**
    ——`NSEvent` 沒有公開的 magnify/rotate 建構子,而 `CGEventType` 的 gesture 型別不是公開 API;
    這會是一個**寫明理由的 `unsupported`**,不是沉默。Windows 兩個 backend 已有外部工具,不改。
  - **若你們也正要動 `Sources/InputEvent/` 的格式,請說一聲** ——這是 mistakes 第 12 條那個形狀,
    而這次我先公開形狀再寫。
  - **2026-09-17 進度:格式與 iOS 已完成並驅動過,Android 還沒建。**
    - `InputAction.pinch/rotate` 與 `ActionFile.swift` 的解析已落地,形狀與上表相同。
    - **iOS 實測通過**:`actions/ios/P65-pinch-and-rotate.csv`,連續三次執行
      (`p65-ios-final-20260917-113959.png`、`-114256.png`、`-115535.png`),三次都讀到
      `magnify ENDED: 1.625`,`rotate ENDED` 則是 0.995、0.995、1.233 rad;三次
      `drag events: 0`,代表沒有任何一個手勢變成了拖曳。
    - **兩者都離開了起始值(1.00 與 0)——那是 P65 所問的;而兩者都不等於那一列所要求的**
      (比例 2.0、45 度 = 0.785 rad),旋轉甚至不可重現。那是關於**驅動器**的事實,不是關於
      UIKitBackend 的:XCUITest 送出的是它自己尺寸的手勢。**此處尚未量測任何 backend 的保真度**,
      而把 1.625 當成「縮放正確」會是一次以驅動器的行為去斷言 backend 的紀錄。
    - **那三次失敗全部不是 backend 的問題,而且每一次看起來都像。** 手勢作用在**元素**上,
      而動作檔不帶元素身分:(1) 送到視窗中心 → 落在旋轉格上,縮放沒有辨識器可收;
      (2) 改用 `scroll` 把目標捲到中心 → P65 沒有可捲的東西,那兩列變成拖曳,被拖曳格收走;
      (3) 改用 `move` 瞄準 + 命中測試 → **app 收到第一個真正的事件之前,accessibility 的框
      回報在一個不是螢幕的座標空間**(440 點寬的視窗裡出現 x = -36、寬 500 的框),於是命中到
      一條 22 點高的細條、再一次命中到 scroll view。**等待清不掉它**(實測:四秒內查詢八次,
      毫無變化);一次送達的輕點可以。三次的擷圖都會寫著 `magnify: (none yet)`。
    - runner 這一側因此有三樣東西:以 `move` 的指標瞄準、丟棄落在視窗外的候選、以及在只命中到
      容器時於 log 裡直接說出「在第一列手勢之前放一次 `click`」。
    - **Android 也完成了,而且是實機(emulator-5554)驅動過的。**
      `actions/android/P65-pinch-and-rotate.csv`,擷圖 `p65-android-final-20260917-143345.png`:
      `magnify ENDED: 2.000`(那一列要求 200)、`rotate ENDED: 0.785 rad`(那一列要求 45 度)、
      `drag events: 0`。**精確**——與 iOS 不同,那裡 XCUITest 送出的是它自己尺寸的手勢。
    - **而這次驅動抓到一個真正的 backend 缺陷。** 修好之前,同一份檔案兩次都回報
      `magnify ENDED: 1.194` 與 `rotate ENDED: 0.633 rad`——數值相同,不是雜訊。原因是
      **一個會捲動的祖先在「一個 touch slop 的位移」處奪走了手勢**(420 dpi 下 8dp = 21 px),
      而 `ContinuousGestureContainer` 把隨之而來的 `ACTION_CANCEL` 當成結束回報,其後每一個 move
      都靜靜落在 `tracking` 守衛之外。1.194 是 62 步中的第 12 步(第一個接觸點移動 20.3 px,
      第 13 步會是 22.0);0.633 rad 是 31 步中的第 25 步(同一點水平移動 20.4 px)。
      兩個手勢、兩個比例、同一個門檻。修法是 `ACTION_DOWN` 時
      `requestDisallowInterceptTouchEvent(true)`——一根手指在任何可捲動區域裡的遭遇與合成器完全相同,
      所以這是使用者也會碰到的缺陷,不只是測試工具的問題。
    - **另一件量到的事:`--no-showtime` 會拍到重放進行到一半。** final 擷圖緊接在 5 秒那張之後拍,
      而這些手勢要跑好幾秒——第一次 Android 執行讀到的部分值並不是錯的,只是早了。
    - **macOS 與 X11 維持寫明理由的拒絕**,理由在 `AppKitSynthesiser.swift` 內。

### 為什麼缺陷排在功能之前 / Why the defects moved above the features

- [x] **T3. AndroidBackend 已遷到 Swift 6 language mode(2026-09-16)** — 五個並行性問題修好並保留:stdio 緩衝移進 C shim(`stdout`/`stderr` 是可變 C 全域,Swift 6 拒絕引用);兩個 `@Entry` 改為手寫 key(macro 產生的是「非 `Sendable` 型別的 `static let`」,而教 macro 加 `nonisolated(unsafe)` 會讓整個套件的同一個診斷消音);一個泛型輔助函式移除了**永遠到不了**的 `default:` 參數;`SharedPreferences` 依 Android 自身的 thread-safety 保證加標註;`ActivityListener` 與兩個 AndroidKit 型別改 `@unchecked Sendable`,因為 **swift-java 的 `@JavaMethod` 展開會把 `self` 與每一個參數送過隔離邊界**。第六個不是模式問題:`CommandLine.arguments` 的 setter 在 Swift 6.0 **被廢除**,而少了它 Android 上 `--debug`/`-rows`/`-actionfile` 全部送不到(runtime 的 argv 是 JVM 的)。先試的「v5 單檔 target」在 `swift build` 下可用、在 swift-bundler 的 `swift build --product` 下**消失**(`no such module`,兩份 manifest 快取都清過,也列進 product 了,原因未明,已放棄)。落地的做法不需要任何 target:那個廢除是**編譯期**閘門,符號仍由 runtime 匯出(以 `nm -D libswiftCore.so` 在實際使用的 Android SDK 上查過),改以 `@_silgen_name` 抵達,`__owned` 明寫。**上機驗過**:四個旗標原樣抵達、零崩潰、程序存活,`focus changes heard: 3`、`refused (correct)`。**順帶抓到一個回歸並記為 mistakes 第 9 條**:把 `AndroidBackend` 加進 `migratedToSwift6` 會讓**非 Android** 的每一次建置以 manifest 自己的打字守衛死掉——而我是在 Android 上驗了五次的,那正是該缺陷不可能出現的平台。
- [x] **4. #121 鍵盤快捷鍵 — 五個 backend 全數完成(2026-09-16 傍晚由原始碼查得)** — UIKit 那一格已由 Mac 補上(`UIKitBackend+Menu.swift` 讀 `environment.keyboardShortcut`,`cfc442aa` 實作、`8ccfc78a` 驅動通過)。下方那句「只剩 UIKit」是當天稍早為真。原文保留:2026-09-16 由**原始碼**查得(不是讀這份 queue):GTK、WinUI、AppKit、Android 都已讀 `environment.keyboardShortcut`,**UIKit 沒有**。那一行「`ResolvedMenu.Item` 沒有 shortcut 欄位」已經不成立——最後採用的是 environment,不是欄位。
- [x] **5. focus / accessibility(#122 / #123)— 五個 backend 全數完成** — GTK 與 WinUI 於 2026-09-16 補上(`4c7bbf12` / `9746bbeb`),P70 與 P69 都以動作檔驅動過。**限制寫明**:GTK 沒有 accessibility 的讀回路徑(`gtkaccessible.h` 只有 update、沒有 getter,要讀得走 AT-SPI),WinUI 的讀回是行程內的、對 Narrator 實際唸出什麼沒有發言權。原文保留:AppKit / UIKit / Android 已落地並驗過,GTK 與 WinUI 未——形狀議定後三份實作已完成,P69 與 P70 分別以 `ax_dump`、`uiautomator --compressed` 與真實點擊/觸控驗過。交接在 `queue-windows.md`。
- [x] **6. #74 `-GPU` on macOS — 已實作(AppKit + UIKit)** — 那個「設計問題」其實已被協定的形狀回答了:`GraphicsAdapter` 的三個欄位 `name`/`isRemovable`/`isLowPower` **就是 `MTLDevice` 的三個屬性**,而 `AdapterOutcome.requiresRestart` 的文件早就寫著「macOS 不需要這個,Metal 在執行期選擇」。AppKit 用 `MTLCopyAllDevices()`(系統預設排最前,因為 `.systemDefault` 取 `first`)、UIKit 用 `MTLCreateSystemDefaultDevice()`(`MTLCopyAllDevices` 僅限 macOS,而 iOS 只有一張且不可移除)。**明說它不做什麼**:它不會把視窗移到另一張 GPU——window server 依「視窗所在顯示器」決定合成用的 GPU,macOS 上沒有應用程式做得到。P68 驅動並列出介面卡。**Android 已補上**:回報一張以 SoC 命名的介面卡(`SOC_MANUFACTURER`/`SOC_MODEL`，早於 API 31 的裝置退回 `HARDWARE`),而**不是**空清單——空清單會讓框架解析為「沒有可用的繪圖介面卡」，那句話對每一台 Android 裝置都是假的。名字是 SoC 而非 GPU:真名要 `glGetString(GL_RENDERER)`，那需要對 `EGL_DEFAULT_DISPLAY` 做 `eglInitialize`/`eglTerminate`——也就是 app 正在算繪的那個 display，而這台機器驗不了它會不會弄壞算繪
- [x] **7. #28 動畫 / #32 手勢** — 五個 backend 全部 conform(`DragGestures`/`MagnifyGestures`/`RotateGestures`、`FrameClocks`)。**未驅動的只剩 magnify/rotate**:此處合成不出觸控板的雙指手勢,需要有人在機器前做一次。
- [x] **9. #79 GTK 39px / #109 popover anchor API — 兩項都已定案並落地(2026-09-16),此條為重複指標,一併關閉** — 原文是「需要你決定」;#79 見 M3a(已驅動驗收 `shortfall 0x0`),#109 見 M3b(兩個 Windows backend 已成對驗收)。
- [x] **10. #80 P42 縮放通知 — WinUI 通過;GTK 值與執行期變更皆已完成並驅動驗收(2026-09-16,`cd90458e`)** — 需要人在機器前改顯示縮放。
  - **WinUI:通過。** 使用者把顯示縮放由 100% 改為 125%、**全程未碰視窗**,而該視窗自己記到
    `1.0 (change 1)` → `1.25 (change 2)`;畫面顯示 `changes observed: 1`、歷程 `1.0 x5 -> 1.25 x2`。
    **判決在歷程、不在當前值**:單看 `1.25` 對「通知有沒有觸發」毫無發言權,因為在改完之後才啟動的
    app 也會顯示 1.25。
  - **GTK:`changes observed: 0`,而那看起來像缺陷、其實不是。** 對照組定了案:**殺掉、在 125%
    之下全新啟動,它仍然回報 1.0**。因此 GDK 的 win32 backend **根本不用 surface scale factor
    表達顯示縮放**——兩種設定下都是 1,縮放走的是字型 DPI。**去接 `notify::scale-factor` 不會有
    任何改變,因為那個值從來不動。**
  - **沒有那個對照,兩種解釋在畫面上完全相同**(都是 `current: 1.0`、`changes observed: 0`),
    而選錯的那一個會導致「為一個不存在的變化實作通知」,然後看著它什麼都不做。
  - **待答(交給下一個接手的人)**:GTK 在 Windows 上改用什麼表達?`gdk_surface_get_scale`
    (GTK 4.12+ 的小數倍率)還是只有字型 DPI?而 `windowScaleFactor` 在此處是不是對的通道?
  - **不要因為 WinUI 通過就把 GTK 標成缺陷**,也不要反過來把 GTK 的沉默當成「這個功能不需要」。
  - **上面那段「不是缺陷,是平台事實」是錯的,原文保留於此以資對照(2026-09-16 當日推翻)。**
    你的一句「我覺得 GTK 在 Windows 上跟著 scale factor 走是合理的」把它推翻了。**對的部分**:
    新探針帶著它當時沒有的小數 API 再問一次,125% 下 `gtk_widget_get_scale_factor=1`、
    `gdk_surface_get_scale=1.0`(GTK 4.12 起的 double,此處 GTK 4.22,所以它存在而且答 1.0)、
    `gdk_surface_get_scale_factor=1` —— **沒有任何 GDK 呼叫講得出顯示器的縮放**,這一半成立。
    **錯的部分是把它當成結論。** 同一個視窗、同一個瞬間,Win32 `GetDpiForWindow` 答 **1.25**,
    經由 `gdk_win32_surface_get_handle` 取得 —— 值一直都在,只是 GDK 不攜帶它。
  - **已實作:`scui_window_display_scale()`**(`Sources/GtkCHelpers/gtk_window_scale.c`),由
    `computeWindowEnvironment` **僅**用於 `windowScaleFactor`。**`ActionFileReplay(layoutScale:)`
    一個字都沒動**,因為 `testapp/actions/win/` 每一份的座標都是對著那個整數量出來的。
    修好之後在 125% 下實測:`scale factor -> 1.0 (change 1)` → `-> 1.25 (change 2)`,與 WinUI
    同一種形狀。
  - **執行期變更那一半:壞的不是通知,是來源。** 修好之後把顯示器從 125% 改成 100%,探針**直接**
    呼叫 `GetDpiForWindow`(不經任何訊號),連續 **99 次讀數全部回報 1.25**——不是慢一拍,是從未
    移動。因此那支 `WM_DPICHANGED` subclass(同檔中已寫好)是**寫得對、但結構上到不了**的程式碼。
  - **原因是行程的 DPI awareness,而 GTK 有開關。**
    `GetAwarenessFromDpiAwarenessContext` 回報 **1 = SYSTEM_AWARE**;Windows 依設計只告訴這種行程
    「啟動當下的系統 DPI」,而且**不送 `WM_DPICHANGED`**。而 `gtk-4-1.dll` 的字串裡就有
    `GDK_WIN32_PER_MONITOR_HIDPI`、`GDK_WIN32_DISABLE_HIDPI`、`_gdk_win32_enable_hidpi`、
    `WM_DPICHANGED`;帶 `GDK_WIN32_PER_MONITOR_HIDPI=1` 重跑,同一支探針讀到 **awareness=2 =
    PER_MONITOR_AWARE**。所以平台表達得出來、GTK 也要求得動。
  - **下一步(需要有人在機器前)**:在 per-monitor 模式下跑著,改一次縮放,看值會不會跟著走。
    **在量到它對視窗尺寸的影響之前,不要預設打開**——`testapp/actions/win/` 的每一個座標都是
    對著現行幾何量出來的。
- [x] `SceneStorage`(P59)、`Settings` scene(P60)—— 即 Windows 表的 #35 前兩項
- [x] #117 phase 2 / 4a / 5:五個 backend 的 list viewport
- [x] Review 4:兩個 ScrollViewReader,AppKit 與 Android 雙向驅動(P58)
- [x] heartbeats/:兩台機器以 session id 送達並實測
