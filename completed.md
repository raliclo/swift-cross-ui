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
  P45-press-the-model-button.actions constructed the model 8 times -- at launch, on each
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
  SoftPCB Mac host, measured THERE on AppKitBackend at 1113a310. This is the "empty ForEach" crash of 2026-09-08,
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
  the SoftPCB Mac host: SOFTPCB_ROOT holding only analysis/workflows.csv2, CLAUDE.md and
  an executable scripts/solver_preflight.zsh containing `exit 0`.
  **核心崩潰,ViewGraphNode.swift:13(`_widget!`):view graph 還在建構時就有一次發布抵達。**
  2026-09-27 由 SoftPCB 的 Mac 主機回報,在**那邊**以 AppKitBackend、1113a310 量到;**這棵樹裡尚未重現。**
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
  - 因此**那兩個原本待回答的問題,量測自己答了**:位移發生在**面板內**,而按下時面板**不會**關閉。
  - **量法本身出過兩次錯,都記在此處,因為兩次都會產生一個看起來合理的結論:**
    (1) 以牆鐘時間抓擷圖,兩張都落在按下**之後**,差異為零——那讀起來像「完全沒有位移」,而其實是
    「兩張一樣的圖」;(2) 第二次改了時間,before 那張落在面板**出現之前**,差異變成整個面板 325 x 203,
    那讀起來像「整個面板都動了」。正確做法是**以 app 自己的 log 行為準**去等
    (`popover alpha shown` → 拍 before;`popover counter 10` → 拍 after)。
  - **順帶修掉兩份過時的動作檔**:`P50-open-first-panel.actions` 與 `P50-panel-press-me.actions` 裡那顆
    「Open the first panel」按鈕座標由 (227,646) 改為 (231,677)。舊座標打在一個 `NSCustomTextField` 上,
    而**重放仍然以 0 結束**——唯一的跡象是事後那行 geometry 寫著 `popover=none`。兩份都已重放驗過。
- [x] **2b. P50:一次 light dismiss 觸發兩次 `onDismiss`** — 已修。`NSPopover` 會把「實作通知形狀方法的 delegate」自動註冊為該通知的觀察者,於是同一個方法被送達兩次
- [x] **2c. 動作檔已能驅動 AppKit 的 popover** — 兩件事要一起改:(1)`targetWindow()` 不再回傳 popover——popover 會取得 key,於是每一個**非** popover 的座標都在對它解析,而檔案照樣重放成功、每次點擊都落在某個看似合理的位置;(2)`origin=popover` 的事件投遞到 **popover 自己的視窗**,投給後方的視窗會把它 light-dismiss,而「被關掉的 popover」與「沒打中的點擊」是同一張圖。`popoverOrigin` 取的是**內容區**而非視窗框(框比畫出來的面板大 26 點,含箭頭與陰影)。實測:`P50-panel-press-me.actions` 讓 P50 記下 `popover counter 1`
- [x] **3. P32:Toggle 沒有可見的開啟狀態** — 已修。`onStateBezelColor` 來自 `environment.toggleColor`,app 沒設就是 nil,於是「開」什麼都不畫;改為退回 `.controlAccentColor`
- [x] **4. P44:vertical stack 空間耗盡** — 已修:那是誤報。`offered 643 / took 643` 相等,什麼都沒不夠;是 `Spacer` 在沒有餘裕時正確地拿到 0。回報條件補上「確實溢出」,與它自己的訊息一致
- [x] **5. P28:點擊延遲 — 兩條未量的路徑都量完了** — 「真實滑鼠事件合成不出來」不成立:`AppKitSynthesiser` 檔頭那個「CGEvent 送出 0 個事件」量於 `AXIsProcessTrusted() == false`,而那台 Mac 當時是 `true`,`CGEvent.post(.cghidEventTap)` 會送達。實測 click→body:**啟動後第一次點擊(未預熱)16.0 ms**、預熱後 2.9–9.9 ms,三輪。合成路徑先前量到的是 0–2 ms / 像素 69 ms。**沒有任何一條接近一秒。** 工具留在 `testapp/test_support/measure/real_mouse_latency.swift`,檔頭的量測也已補上「已授權」那一半
- [x] **5b. #126 `onEditingChanged`** — 已完成。五個 backend 全數實作,AppKit/UIKit/Android **實測建置通過**,GTK/WinUI 寫了但未執行(待查假設已在檔內指名)。**P61 是它的測試 app**,自帶對照組
- [x] **M2. #125 Table 的 `selection` 與 `sortOrder` — 兩項都已完成於五個 backend(2026-09-16)** — selection:`BackendFeatures.TableSelection` 落地,Windows 兩個 backend 由此側實作、AppKit/UIKit/Android 由 Mac 實作,**兩個方向都以真實輸入驅動驗過**(探針寫 binding + 動作檔點擊,含「點標題列不得選取」的拒絕對照)。`sortOrder`:同樣五個 backend 到齊,細節見下方各條。以下為原始說明,保留作為背景:欄寬他們已完成並雙 backend 驗收(`2fd81acb`)。剩下兩項需要 **backend→view 的事件回報**,而 `BackendFeatures.Tables` 目前每個方法都是單向的。**關鍵事實:`Gtk.Table` 是包著 `Grid` 的 `ScrolledWindow`,不是 `GtkColumnView`**——對「選取的列」毫無概念,標題也只是不可點的 `Label`。**不要假設與 `NSTableView` 對等**

  - **`sortOrder` 已完成。** Windows 落地了協定 `BackendFeatures.TableColumnSorting`、`TableSortOrder`
    與兩個 Windows backend(`b308559a`);Mac 主機接著落地 AppKit / UIKit / Android,三個平台各以動作檔實測,
    七支新檔 + 先前五支 selection 檔全數重跑(P23 版面改過兩次,座標重量過兩次)。
  - **形狀以 origin 的為準,Mac 那份被丟棄。** 兩邊在同一段時間各自寫了一版:Mac 的 `setSortHandler`
    回報 `TableSortOrder?`、由每個 backend 自行決定「同一欄反轉」;origin 的回報 `column: Int`,由框架的
    `TableSortOrder.toggled(byClicking:)` 決定一次。**origin 的比較好**——Mac 那版等於讓那條規則在
    AppKit/UIKit/Android 各存在一份,而三份之間的任何差異,都會以「某個平台的標題行為不一樣」現身。
    這是 mistakes 第 12 條的第二次發生,而這次兩邊都先查過對面、對面當時是乾淨的。
  - **順手修掉 P23 自己的一個缺陷:** 排序讀數原本與按鈕同一行,`sort: column 3 ascending` 在手機上會
    折成兩行、把表格往下推,於是「在標題上點兩次」的動作檔第二次會落空——而擷圖看起來像是
    「backend 忘了自己的排序狀態」。已改為獨立一行,理由寫在 P23.swift 裡。
- [x] **M4. #121 在 iPhone 上已補上 — `UIResponder.keyCommands`(2026-09-16 完成並驅動驗證)** — UIKit 的 `#121` 目前是
  **iPad ✅ / iPhone ❌**,而那不是「平台沒有 API」。唯一的註冊路徑是 `buildMenu(with:)`
  (`UIKitBackend+Menu.swift:215`),而 iPhone 沒有選單列、`buildMenu` 從不以 `.main` 被呼叫
  ——2026-09-16 在 iPhone 17 Pro Max 上量過,寫在 `actions/ios/P71-shortcuts.actions` 的檔頭。
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
  - `actions/ios/P71-shortcuts.actions` 的檔頭原本寫著「只跑 iPad」,已更正。
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
  - **先前那三筆「未驅動 / 只在小尺度觀察到」的紀錄已被取代,原因在動作檔本身**:`scroll` 欄位的單位是
    **滾輪格數**(一格 40 點,Android 再乘 density),而先前填的是像素大小的數字。見 mistakes 第 17 條。
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
  trap。AppKit 已改為搜尋子樹;**UIKit 可在 Mac 主機上驗證、WinUI 需要 Windows**。
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
    **剛有人與遠端桌面互動之後**的第一次嘗試(19:10 WinUI 排序、19:30 GTK 排序、19:36 指示符);
    而夾在中間那八次在完全沒有互動的情況下連續被拒。下次要驗證需要滑鼠的東西時,請對方動一下、
    然後**立刻**跑——這比重試迴圈有效得多:那個迴圈連跑八次都沒中,而互動後的第一次就中。
    *Both successful sort replays today began right after someone interacted with the remote
    session; eight consecutive attempts with no interaction were all refused. Correlation, not a
    proven cause -- but it is the cheapest thing to try first.*
- [x] **5c. #122 focus / #123 accessibility:protocol 形狀草案已出** — `testapp/plan/plan-focus-protocol.md`。四個方法、`focus` 回傳 `Bool`(Android touch mode 會正當失敗)、`setFocusChangeHandler` 為必要;**#123 與 #122 分開**且可先落地。**待 Windows 回答一個問題**:WinUI 的 `FocusManager.TryFocusAsync` 是非同步的,而草案的 `focus` 是同步的
- [x] **5c-ANSWER(Windows 回覆,2026-09-10):同步的 `focus` 可以照用,形狀不必改。**
  提問針對的是 `FocusManager.TryFocusAsync`,而那不是唯一的路。**`UIElement` 自己有一個同步版本**:
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
  `testapp/plan/plan-120-grid-and-geometry.md` 提出的兩件事,兩件都查證過了:
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
  **以下為原始請求的內容(改以第三人稱記述),保留作為背景;其中「四個欄位都是 `Int`」已不再成立。**
  `EdgeInsets` 的四個欄位都是 `Int`(`PaddingModifier.swift:34-42`),因此**小數 padding 完全無法表達**;
  `.padding(8.5)` 沒有寫法。Sources/ 下有 14 個檔案提到 `EdgeInsets`,而它經由 `baseItemPadding` 跨越
  backend 邊界。
  **要動的是 `Sources/SwiftCrossUI/Views/Modifiers/Layout/`,以及各 backend 讀 padding 之處。**
  第 16 條提到「若要動手,先說一聲,Mac 端會在那段期間避開該檔」——這就是那一聲,只是換一個檔案:
  Windows 端想動的是 `Layout/` 而不是 `GridLayoutPlan`,所以與 #118 **不衝突**,但兩者相鄰到值得先問。
  **請 Mac 端回覆:(a) 近期會動 `Views/Modifiers/Layout/` 嗎?(b) 若 Mac 端接手 #118,兩件事同時進行是否可接受?**
  在收到回覆之前,Windows 端先做 #32(手勢),不碰 layout。
  *A coordination request, not a handover. `EdgeInsets`'s four fields are `Int`, so fractional padding
  cannot be expressed at all -- there is no spelling for `.padding(8.5)`. 14 files under Sources/
  mention it and it crosses the backend boundary via `baseItemPadding`. The Windows side would be touching
  `Views/Modifiers/Layout/`, not `GridLayoutPlan`, so it does not collide with #118 -- but the two are
  adjacent enough to ask first. Asked of the Mac side: (a) whether it will be in `Views/Modifiers/Layout/` soon, and
  (b) whether both can run at once if it takes #118. Until then the Windows side is on #32 and stays out of
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
  - 原本問 Mac 端的兩個問題,答案記在這裡以免再被問一次:**(a) Mac 端從未動過
    `Views/Modifiers/Layout/`**——`git log -- Sources/SwiftCrossUI/Views/Modifiers/Layout/`
    裡沒有 Mac 端的 commit;**(b) Mac 端不接 #118。** 那個目錄屬於 Windows 端。
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
  - **若 Windows 端也正要動 `Sources/InputEvent/` 的格式,需先協調** ——這是 mistakes 第 12 條那個形狀,
    因此這次先公開形狀再寫。
  - **2026-09-17 進度:格式與 iOS 已完成並驅動過,Android 還沒建。**
    - `InputAction.pinch/rotate` 與 `ActionFile.swift` 的解析已落地,形狀與上表相同。
    - **iOS 實測通過**:`actions/ios/P65-pinch-and-rotate.actions`,連續三次執行
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
      `actions/android/P65-pinch-and-rotate.actions`,擷圖 `p65-android-final-20260917-143345.png`:
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
- [x] **6. #74 `-GPU` on macOS — 已實作(AppKit + UIKit)** — 那個「設計問題」其實已被協定的形狀回答了:`GraphicsAdapter` 的三個欄位 `name`/`isRemovable`/`isLowPower` **就是 `MTLDevice` 的三個屬性**,而 `AdapterOutcome.requiresRestart` 的文件早就寫著「macOS 不需要這個,Metal 在執行期選擇」。AppKit 用 `MTLCopyAllDevices()`(系統預設排最前,因為 `.systemDefault` 取 `first`)、UIKit 用 `MTLCreateSystemDefaultDevice()`(`MTLCopyAllDevices` 僅限 macOS,而 iOS 只有一張且不可移除)。**明說它不做什麼**:它不會把視窗移到另一張 GPU——window server 依「視窗所在顯示器」決定合成用的 GPU,macOS 上沒有應用程式做得到。P68 驅動並列出介面卡。**Android 已補上**:回報一張以 SoC 命名的介面卡(`SOC_MANUFACTURER`/`SOC_MODEL`，早於 API 31 的裝置退回 `HARDWARE`),而**不是**空清單——空清單會讓框架解析為「沒有可用的繪圖介面卡」，那句話對每一台 Android 裝置都是假的。名字是 SoC 而非 GPU:真名要 `glGetString(GL_RENDERER)`，那需要對 `EGL_DEFAULT_DISPLAY` 做 `eglInitialize`/`eglTerminate`——也就是 app 正在算繪的那個 display，而 Mac 主機上驗不了它會不會弄壞算繪
- [x] **7. #28 動畫 / #32 手勢** — 五個 backend 全部 conform(`DragGestures`/`MagnifyGestures`/`RotateGestures`、`FrameClocks`)。**未驅動的只剩 magnify/rotate**:當時合成不出觸控板的雙指手勢(之後見 M9:iOS 與 Android 已驅動,AppKit 與 X11 以寫明的理由拒絕)。
- [x] **9. #79 GTK 39px / #109 popover anchor API — 兩項都已定案並落地(2026-09-16),此條為重複指標,一併關閉** — 原文是「需要決定」;#79 見 M3a(已驅動驗收 `shortfall 0x0`),#109 見 M3b(兩個 Windows backend 已成對驗收)。
- [x] **10. #80 P42 縮放通知 — WinUI 通過;GTK 值與執行期變更皆已完成並驅動驗收(2026-09-16,`cd90458e`)** — 需要人在機器前改顯示縮放。
  - **WinUI:通過。** 顯示縮放由 100% 手動改為 125%、**全程未碰視窗**,而該視窗自己記到
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
    一句質疑「GTK 在 Windows 上跟著 scale factor 走才合理」把它推翻了。**對的部分**:
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

## 背景資料,2026-10-05 從 queue.md 搬來 / Background notes moved from queue.md (2026-10-05)

這些不是已完成的項目，而是 queue.md 末尾的背景、決定、回覆與當時的量測，原文照搬。內容反映各自寫下的日期，不代表現況。
Not finished items: the background, decisions, answers and measurements that ended queue.md, moved
verbatim. Each reflects the date it was written, not the present.

## 這份佇列是怎麼來的 / Where this list comes from

**它現在合併了三個來源,而先前只有一個。** 2026-09-09 對照 `todo.md`(樹裡唯一的待辦檔)與 Windows
端貼過來的表之後重建;先前的版本只反映了 Mac 這一側自己推進的工作,因此 Windows 端正在追蹤的項目
一個都不在上面。

**對照的第一個結果是刪掉工作,不是加上工作。** `todo.md` 中「六項交給 Mac」的表裡,有**五項在讀到它
時就已經完成了**——Swift 6 語言模式(AppKit 與 UIKit 都已在 `migratedToSwift6`)、前景色寫死
(`resolvedForegroundColor` 在兩個 backend 共 8 處)、Android 的 `.onHover`(已有
`AndroidBackend+HoverGestures.swift`)、UIKit 的 popover `onDismiss`(已完成)、UIKit 與 Android 的
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

回覆 `testapp/plan/queue-windows.md`。**先講四項 Mac 端以為還開著、但已經收掉的**,因為那份清單寫在
Mac 端 pull 到今天下午的收尾之前。

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
3. **#109 分工照 Mac 端的提案。** Windows 端做 SwiftCrossUI 層 + Gtk + WinUI,Mac 端做 AppKit / UIKit / Android。
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
Mac 端量的是 **per-cell layout cost**(primitive / custom / text 三臂)。同一支 P52、不同的被測量。
在那一格對齊之前,30 倍是兩個不同量之間的比值,而不是同一個量的跨 backend 差異。

**P28 的「一秒」:這棵樹裡沒有任何 Windows 紀錄可以支撐它。**
`matrix_coverage/results.csv2` 中 P28 有 mac、android、ios、wsl 的列,**windows 一列都沒有**。
所以那份回報若來自 Windows,它從未被記錄下來;若來自 macOS,Mac 端已經量完並推翻(冷啟 16 ms)。
`queue.md` 自己也早就標註過它是「**一次觀察而不是一個量測**」。**這一格由 Windows 端補上量測。**

*The 0.3 s is a Windows/GtkBackend measurement with a stated method — but it measured button press
transitions, not per-cell layout cost, so the 30x is a ratio between two different quantities until
that is aligned. The one-second P28 report has no Windows row anywhere in results.csv2 to support it;
this side will measure it.*

---

## 更正:#123 在 GTK/Windows 上**做得到**,先前說反了

### Correction: #123 IS reachable on GTK/Windows

2026-09-11。先前寫下的是「Windows 上的 accessibility 是 WinUI-only,除非 GTK 上游補上 UIA bridge」。
**那句話是錯的**,而且它正是 CLAUDE.md 明令禁止的形狀——把「這個平台沒有內建 X」說成「這個平台
做不到 X」。這一點當場被指出,而規則寫得很清楚:那是**待查證的主張,不是結論**,而且答案仍然是
去找出該平台**做得到**的方式。

錯誤的部分不是量測,是從量測推出的結論。量測本身仍然成立:`C:/gtk4` 有 **0** 個 atk/at-spi
程式庫(對照 67 個 dll),`gtk-4-1.dll` 有 **130** 處 `gtk_accessible` 與 **0** 個 UIA 符號
(對照 `gtk_widget_grab_focus` 2)。**GTK 確實不會把它自己的樹送給任何輔助技術。**
但那不是本專案要送的樹。

### 為什麼那不擋路

**#123 要暴露的是 SwiftCrossUI 的 `.accessibilityLabel(...)`,不是 GTK 的 accessible 樹。**
那個資訊在 SwiftCrossUI 層產生,GtkBackend 只需要把它存起來再交出去——而「存進側表再回答」
正是這個 backend 已經為 slider 的編輯狀態、table 的欄寬做過的事。

三個環節都已查證,每一個都已經在本樹中被使用:

| 環節 | 證據 |
| --- | --- |
| 取得 GTK 視窗的 HWND | `GtkBackend.swift:1904` 自述「on Windows a GTK window is an ordinary `HWND`」,且 `SetWindowPos` 已在用它 |
| 手寫 COM 介面與 IID | `D3D11VideoInterop.swift:176` 明說「hand-declared IIDs rather than linking against dxguid.lib, so no extra linker settings are needed」;`lpVtbl`/`QueryInterface` 出現在四個檔案 |
| UIA 的 provider 端 | 基於 HWND:回應 `WM_GETOBJECT`、回傳 `IRawElementProviderSimple`。`UIAutomationCore.h` 位於 Windows Kits 10.0.22621.0 |

也就是說:**GTK 缺的是「把它自己的樹送出去」,而本專案要送的本來就不是它的樹。**
一個掛在該 HWND 上的 UIA provider,從 SwiftCrossUI 的標籤側表回答,完全不經過 `gtk_accessible`。

### 誠實的成本

這不是一個旗標,是一份實作:視窗程序的 `WM_GETOBJECT`、一組手寫 vtable、以及把
`IRawElementProviderFragment` 的父/子/兄弟關係映射到 view 樹。**但它不是「不可能」,
而先前那句話讓它讀起來像不可能。**

*Correcting myself: "accessibility is WinUI-only on Windows" was wrong, and wrong in the shape
CLAUDE.md forbids -- "no built-in bridge" restated as "the platform cannot". The measurements stand;
the conclusion drawn from them does not. #123 exposes SwiftCrossUI's labels, not GTK's accessible
tree, and a UIA provider hung on the GTK window's HWND answers from a side table without touching
`gtk_accessible` at all. All three pieces -- the HWND, hand-written COM vtables, the UIA provider
API -- are already used in this tree. Real work, not impossible.*

---

## 減少不必要的重繪 / Reduction of unnecessary redraw

加入佇列於 2026-09-11,起因是一個問題:「GTK 只在必要時更新畫面是否比較省電?」
Added to the queue 2026-09-11, prompted by the question "does GTK's redraw-only-when-needed save
power?" It does, and the interesting part is that the answer is a *framework* question, not a
per-backend one.

### 已經在位的部分 / What is already in place

**兩個 backend 對「幀」的立場相反,而框架已經在兩者之上做了收斂。**
The two backends take opposite positions and the framework already reconciles them.

| | 閒置時 | 表達「我要幀」的方式 |
| --- | --- | --- |
| GTK | 不產生幀 | `gdk_frame_clock_begin_updating` / `end_updating`,計數成對 |
| WinUI | `CompositionTarget.Rendering` **只要有人訂閱就每幀觸發** | 訂閱 / 取消訂閱 |

`Sources/SwiftCrossUI/Animation/AnimationDriver.swift` 已經是 GDK 那套計數,只是計的是 tween:
`startClockIfNeeded()` 在第一個 tween 註冊時才 `startFrameClock`,`stopClockIfIdle()` 在
`tweens` 一空時 `stopFrameClock`,而 `tick(at:)` 的最後一行就是 `stopClockIfIdle()`——所以
最後一個動畫結束的**那一幀**就把時鐘拆掉。WinUI 因此不必改:省電的唯一施力點是「閒置時不訂閱」。

`AnimationDriver` is already GDK's refcount with tweens as the count. WinUI needs no change: the
only lever is not being subscribed while idle, and that is what `stopFrameClock` is.

### 沒有被跑過驗證的部分 / What has NOT been verified by running

**這一段是設計對了,不是量到了。** P64 直接驅動 backend requirement,繞過 `AnimationDriver`,
所以沒有任何量測顯示 `frameClockToken?.dispose()` 真的解除了 WinUI 的訂閱。

The design is right; nothing has been measured. P64 drives the backend requirement directly and
bypasses `AnimationDriver`, so no measurement shows that `frameClockToken?.dispose()` actually
unsubscribes.

決定性的實驗很便宜,而且**兩個結果都有意義**:start → stop → 再 start,量第二段的速率。
The experiment is cheap and both outcomes say something: start, stop, start again, and measure the
second window.

- 仍是約 141 Hz → 取消訂閱有效
- 約 283 Hz(兩倍)→ 第一次訂閱洩漏了,而每一次動畫都會再洩漏一次
- ~141 Hz means the unsubscribe works; ~283 Hz means the first subscription leaked, and every
  animation would leak another.

**為什麼倍數是可讀的證據而不是巧合:** `CompositionTarget.Rendering` 每幀觸發一次,而 handler 是
一個型別屬性——兩個活著的訂閱會讓同一幀被數兩次。若改用「有沒有跳」來驗,兩種情況都會跳,那個
測試無法分辨它們。

### 相鄰但**不同**的一項,不要混為一談 / An adjacent item that is NOT the same

上面談的是**時鐘**的訂閱。「view 內容沒變卻仍重繪」是另一件事,尚未量測,也還沒有人主張它存在
——本節不宣稱它。要提出它,需要的是一個計數:同一個 widget 在一次沒有狀態變動的 layout pass 中
被要求重繪幾次。

The above is about the CLOCK subscription. "A view redrawing when its content did not change" is a
different thing, unmeasured, and not claimed here. Raising it needs a count first.

---

## 這份 queue 會漂,而重新產生它的指令在這裡(2026-09-16)

本檔上方有五條描述的是**已經完成**的工作,卻讀起來像未開始。那不是誰偷懶:**一個 queue 檔記錄的是
「某人寫下它時相信什麼」**,而它不會自己過期。同一天這件事讓 #121 被實作了兩次(`mistakes.md` 第 12 條)。

**不要讀這份表來判斷某件事做完了沒有。去問原始碼:**

```sh
# 每個 backend 真正宣告的 BackendFeatures conformance
for be in GtkBackend WinUIBackend AppKitBackend UIKitBackend AndroidBackend; do
  echo "--- ${be%Backend}"
  grep -rhoE "BackendFeatures\.[A-Za-z]+" Sources/$be/ | sed 's/BackendFeatures\.//' | sort -u | tr '\n' ' '
  echo
done
```

**用 `grep -rhoE "BackendFeatures\.[A-Za-z]+"`,不要用 `extension X: BackendFeatures\.Y`。** 後者是
2026-09-16 的第一個版本,它**兩個方向都錯**:多行的 conformance 寫法

```swift
extension AppKitBackend:
    BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
```

被漏掉(偽陰性,看起來五個 backend 都沒有 magnify),而註解裡提到協定名稱的行被算進去(偽陽性,
讓人以為 UIKit 讀了 `keyboardShortcut`,其實那兩處是註解寫的「此處**沒有**讀取」)。

**先跑正對照再相信任何一個零**:一個確定存在的名字(`WidgetGeometry` 五個都該有)與一個確定不存在的
(`ZZZNotARealProtocol` 應回傳空)。

---

## The command that regenerates this, because this file drifts (2026-09-16)

Five open items above described work that was FINISHED. That is not laziness: a
queue file records what someone believed when they wrote it, and it does not
expire. On the same day, that cost `#121` a second implementation
(`mistakes.md` entry 12).

Do not read this table to decide whether something is done. Ask the source, with
the command above.

Use `grep -rhoE "BackendFeatures\.[A-Za-z]+"`, not a pattern anchored on
`extension X: BackendFeatures.Y`. The latter was the first version and it was
wrong in BOTH directions: it missed multi-line conformances (so all five
backends looked like they had no magnify gesture) and it counted comments that
merely name a protocol (so UIKit looked like it read `keyboardShortcut`, when
those two hits were a comment saying it does NOT). Run both controls before
believing any zero.

---

## 五個 backend 的能力缺口,逐格開成待辦(2026-09-16 由原始碼查得)

CLAUDE.md:**任何功能都不得在這五個 backend 上維持「不支援」。** 以下每一格都是那條規則下的一筆欠債。

| 缺口 | 誰 | 備註 |
| --- | --- | --- |
| ~~UIKit `keyboardShortcut`(#121)~~ | **完成** | **已驅動並通過**:iPad(iOS 27)上 `plain 1、shifted 1、disabled 0`,選單全程關著,走 `test_ios.zsh --actionfile`。**根因不是快捷鍵**:`UIKitBackend` 的 `ApplicationMenus` conformance 被關在 `#if targetEnvironment(macCatalyst)` 裡,因此在真正的 iOS 上,框架的 `backend as? any BackendFeatures.ApplicationMenus` 直接失敗、`setApplicationMenu` 從不被呼叫,而 `buildMenu` 對著一份**空清單**建選單(讓它寫出自己看到的東西才追出來:`buildMenu system==main: true submenus=0`)。所以 `.commands` 與 `CommandMenu` 在 iOS 上**完全沒有作用**,不只是快捷鍵。那個 `#if` 帶著上游自己的條件——「等快捷鍵實作出來,或許就能推廣到 Catalyst 以外」——而今天的工作讓它成立了。 |
| ~~Android 應用程式選單(`setApplicationMenu`)~~ | **完成** | **已實作並驅動驗證**:`plain 1、shifted 1、disabled 0`,以 `adb shell input keycombination` 驅動,選單全程不開。那個註解掉的樁帶著上游的 TODO「Register app menu items as shortcuts when we support keyboard shortcuts」——現在它做的正是那件事。**Android 沒有應用程式選單可畫,而那是平台的答案、不是留下的缺口**:全域動作屬於 toolbar 溢位或側邊抽屜,那是 app 自己的版面;在此畫一條,等於替 Android 上每一支 app 都加上橫槓,無論它有沒有宣告 `.commands`。用 `addOnUnhandledKeyEventListener` 而非 `setOnKeyListener`——unhandled 那個變體只在每一個 view 都拒絕之後才跑,因此 Cmd-S 不會在聚焦的文字欄位看到它之前被吞掉,而打進該欄位的普通 `s` 根本不會抵達。修飾鍵比較採**完全相等**(否則 Ctrl-Shift-S 會連帶觸發單純的 Ctrl-S),並遮掉 CAPS_LOCK/NUM_LOCK(否則 Caps Lock 一開,每個快捷鍵都失效)。 |
| ~~GTK `LazyListRows`(#117)~~ | Windows | **已完成 `5739d453`,而且這一格正是那支探針要抓的東西。** `LazyListRowLifetimes: LazyListRows`——**繼承即 conformance**,而那個 extension 兩個方法都實作了(`setLazyRows` 與 `setLazyRowReleaseHandler`,`GtkBackend+LazyListRows.swift:5,12`)。「只 conform Lifetimes,按需建列未做」是從缺少的**名字**推出來的,而非從方法推出來的。**把這一格當探針的正對照:任何回報 GTK 缺 `LazyListRows` 的判準就是壞的。** |
| ~~GTK `Accessibility`(#123)~~ | Windows | **已完成 `9746bbeb`。** 用的是 `gtk_accessible_update_property_value` / `_state_value`——**帶計數的非 variadic 變體**,因為 variadic C 函式在 Swift 裡叫不動。`GTK_ACCESSIBLE_PROPERTY_LABEL` / `_DESCRIPTION` 之外還有 `ItemStatus`。**限制寫明**:GTK 那邊**沒有讀回路徑**,`gtkaccessible.h` 只有 update、沒有 getter,要讀得走 AT-SPI(Linux only) |
| ~~WinUI `Accessibility`(#123)~~ | Windows | **已完成 `9746bbeb`,並於 `23c9cc61` 以 P69 實測讀回。** `AutomationProperties.Name` / `HelpText` / `ItemStatus` / `setAccessibilityView(.raw)`。**限制**:讀回是**行程內**的(`VisualTreeHelper`),它對 Narrator 實際唸出什麼沒有發言權 |
| ~~GTK `FocusableViews`(#122)~~ | Windows | **已完成 `4c7bbf12`。** `gtk_widget_grab_focus` 確實直接叫得到。踩到的一點:TextField 是包著 `GtkEntry` 的 wrapper,所以回報那一半用的是 `EventControllerFocus` 的 `enter`/`leave`,不是 `notify::has-focus` |
| ~~WinUI `FocusableViews`(#122)~~ | Windows | **已完成 `4c7bbf12`——形狀不必改,而那個答案 2026-09-10 就寫在上面 5c-ANSWER 了。** `UIElement.focus(_:) throws -> Bool` 是同步的;`TryFocusAsync` 是另一個變體,不是取代品。真正的陷阱不是同步與否:本 backend 交出去的每個 widget 都是 `Canvas`,而 `Canvas` 無條件接受焦點,所以得往內走到真正 `isEnabled && isTabStop` 的控制項 |
| ~~**WinUI `LazyListRowLifetimes`(#117)**~~ | **Windows,同日完成並量測** | 上面那一格查證時發現的**真缺口**,方向與原表相反:**GTK 有、WinUI 沒有**。**已實作並以對照組驗收**:同一支執行檔掃過 5000 列(約 9000 次 prepare / 9000 次 recycle),release 開啟 **146 / 150 MB**,`SCUI_WINUI_NO_LAZY_RELEASE=1` 的對照組 **221 / 222 MB**,交錯兩輪、無重疊;兩組的實體化容器都是 38,因此**差的 72–76 MB 全是框架端的 view-graph 節點**。對照組是必要的,因為 conform 這件事本身會把 `List.swift` 從 200 列 LRU 換成 4000 列兜底——少了它,「加了 conformance」與「回呼真的有觸發」會同時改變。訊號是 `ContainerContentChanging` 的 `inRecycleQueue` + `args.itemIndex`(不是 `ItemsRepeater.elementClearing`,`ListView` 走的是這條)。**三個看起來都對卻被量成假的假設**寫在 `WinUIBackend+LazyListRows.swift` 裡加了刪除線的註解中。**AppKit / UIKit / Android 仍只有 GTK 有**——那三個不是我編得動的,留給 Mac 判斷 |

**這六格是查證過的。** 一次完整的掃描會列出更多 `NO`,但那份清單目前**不可信**:很多協定是由基底
backend 協定**繼承**而來、而不是以 `BackendFeatures.X` 具名 extension 實作的,因此「名字沒出現」不等於
「沒有實作」。2026-09-16 曾試著自動分辨兩者,那個判準抓到 0 個繼承項目——所以它是壞的,因此沒有
拿它去開 39 條待辦。**要補完這張表,得先寫出一個能通過正反對照的探針。**

**Windows 端回覆(2026-09-16 15:xx):這張表寫下時,五格 Windows 欄位中的五格都已經關掉了**
——#122 與 #123 於 `4c7bbf12` / `9746bbeb` 落地、#117 的 GTK 側於 `5739d453`,全部早於本表。
這不是抱怨,而是**它示範的正是同一段文字自己警告的那件事**:五格裡有一格(GTK `LazyListRows`)
的判定完全來自「具名 extension 沒出現」,而它是**繼承**來的;另外四格則是**時間差**——表從原始碼
查得,而原始碼在幾小時前就變了。所以那支探針需要的不只是繼承判準,還要**一個日期與一條重新產生的
指令**,否則下一份表在寫完的當天就開始腐爛(user CLAUDE.md:超過 7 天的文件即為未查證)。

**探針的兩個對照組,現在都有現成的實例,不必另外造:**

- **正對照(必須回報 YES)**:`GtkBackend` 對 `BackendFeatures.LazyListRows` —— 具名 extension
  寫的是 `LazyListRowLifetimes`,而它 refine 了 `LazyListRows`,兩個方法都在裡面。
- **負對照(必須回報 NO)**:`WinUIBackend` 對 `BackendFeatures.LazyListRowLifetimes` ——
  這是**真的**沒有,上面新開的那一格就是它。

一個把這兩格都答對的判準才可以拿去開那 39 條;只答對一格的,答對的那一格是巧合。

---

## The capability gaps, one todo per cell (read from the source, 2026-09-16)

CLAUDE.md: no feature may be left "not supported" on these five. Each cell above
is a debt under that rule. UIKit's `keyboardShortcut` is the Mac side's and was
created today; the other five are the Windows side's, and `queue-windows.md`
carries the details for each.

Those six are verified. A full sweep reports more `NO`s and that list is NOT
trustworthy yet: many protocols are satisfied by INHERITANCE from the base
backend protocol rather than by a named `BackendFeatures.X` extension, so "the
name does not appear" is not "it is not implemented". An attempt to separate the
two automatically found zero inherited protocols, which means the discriminator
is broken -- so it was not used to open 39 todos. Completing this table needs a
probe that passes a positive and a negative control first.

**Windows reply, same day.** All five Windows cells were already closed when the
table was written -- #122 and #123 in `4c7bbf12` / `9746bbeb`, the GTK half of
#117 in `5739d453`, all of them hours earlier. That is not a complaint; it is
the table demonstrating the thing its own last paragraph warns about. One cell
(GTK `LazyListRows`) was judged purely on a name that does not appear, and the
conformance is INHERITED: `LazyListRowLifetimes` refines `LazyListRows` and the
extension implements both methods. The other four were simply out of date within
hours, which says the probe needs a DATE and a regeneration command as much as it
needs an inheritance rule.

The two controls now exist as real cells, so neither has to be invented:

- **Positive (must report YES)**: `GtkBackend` vs `BackendFeatures.LazyListRows`,
  satisfied through the `LazyListRowLifetimes` extension.
- **Historical negative (no longer valid)**: `WinUIBackend` vs
  `BackendFeatures.LazyListRowLifetimes`. This now reports YES.

A discriminator that gets both right can open the 39; one that gets a single cell
right got it by luck.

**All five backends now implement the lifecycle protocol** (24319bd6).
Use an explicit nonconforming test fixture for the negative control, not one of
these production backends. 五個 backend 皆已實作，負對照應使用未 conform 的測試型別。

WinUI now conforms, measured rather than asserted: one binary, two runs
interleaved twice, each sweeping 5,000 rows (~9,000 prepares, ~9,000 recycles).
With the release callback: **146 and 150 MB**. With `SCUI_WINUI_NO_LAZY_RELEASE=1`,
which keeps the conformance and withholds the callback: **221 and 222 MB**. No
overlap between the groups, and both ran with 38 realized containers, so the
72-76 MB is entirely framework row nodes. The control switch is not optional
here: conforming is itself what moves `List.swift` from its 200-row LRU to the
4,000-row backstop, so without holding one half still, "conformed" and "actually
releases" change together and neither number means anything.

The signal is `ContainerContentChanging` with `inRecycleQueue`, and the index is
`args.itemIndex`. Three plausible alternatives were measured false first; they
are kept, struck through, in `WinUIBackend+LazyListRows.swift`.

---

## 停在待辦上:iOS 的按鍵驅動(低優先,2026-09-16)

**UIKit 的 `keyboardShortcut` 已實作並提交(`cfc442aa`),卡的是「驗證」而不是「實作」。**

按鍵送不進模擬裝置,而這是用**兩次正對照**量出來的,不是推論:

| 嘗試 | 結果 |
| --- | --- |
| iPhone 17 Pro Max | `buildMenu` 從不以 `.main` 被呼叫——iPhone 沒有選單列,不會有 key command 被登記 |
| iPad Pro 13" / iOS 27 | 三個計數皆 0 |
| 正對照 #1 | P70 顯示 `focused field: email`、游標在欄位裡(**app 是活的**),而送出的 `a h v` 一個都沒進去 |
| 正對照 #2 | 先送 ⇧⌘K(Simulator 的「把鍵盤輸入送到裝置」)再送,同樣沒進去 |

已排除:`simctl` 沒有 `sendkey` 動詞、`idb` 未安裝、DeviceHub 不透過 AX 暴露選單列。

**三條出路,依成本排序:**

1. DeviceHub 自己的鍵盤開關——若那個 UI 上有,用 AX 或座標點它
2. `brew install facebook/fb/idb-companion`,然後 `idb ui key`
3. **XCUITest target** —— iOS 上受支援的驅動方式(`XCUIApplication().typeText()`)。這也是
   `testapp/actions/ios/` 至今空著、其 README 標 `planned` 的真正原因

第 3 條做完,iOS 就從「只能靠 app 自報」變成能被真實驅動,而那對 P63 之後的每一支 app 都有效。

**在此之前,UIKit #121 的狀態是「實作完成、未驅動」,而依本樹的規矩那不算完成。**

---

## Parked: driving keys into iOS (low priority, 2026-09-16)

UIKit's `keyboardShortcut` is implemented and committed (`cfc442aa`). What is
blocked is the verification, not the implementation.

Keystrokes do not reach the simulated device, established with two positive
controls rather than inferred: P70 showed `focused field: email` with a caret --
the app is alive and responding -- and three plain letters sent the same way did
not appear in the field, with and without Simulator's ⇧⌘K toggle first. On an
iPhone the question does not even arise: `buildMenu` is never called with
`.main`, so no key command is registered.

Ruled out: no `simctl sendkey` verb, `idb` not installed, DeviceHub exposes no
menu bar over accessibility.

Three ways out, cheapest first: a keyboard toggle inside DeviceHub itself; `idb`
and its `ui key`; or an XCUITest target, which is the supported way and is why
`testapp/actions/ios/` is still empty and marked planned. The third would move
iOS from "the app reports on itself" to "the app can be driven", which pays for
every Pn from P63 onward.

---

## #125 Table 的 selection 與 sortOrder:開工前先講形狀(2026-09-16,Windows 端)

**先寫這一段再動手,理由是今天早上那次撞車(mistakes 第 12 條):`queue` 說「blocked on Mac」
是寫的當下為真,而不是現在為真。** 這一段推出去之後才開始寫,若 Mac 已經有別的形狀,請直接覆蓋
這裡,Windows 端照著改。

**先查證的事實,不是假設:** `git log origin/develop -S'sortOrder'` 與 `-S'TableSelection'` 在
`Sources/` 之下**零命中**;`BackendFeatures/Tables.swift` 最近三次改動是 `2fd81acb`(逐欄寬度)、
`6d52866a`(文字選取)、`f1bc7f23`(協定拆分),都沒有 backend→view 的事件。

**兩個 backend 的真實結構(這決定了做法,而不是 `NSTableView` 的類比):**

| | 是什麼 | 因此 |
| --- | --- | --- |
| `Gtk.Table` | `GtkScrolledWindow` 裡的 `GtkGrid`,標題是不可點的 `GtkLabel` | **沒有「列」這個物件**,也沒有現成的選取 |
| `WinUITable` | 同樣是一個 `Grid` | 同上 |

兩邊都**不是** GTK 的 `GtkColumnView` / WinUI 的 `DataGrid`,而那是刻意的:協定交給 backend 的是
一個**已建好的 widget 扁平陣列**,走 model-driven 的元件等於把每個 cell 再包成 GObject 餵給一個
隨即原樣交還的 model(理由寫在 `Sources/Gtk/Widgets/Table.swift` 檔頭)。所以選取與排序這兩件事,
在這兩個 backend 上都得**自己做**:以 click gesture 命中列、以樣式畫出選取、把標題做成可點。

**打算加的協定形狀**(與 `SelectableListViews` 對齊,那是這棵樹既有的答案):

```swift
public protocol TableSelection: Tables {
    func setSelectionHandler(ofTable: Widget, to: @escaping (Int?) -> Void)
    func setSelectedRow(ofTable: Widget, to index: Int?)
}

public protocol TableColumnSorting: Tables {
    func setSortHandler(ofTable: Widget, to: @escaping (_ column: Int) -> Void)
    func setSortIndicator(ofTable: Widget, column: Int?, ascending: Bool)
}
```

- **兩個協定分開**,理由與 `LazyListRows` / `LazyListRowLifetimes` 分開相同:一個 backend 可能
  做得到其中一個而不是另一個,而合成一個協定會讓「做得到一半」變成「宣稱兩個都有」。
- **採 conformance 檢查**,所以未實作的 backend 行為完全不變。
- **排序由 app 自己做。** backend 回報的是「使用者點了第 n 欄」,框架把它變成一個 binding 的更新,
  由 app 重新排序自己的資料——框架不介入 comparator。這與 SwiftUI 的 `sortOrder` 精神一致,
  但不需要 `KeyPathComparator` 那一整套。

**分工(沿用 #121 那次講定的「各做自己編得動的」):** 協定與 view 端由 Windows 端落地,GtkBackend 與
WinUIBackend 兩個實作也由 Windows 端做並驗收;**AppKit / UIKit / Android 三個是 Mac 那邊的**——
`NSTableView` 與 `UITableView` 本來就有選取與可點標題,成本應該遠低於這裡。

**分兩批做,selection 先。** 它自成一件完整的事、可獨立驗收,而排序還要處理指示符的繪製。

### selection 進度(2026-09-16 當天完成一半並驗收)

**`BackendFeatures.TableSelection` 已落地,兩個 Windows backend 都實作並以畫面驗過。**
`Table(rows, selection: Binding<Int?>)` 為 view 端的新初始化式;選取以**索引**表示,因為
`RowValue` 沒有任何約束——沒有 `Identifiable`、連 `Equatable` 都沒有——所以沒有東西可以拿來
比對把某一列找回來。

**已驗證:框架 → backend(`setSelectedRow`)。** P23 新增 `--select-probe`,以計時器寫入 binding,
完全不需要滑鼠(機制與 P70 的 `SCUI_P70_AUTOFOCUS` 相同,而那支在兩個 backend 上都重放過)。

| | log | 畫面 |
| --- | --- | --- |
| WinUI | `row selection supported: yes`、`SELECTION now 2 / 5 / none` | `p23-sel-row5-20260916-134321.png`:ID=3 那列(索引 2)整列有底、文字仍可讀;`p23-sel-none-…png`:底色消失 |
| GTK | 同上 | `p23gtk-sel-row5-20260916-134434.png`:ID=6 那列(索引 **5**)有底——與 WinUI 那張是**不同的列**,所以高亮是跟著 binding 走、不是畫死的 |

**截圖是必要的,不是錦上添花。** log 看不見「一個從未被畫出來的高亮」——那正是 #117 在 WinUI 上
記憶體量對了、畫面卻全空的那個形狀。

**~~尚未驗證:backend → 框架(點擊變成 binding 的寫入)。它需要真實指標事件,而這台機器在遠端
桌面連線時拒絕注入滑鼠。~~ 同日以真實滑鼠驗完,而那句「拒絕注入」是錯的。**

**那段阻擋警告不是結論,卻被當成了結論。** 它自己寫著「這是**相關性**,不是已證實的成因」,
卻被用來解釋為什麼不驗。實際去跑之後:`SetCursorPos` 生效(`cursor=(406, 621)` 與要求值相符),
**CDP 連著時滑鼠是可用的**。先前那次「點了沒反應」的真正差別在於啟動方式(經 harness 與直接執行),
不是輸入被拒絕。

兩個動作檔都留在 repo 裡,各三次點擊,而**中間那次是拒絕對照**:

| 檔案 | backend | 判決 |
| --- | --- | --- |
| `actions/win/P23-select-rows.actions` | WinUI | 第六列 → `SELECTION now 5`;**標題列 → 一行都沒有**;第一列 → `SELECTION now 0` |
| `actions/win/P23-select-rows-gtk4.actions` | GTK | 完全相同的三個答案,而走的是完全不同的路徑 |

**分成兩個檔案而非共用座標**,因為兩個視窗大小不同、列的位置也不同(GTK 848x688 自 y=368 起,
WinUI 822x652 自 y=325 起)。照抄另一份會點到標題列與第一列,而**兩次點擊都仍然會回報成功**。

WinUI 側以 `SCUI_WINUI_TABLE_TRACE` 量到機制:`handleClick y=172/10/32` 對上
`heights=[18, 28, 28, 28]`,分別命中 definition 6/0/1。**標題列高 18、資料列高 28**——這正是
命中測試累加 `actualHeight`、而不是拿列高去除的理由:若用相除,這三次會整整差一列。

### Selection, half done and verified the same day

`BackendFeatures.TableSelection` has landed and both Windows backends implement
it. The framework-to-backend direction is verified with pictures: P23's new
mouse-free `--select-probe` writes the binding on a timer, and the captures show
the band on the ID=3 row under WinUI and the ID=6 row under GTK -- different
rows, so the highlight follows the binding rather than sitting where it was
painted -- and gone again when the selection clears. The log alone could not
have shown that: a highlight that is never drawn logs exactly like one that is,
which is how #117 passed on memory here while rendering nothing.

~~The click-to-binding direction is NOT verified; this machine refuses pointer
input while a remote-desktop host is connected.~~ **Verified the same day with a
real mouse, and that sentence was wrong.** The blocker note says of itself that
it is a correlation rather than a proven cause, and it was used as a conclusion
anyway. Driving it: `SetCursorPos` took, the cursor landed where it was asked to,
and both backends selected. The earlier run that saw nothing differed in how the
app was launched, not in whether input was accepted.

Two action files are kept, three clicks each, the middle one a control:
`actions/win/P23-select-rows.actions` (WinUI) and `-gtk4.actions` (GTK). Sixth row ->
`SELECTION now 5`; the HEADER -> no line at all; first row -> `SELECTION now 0`.
Separate files rather than shared coordinates because the windows differ in size
and the rows sit elsewhere -- copying would click the header and still report
success.

`SCUI_WINUI_TABLE_TRACE` shows the mechanism on the WinUI side: y=172/10/32
against heights [18, 28, 28, 28], matching definitions 6/0/1. The header is 18 px
and the rows are 28, which is why the hit test accumulates `actualHeight` rather
than dividing -- dividing puts all three clicks one row out.

## #125 Table selection and sortOrder: the shape, before writing any of it

Published before starting, because of this morning's collision (mistakes entry
12): a queue line saying "blocked on Mac" was true when written, not now. If the
Mac side already has a shape for this, overwrite this section and the
Windows side follows it.

Checked rather than assumed: `-S'sortOrder'` and `-S'TableSelection'` find
nothing under `Sources/` on origin, and the last three changes to `Tables.swift`
(`2fd81acb`, `6d52866a`, `f1bc7f23`) add no backend-to-view event at all.

Both Windows tables are a `Grid` -- GTK's inside a `ScrolledWindow`, with plain
`Label` headers -- and deliberately not `GtkColumnView` or `DataGrid`, because
the protocol hands the backend an array of already-built widgets. So there is no
row object and no built-in selection on either: hit-testing a click, drawing the
selection, and making a header clickable are all hand work here, which is the
part worth knowing before anyone estimates it.

Two protocols rather than one, for the reason `LazyListRows` and
`LazyListRowLifetimes` are separate: a backend may manage one and not the other,
and merging them turns "half of it" into a claim of both. Conformance-checked, so
a backend that does not implement them behaves exactly as it does today. Sorting
is reported, not performed: the backend says which column was clicked, and the
app re-sorts its own rows.

Split: protocol, view side, GtkBackend and WinUIBackend here; AppKit, UIKit and
Android are the Mac side's, where `NSTableView` and `UITableView` already have
selection and clickable headers. Selection lands first, on its own.

## Archived 2026-10-06 from queue.md

### 2026-09-27 found while driving iOS

- [x] **FIXED 2026-09-29: a re-layout reuses each node's kept body.** A node keeps
  the body its view's default layout evaluated (`BodyCapture` / `lastBody`); a pass
  started by a child's resize -- or by the window when its content resized, which
  no longer recomputes the scene -- carries `EnvironmentValues.reusesBodies`, and
  every node on it lays out its kept body instead of evaluating `body`. Commit
  always uses the laid-out body, so a commit builds no views. The flag and the
  cache are pass-only and never stored, so a node's own update still evaluates its
  body. Evidence: the `withKnownIssue` test began reporting "known issue was not
  recorded" and is now a plain expectation that fails without the change (shown);
  whole test product passes. P45Model: 7 constructions per run on macOS before,
  now the 4 at launch and none on any state change; Android 2 at launch and none
  after. Full sweeps on the change: macOS 83/83 and iOS 74/74, each capture
  compared pixel-wise with the last verified one -- all identical but the pages
  that change by themselves (spinning cube, video, network images) and P38, whose
  failures came from example.com now serving localized pages (macOS now follows
  the link with Option-Tab; iOS loads P38's own fixed page via -url). Launch still
  builds the root view a few times (the window probes its minimum and maximum
  sizes with the scene); that is bounded and was left alone.
  **Independently confirmed 2026-09-29 by SoftPCB-mac on 268502a8 (clean
  sources):** GeometryRenderModel.init 28 -> 7, 9, 7 over three runs of the same
  action file (tab 9, a coupon clicked twice); every init before the first
  `select` -- launch and the tab switch -- and none after either click; one model
  ObjectIdentifier throughout, selection held. Probe reverted on their side.
  **2026-09-29 由 SoftPCB-mac 在 268502a8 上獨立確認:**28 次降為三次執行的 7、9、7,全部發生在啟動與切換分頁時,兩次
  點擊之後一次也沒有;model 全程同一個物件,選取保住。Original entry:
  **Core: a child's resize makes its parent re-evaluate `body`, so views are
  re-created on every state change that changes a size.** Every `computeLayout`
  evaluates `body`, and `bottomUpUpdate` climbs through `onResize`. Consequence
  left after the ObservedObject fix: initial-value expressions of wrappers run far
  more often than in SwiftUI.
  **Attempted 2026-09-29, reverted.** A pass-only `reusesChildViews` flag, set by
  `onResize` (node and window) and never stored, so nodes keep their views and the
  window stops recomputing the scene. The whole test product still passed, but the
  new test -- a child's @State change must not construct the child again -- failed
  IDENTICALLY with and without it: laying the parent out evaluates its body, and
  evaluating `VStack { Child() }` builds `Child` whether or not its node takes it.
  The flag only prevented the adoption, which the ObservedObject fix already
  handles, at the price of relayouts no longer applying new views on every
  backend. **What a real fix needs:** a re-layout that does not evaluate `body` --
  each node keeping the body value it last computed and laying that out, which
  touches every default implementation in `View` (children, layoutableChildren,
  asWidget, computeLayout, commit). The test stays in `ObservedObjectTests` under
  `withKnownIssue`; it will report when this is fixed.
  **2026-09-29 試過並撤回。**只屬於該趟的 `reusesChildViews` 旗標無法阻止子 view 被建出:排版父層就會求值 body,
  而求值本身就會建出子 view。真正的修法是重新排版時不求值 body——每個節點保留上次算出的 body 值並排版它,這會
  動到 `View` 所有預設實作。測試以 `withKnownIssue` 留在 `ObservedObjectTests`,修好時會自己報告。
- [x] **CLOSED 2026-09-29 -- does not reproduce.** A long press held with the menu
  open, captured three times (p72-ios-final-20260929-000335/000434/000453.png):
  Reset the camera and Snapshot shown, no keyboard in any of them. The suspected
  cause does not exist either: `KeyEventWidget` is a view CONTROLLER that becomes
  first responder and adopts no `UIKeyInput`, so UIKit has no text input to show a
  keyboard for. The 2026-09-27 captures predate the RootScrollHost and
  first-responder changes of 09-27/28 and the simulator's one-time typing sheet;
  which of those it was is not known. Original entry:
  **UIKit: a long press on P72's mesh view raises the software keyboard.**
  Seen in every capture of the open context menu on 2026-09-27 (and once as
  the simulator's one-time "Speed up your typing" sheet). Suspected, NOT
  verified: the view takes first-responder status for `.onKeyPress`, and UIKit
  shows a keyboard for a first responder that accepts text input. SwiftUI's
  `.onKeyPress` does not raise one. Check `UIKitBackend+KeyEvents.swift` for
  `UIKeyInput` / `canBecomeFirstResponder` before changing anything.
  **UIKit:P72 的 mesh view 被長按時會叫出螢幕鍵盤。** 2026-09-27 每一張「選單已開啟」的擷圖都看得到
  (其中一次是模擬器一次性的「Speed up your typing」面板)。推測、**未查證**:那個 view 為了 `.onKeyPress`
  取得 first responder,而 UIKit 會為一個接受文字輸入的 first responder 顯示鍵盤。SwiftUI 的 `.onKeyPress`
  不會叫出鍵盤。動手之前先看 `UIKitBackend+KeyEvents.swift` 裡的 `UIKeyInput` / `canBecomeFirstResponder`。

### 2026-09-12 Windows / WSL handover

- [x] **CLOSED 2026-09-29 -- TalkBack's actual speech verified, no human listening.**
  `testapp/test_support/android_log_tts` is a TTS engine that logs every utterance
  (tag SCUI-TTS) and speaks none; as the default engine it receives everything
  TalkBack says. P69 on the api36 emulator, each element touch-explored through the
  real touchscreen device (`adb input tap` bypasses the accessibility filter):
  Close -> "Close, Button" (no "X"); Delete -> "Delete, Button. Removes the file
  permanently"; Volume -> "40 percent, Volume, Button"; the 12:30 text -> "Half past
  twelve" (12:30 not spoken, so the contentDescription override is what a reader
  uses -- the one thing this item had not heard); decorative -> nothing.
  Transcript: `testapp/measurements/talkback-p69-20260929.txt`. What remains is
  Narrator, on the Windows machine, tracked in the item above.
  **2026-09-29 關閉:TalkBack 的實際朗讀已驗證,不需要有人聽。**記錄每段朗讀的 TTS 引擎 + 真正的觸控事件;五項主張全部
  以「唸出的內容」成立。剩下的 Narrator 在 Windows 主機上,由上面那一項追蹤。原條目:
  **#123 複驗(2026-09-17,應 Windows 之請):AppKit / UIKit / Android 三個 backend 乾淨,但複驗本身找到一個更大的洞**
  - **起因**:那邊的外部 AT-SPI 探針發現 GTK 的 Close 按鈕仍把 `X` 子節點暴露出去。
  - **macOS:沒有這個問題,而且現在證得出來。** `ax_dump` 加了 `--children`,會印出每一顆具名按鈕
    **底下**有什麼:`desc='Close'`(無子節點)、`desc='Delete' help='Removes the file permanently'`
    (無子節點)、`desc='Volume' value='40 percent'`(無子節點),整棵樹裡沒有 `X`、也沒有
    `decorative`。原本那份扁平清單**不可能**顯示出子節點——同一個量測,現在被問了一個它先前答不出的問題。
  - **Android:未壓縮的 dump 確實看得到 `Button desc='Close' → … → TextView text='X'`,以及
    `decorative`。那不是缺陷**,而且原始碼早就寫著:`uiautomator` 的普通 dump 會設
    `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS`,列出螢幕閱讀器永遠抵達不了的 view。`--compressed`
    ——也就是與輔助技術所走訪者相符的那一份——給的是 `Button desc='Close'` **0 個子節點**、
    `decorative` 完全不存在。兩份 dump 同一次執行取得,因此差別在旗標,不在建置。
  - **iOS:在今天之前根本沒有外部探針,而一裝上就抓到東西。** XCUITest 的 runner 現在支援
    `--dump-tree`(`test_ios.zsh`),印出的是輔助技術所走訪的同一棵樹。第一份輸出:**整支 app 只解析出
    一個 `StaticText`,而它屬於測試載具自己的 `actualView` 按鈕**;SwiftCrossUI 畫出的每一段文字都是
    沒有名字的 `Other`——**VoiceOver 對這個 backend 上任何 app 的任何文字都無話可說**。原因是
    `UIKitBackend.TextView` 以 TextKit 自行繪製,因此是普通 `UIView`、不是無障礙元素。已修:設定文字時
    一併發布 `isAccessibilityElement`/`accessibilityLabel` 並加上 `.staticText` trait,並讓
    `namedChild` 認得 `TextView`。修後:七個 `StaticText` 各自帶著自己的內容,
    Close/Delete/Volume 仍帶著名字且**沒有** `X` 子節點,`decorative` 不出現。
  - **給 Windows 端的一條線索(GTK)**:AT-SPI **沒有** Android 那種「不重要」過濾,所以那棵樹就是 AT 走訪的樹
    ——`X` 若在裡面就是真的在裡面。GTK4 可以把內層 label 的 accessible role 設為 `NONE`/presentation,
    或對它 `gtk_accessible_update_state(... GTK_ACCESSIBLE_STATE_HIDDEN, TRUE ...)`。Mac 主機上沒有 GTK 的 AT-SPI 環境,
    無法驗,所以這是線索不是結論。
  - **`.accessibilityLabel` 對 `Text` 的等價檢查已完成(2026-09-19,AppKit 與 Android)**,而它找到的
    不是實作缺陷、是 **P69 自己的主張寫錯了**:
    - **AppKit**:`AXStaticText 'Half past twelve' desc='Half past twelve'`,整棵樹裡沒有 `12:30`。
    - **Android**(`uiautomator --compressed`):**同一個** TextView 同時帶著 `text='12:30'` 與
      `content-desc='Half past twelve'`。
    - P69 原本的主張寫著「出現 'Half past twelve' 而**不出現** '12:30'」——那是 macOS/iOS 的形狀,
      被當成普世規則寫下。在 Android 上 `contentDescription` 是一個「閱讀器**改讀它**、而不是讀 text」
      的**覆寫**,不是替換;`12:30` 留在節點上是正確的。那段主張會把 Android 的 dump 讀成失敗,
      而當時標籤正在正確地做它的事——**最糟的一種錯誤斷言:它指著能用的程式碼。** 已改為逐平台敘述。
    - **兩邊都確認 `decorative` 不出現**(Android 上唯一的那次出現,是在 P69 自己的主張字串裡)。
  - **仍未做**:Narrator / TalkBack 的**實際朗讀**(要有人聽);Android 上「閱讀器會改讀
    contentDescription」是平台的既定行為,但尚未實際聽過,因此與 Narrator 那一項同列。

## Archived 2026-10-18 from queue.md

### 2026-10-10 onContinuousHover (for SoftPCB's Cmd node probe)

- [x] **GTK drew P89's 14 x 14 stroked Circle as a rounded square** (fixed
  2026-10-10). GtkDrawingArea draws through a cairo node the size of the widget,
  so the half of a stroke that lies outside the shape's frame was cut off flat.
  The path widget now draws through its own snapshot with room for the stroke
  (`gtk_passthrough_drawing_area_set_overflowing_draw_func`). Seen on macOS with
  gtk4 4.24.1: P89's ring is round, P43's fills and gradient stroke unchanged.
  Not run on Linux/WSL or Windows GTK.

### 2026-10-09 SVG in Image (user request, priority one)

- [x] **Visible `<text>`: drawn by each platform's own text engine**
  (2026-10-09). Chosen over bundling a font, for size: no font
  file in the library, and every script the platform has fonts for draws,
  Chinese included; the price is that text differs a little between
  platforms. Core: `SVGBuilder` turns `<text>` into a text node (font-family,
  font-weight, font-style, font-size, text-anchor, fill, stroke, transform,
  whitespace collapsed); `rasterize(..., textMasker:)` asks for a coverage
  mask per run (`SVGTextMaskRequest`) and composites it with the SVG's colour,
  opacity and paint order. Backends: `BackendFeatures.SVGText` --
  AppKit/UIKit through `SVGCoreTextMasker` (Core Text), Android through
  `SVGTextMasker.kt` (Canvas, ALPHA_8), GTK through PangoCairo (A8; no
  font-family means sans-serif, as on the others). Without a text renderer
  the run stays outlined in magenta and listed as `textNeedsRenderer`.
  Checked: SVGTextTests (7, with a fake masker and real Core Text incl.
  "電"), all 34 SVG tests; P85 (new, nine numbered checks incl. Chinese,
  rotation, 40% opacity and a box painted over text) passes on macOS,
  GTK on macOS, the iOS simulator and the Android emulator.
- [x] **Gradients: `linearGradient` and `radialGradient`** (2026-10-10), in
  the core rasteriser, so every backend has them: objectBoundingBox and
  userSpaceOnUse, `gradientTransform`, spreadMethod pad/reflect/repeat, the
  SVG 2 focal circle (`fx`, `fy`, `fr`), stop-color/stop-opacity from
  attributes or `style`, `href` inheritance (16 links at most), stops
  interpolated premultiplied; on shapes, strokes and text (through the text
  mask). No stops paints nothing, one stop paints solid. Only a broken
  reference falls back to the paint's fallback colour and stays reported.
  Checked: SVGPaintTests (10), all 44 SVG tests.
- [x] **`clip-path` and `mask`** (2026-10-10), in the core rasteriser: the
  element's nodes go into a layer, multiplied by the clip's coverage and
  the mask's value, then composited at the element's opacity. clipPath:
  shapes, text (through the text mask) and use; geometry only, filled with
  `clip-rule`; clipPathUnits both ways; a clip-path on the clipPath
  intersects. mask: luminance (sRGB coefficients) or `mask-type: alpha`;
  the region (x/y/width/height, -10%/120% default) in either maskUnits;
  maskContentUnits both ways. Broken or circular references draw
  unclipped/unmasked, reported and outlined. Checked: SVGEffectsTests (13),
  all 57 SVG tests, the full suite (161 + 14).
- [x] **`<pattern>` paint** (2026-10-10), in the core rasteriser: the tile
  content is built in tile space per shape; at draw time the tile is
  rendered at device resolution (at most 4 million pixels) and sampled
  with wrap-around. patternUnits and patternContentUnits both ways,
  viewBox + preserveAspectRatio, patternTransform, href inheritance of
  attributes and content; fills, strokes and text. A zero-sized tile or
  empty content paints nothing; a pattern painting with itself is
  reported. Checked: SVGPatternTests (9), all 66 SVG tests.
- [x] **Markers: `marker-start`, `marker-mid`, `marker-end`** (2026-10-10),
  on path, line, polyline and polygon, drawn after fill and stroke inside
  the shape's opacity, clip and mask. Vertices with directions in and out
  (curves by their end tangents, closed subpaths joined); orient auto,
  auto-start-reverse and angles; markerUnits strokeWidth and
  userSpaceOnUse; markerWidth/Height, viewBox, refX/refY; overflow hidden
  (the default) clips to the marker viewport. Checked: SVGMarkerTests (9),
  all 75 SVG tests.
- [x] **`<image>` with a `data:` URI** (2026-10-10): PNG, JPEG and the
  other formats ImageFormats decodes, base64 or percent-encoded. The
  picture is a paint and the element a rectangle filled with it, so edges
  are antialiased; preserveAspectRatio (meet, slice cut to the viewport,
  none), width/height auto from the picture, bilinear sampling, opacity.
  A file reference (`href="photo.png"`) is still reported and outlined: a
  document parsed from a string has nowhere to resolve it. Checked:
  SVGImageTests (8), all 83 SVG tests.
- [x] **`<image>` of a file, and of an SVG** (2026-10-10). A document read
  from a file (`SVGDocument(contentsOf:)`, `baseURL:`, and `Image` for a
  file URL) reads pictures from its own folder or below; absolute paths,
  `../` escapes and network addresses are refused and reported, and a
  document from a string still reads none. A picture that is an SVG (file
  or `data:image/svg+xml`) is placed as vectors -- its nodes moved and
  scaled into the viewport and clipped to it, text still through the text
  engine -- and what it cannot draw is reported against the `<image>`
  ("in inner.svg: ..."). Nesting stops at 8 and at a cycle (the document
  itself included). Checked: SVGImageFileTests (7), all 104 SVG tests, the
  full suite (208 + 14), `compile.zsh -android P87`.
- [x] **Filters, the common subset** (2026-10-10), run on the element's
  layer in device pixels before its clip, mask and opacity:
  feGaussianBlur (three box blurs from 2 px, an exact kernel below),
  feOffset, feDropShadow, feFlood, feColorMatrix (matrix, saturate,
  hueRotate, luminanceToAlpha), feComposite (all operators incl.
  arithmetic), feMerge, feBlend (normal, multiply, screen, darken,
  lighten), feComponentTransfer; in/in2/result, SourceGraphic and
  SourceAlpha; filter region and primitive subregions in either unit;
  color-interpolation-filters, linearRGB by default. A filter with any
  other primitive or input is not applied at all and stays reported and
  outlined. A rotated or skewed element is filtered along its own axes
  (drawn in filter space and resampled back, SVGFilterTests.rotatedBlur).
  Checked: SVGFilterTests (14), all 97 SVG tests, the full
  suite (200 + 14); P87 (new, nine cells, 0 diagnostics) on macOS.
- [x] **The rest of the SVG 1.1 filter primitives** (2026-10-10): feMorphology,
  feConvolveMatrix (kernel turned 180 degrees, edgeMode, preserveAlpha), feTile
  (the input's subregion), feDisplacementMap, feTurbulence (SVG 1.1 reference code,
  stitchTiles), feDiffuseLighting and feSpecularLighting (distant, point and spot
  lights, SVG's Sobel normals with edge forms), feImage (an element by #id, or a
  picture placed in the subregion). BackgroundImage, BackgroundAlpha, FillPaint and
  StrokePaint read as transparent, as browsers draw them. Written and tested in a
  separate worktree first, so the shared tree never held a half-applied change.
  Checked: SVGFilterMoreTests (10; diffuse at 30 degrees gives 128, N.L = 0.5), all
  114 SVG tests, the full suite (218 + 14), `compile.zsh -android P87`. Not checked
  against a browser: feTurbulence's values follow the reference code, but no
  rendering of the same SVG was compared pixel for pixel.

### On the Mac host

- [x] **Android: `BackendFeatures.IncomingURLs` is not implemented.** It is part
  of `FullAppBackend`; GTK, WinUI, AppKit and UIKit have it, Android does not
  declare it, and `AndroidBackend.swift:609` still carries upstream's commented
  "Handle incoming URLs". An app opened by a link on Android never hears about it.
  DONE 2026-10-06 (AndroidBackend+IncomingURLs.swift): the launch intent's data
  is read when the handler is set, `onNewIntent` through an ActivityListener
  installed for it; early URLs queue and replay. The manifest gains one VIEW
  filter per `url_schemes` entry in Bundler.android.toml (`scui-testapp`) and
  `launchMode="singleTop"`, so a link to the app in front is `onNewIntent`
  rather than a second activity. P78 (new): cold start with
  scui-testapp://launch, then scui-testapp://running while in front ->
  "received 2" in order on the emulator.
- [x] **WinUI: compile and run the file-dialog filters.** DONE 2026-10-07,
  after replacing the WinRT pickers with the Win32 shell dialogs
  (`IFileOpenDialog` / `IFileSaveDialog`, `WinUIBackend+FileDialogs.swift`):
  WinRT could start only at a `PickerLocationId`, so `initialDirectory` was
  lost (P62 landed in Documents, P75 in OneDrive Documents). P62 "open…"
  starts in `%TEMP%\p62-open`, offers "Plain text", lists readable.txt only,
  and opening it brings up window 2 titled readable.txt
  (`p62w-open-filter-20261007-033800.png`). The "." question is moot: with no
  types the save dialog offers "All files" (`*.*`) and P75 saved
  p75-saved.txt under that exact name. P18: open, folder (`Select`), save
  destination and Cancel all reach the app (`p18w-*-20261007-03*.png`).
  Difference from macOS/iOS: `ContentType` is extension-only, so Windows also
  hides also-text.swift, which UTType conformance keeps selectable there.
  **FIXED later the same day:** `ContentType.conformingFileExtensions` holds
  the 95 extensions macOS 27.2 maps to types conforming to public.plain-text
  (measured with `UTType(filenameExtension:)?.conforms(to: .plainText)`);
  WinUI and GTK add them to the open filter only. P62 on WinUI and on GTK on
  Windows (which also shows the shell dialog) lists also-text.swift beside
  readable.txt, still hides not-text.png, and opens it as window 2
  (p62w-/p62g-open-conforming-20261007-07*.png). Not run: GTK on WSL (GIO
  types by MIME there; the suffixes are added as well). Android: see below.
  完成 2026-10-07：以 Win32 shell 對話框取代 WinRT picker（WinRT 只能從
  `PickerLocationId` 開始，`initialDirectory` 因此遺失）。P62 開檔從 `%TEMP%\p62-open`
  開始、只列 readable.txt、開啟後出現 readable.txt 視窗；無類型時存檔提供「All files」；
  P18 開檔、資料夾、存檔、取消皆回到 app。與 macOS/iOS 的差異：`ContentType` 只有副檔名，
  所以 Windows 也隱藏 also-text.swift。**同日稍後已修：**`ContentType.conformingFileExtensions`
  (macOS 27.2 上 95 個屬於 public.plain-text 的副檔名),WinUI 與 Windows 上的 GTK 現在都會列出並開啟 also-text.swift。
- [x] **WinUI: the save dialog ignores `defaultFileName`** -- FIXED 2026-10-07
  by the same change (`SetFileName`): P18's save dialog shows "p18-example",
  P62's "Untitled". 同一變更修正（`SetFileName`）：P18 顯示 p18-example、P62 顯示 Untitled。
- [x] **Android: plain-text open hides source files such as also-text.swift.**
  Unverified on a device, reasoned from the API: the picker filters by the
  MIME type the storage provider reports, and an extension Android's
  `MimeTypeMap` does not know (`swift`) is reported as
  `application/octet-stream`, so `text/plain` cannot reach it and
  `conformingFileExtensions` has no MIME to add. Run P62 "open…" on the
  emulator first; if hidden, find the way Android does express it (e.g.
  mapping the extensions it does know through `MimeTypeMap`).
  Android 依 provider 回報的 MIME 過濾，`swift` 會被報成 octet-stream;先在模擬器上跑 P62 確認。
  DONE 2026-10-07. Confirmed first, on the API 36 emulator with ACTION_OPEN_DOCUMENT
  and the three files in /sdcard/Download/p62-open (uiautomator `enabled`):
  `text/plain` -> readable.txt yes, also-text.swift NO, not-text.png no; `*/*` -> all
  three yes; `text/plain` + `application/octet-stream` -> txt yes, swift yes, png no.
  Fixed in FilesActivityContract.kt: the open dialog now gets every allowed
  extension (`fileExtensions` + `conformingFileExtensions`), maps each through
  `MimeTypeMap`, and adds octet-stream when one has no MIME type; what comes back is
  then checked by display name, so an unknown binary is refused with a warning
  instead of opened as text. P62 "open…" after the change: txt yes, swift yes, png
  no, data.bin offered (octet-stream) and refused on choosing it ("open dialog:
  data.bin is not one of [txt, text, swift, ...]").
- [x] **Android: a document chosen in the open dialog cannot be read.** Found
  2026-10-07 while checking the item above: choosing also-text.swift in P62 logs
  "could not open document" with NSURLErrorDomain -1002 "unsupported URL" for
  `content://com.android.externalstorage.documents/...`, because
  `DocumentGroup.swift:207` reads it with `Data(contentsOf:)`, which Foundation on
  Android cannot do for content:// URIs. Every file opened this way should fail
  the same way (reasoned; only the .swift file was tried). The save side already
  avoids handing content:// back (AndroidBackend+SystemHandoffs.swift); the open
  side needs a decision: copy into the app's cache and return a file URL, or read
  through ContentResolver -- and how a later save reaches the original.
  DONE 2026-10-07 (user: "fix Content issue"), the copy: the open dialog's
  content:// URIs become files in the cache (`stagingPathForOpen`: each in its own
  `open-<ns>` folder under its display name, read through ContentResolver,
  persistable read+write grant taken when offered), and the save mirror that
  `stagingPathForSave` already used is now `mirrorBack`, shared by both, so a save
  over the opened file is written back with "wt". Checked on the API 36 emulator
  with P62: before, /sdcard/Download/p62-open/also-text.swift held
  "P62 also-text.swift"; "open…" -> also-text.swift opened and showed that text;
  "type A" then "save" showed "...\nA", and the original on the device then read
  "P62 also-text.swift\nA". Regression, P75 save-and-read-back: the new
  "p75-saved.txt (1)" holds "saved by P75". Not checked: a provider that grants
  read only (its saves would log "could not copy the save" and stay local).
  FOLLOW-UP 2026-10-07: that silent case is closed. `stagingPathForOpen` probes
  the document with `openFileDescriptor(uri, "wa")` (nothing written); if it
  cannot be opened for writing, the copy and its folder are made read-only and
  no mirror is started, so the save fails in Swift (`saveDocument` returns
  false and logs) rather than "succeeding" locally. Not COLUMN_FLAGS: a text
  file in Documents > Download (MediaDocumentsProvider) reported flags=4, no
  FLAG_SUPPORTS_WRITE, and the "wt" write-back to it succeeded anyway -- a
  flag-based check, tried first, made that file read-only (Swift: Code=513
  "Permission denied", original untouched). With the probe, P62 on the API 36
  emulator: that media document "type A" + "save" wrote back "revealed by
  P75\nA"; also-text.swift in Download wrote back "...ABA". Not found on the
  emulator: a provider that actually refuses "wa", so the read-only branch is
  proven only from the save side (the 513 above), not from the probe failing.
- [x] **`Picker.inspect` is commented out on all five backends**
  ("Repair Picker.inspect implementations post PickerStyle refactor" in each
  `InspectionModifiers.swift`; Android has none at all). Every other control
  has its `.inspect`. DONE 2026-10-06 on four of five: `.inspect { picker in }`
  hands over the `.menu` control (NSPopUpButton / UIButton / Gtk.DropDown /
  WinUI.ComboBox / Spinner), `.inspect(as: T.self) { }` any other. Found on the
  way: a typed `.inspect` at `.onCreate` trapped whenever the control sits in a
  container (the example's Slider) -- descendants are not in
  the container until the first update -- so the search now also walks the view
  graph (`InspectView.init(child:inspectionPoints:searching:)`), all five
  backends. AdvancedCustomizationExample runs on AppKit and on Gtk-on-macOS with
  its Picker block restored; P4 runs on iOS and Android.
  - [x] **WinUI: compile and run AdvancedCustomizationExample** -- the WinUI
    half was written here and has not been compiled. Windows machine.
    **Done 2026-10-07 on Windows:** `swift build --product AdvancedCustomizationExample`
    in Examples/ built with 0 errors (first build 1117 s). Run: the magenta custom
    native button, the red `+` with a 10-point top-left corner, and the red picker
    all show (`ace-winui-20261007-030552.png`); through UIA, + + - read
    `Count: 1`. Not checked by eye: the slider thumb tooltip, the selectable count
    text and the green text-field selection highlight.
    **2026-10-07 已在 Windows 完成:** 編譯 0 error;洋紅按鈕、左上圓角 10 的紅色 `+`、紅色選單都正確顯示,
    經 UIA 按 + + - 讀到 `Count: 1`。滑桿提示、可選取文字與綠色選取色未以肉眼確認。
  - [x] **Gtk (macOS): the example's red `+` button stays grey** -- its
    `.inspect(.afterUpdate)` sets `css backgroundColor`, and nothing trapped, so
    the closure ran; whether the CSS is overridden by the theme is not known.
    FIXED 2026-10-06: not the theme. The button's own rules and the app's
    `css` share one CssProvider and each `loadCss` replaced the other, so the
    next `updateButton` erased the red. `Widget.reloadCSS()` is open now and
    GtkCustomButton writes both, the app's under a more specific selector.
    The example's `+` is red on Gtk-on-macOS.
- [x] **UIKit: `preferredColorScheme` on the window -- verify.** `updateWindow`
  (`UIKitBackend+Window.swift:283`) only paints the background from
  `colorScheme` and carries "TODO: Support preferredColorScheme"; views set
  `overrideUserInterfaceStyle` one by one (Symbols, Passive), system controls in
  between may not follow. P15 on iOS is the check. DONE 2026-10-06: they did
  not follow -- P15-DARK (now with a TextField and a Toggle) on a light
  simulator showed an unreadable placeholder and light-style controls on the
  dark background. The window now carries `overrideUserInterfaceStyle` while
  the scheme differs from the system's, and the system's is read from the window
  scene (the override would otherwise read back as the system's). Captures
  p15-dark-ios-final-20261006-130110 (after) / -130141 (before). Not yet
  exercised: removing the preference at runtime.
- [x] **Android TODOs to verify, each a possible gap:** navigation titles
  (`AndroidBackend.swift:460`), orientation and configuration changes (`:580`),
  live system light/dark changes (`:804`), per-window environment changes
  (`:822`), more than one `createWindow` (`:430`), sheet background and detents
  (`AndroidBackend+Sheets.swift:51`), `dismantleAndroidView`
  (`AndroidViewRepresentable.swift:53`). UIKit: sheet detents before iOS 16
  (`UIKitBackend+Sheet.swift:171`).
  CHECKED 2026-10-06, six of seven were real gaps and are fixed:
  - navigation titles were already a row (Toolbar); the empty one was the
    WINDOW title -- now the activity title and the Recents label (P78:
    `dumpsys activity recents` shows label="P78 incoming URLs").
  - rotation, light/dark, density, font scale RESTARTED THE APP: no
    `configChanges`, so the activity was recreated and `setup()` ran the Swift
    app again in the same process (P78: received 2 -> rotate -> received 0,
    same PID). The manifest declares them now and onConfigurationChanged feeds
    the resize, root- and window-environment handlers (all three were empty
    TODOs). P78 after: rotate and night mode keep "received 2", same PID, the
    layout goes landscape and the background dark.
  - sheet detents, corner radius, drag indicator: implemented in CustomSheet.kt
    (BottomSheetBehavior peek / half-expanded / expanded, MaterialShapeDrawable,
    BottomSheetDragHandleView); the frame is as tall as the largest detent, which
    was the "background" problem. P49 gains a detent sheet: half height, round
    corners, handle, drags to full; P1's green background and the plain sheet
    unchanged.
  - `dismantleAndroidView` added, run when the node is released (as UIKit). P79
    (new): show, hide, show, hide -> made 2, dismantled 2.
  - UIKit before iOS 16: `.fraction`/`.height` map to the nearer of medium/large
    on iOS 15 instead of always medium. Built, not run (only an iOS 27 runtime
    here).
  - [x] **Android: more than one `createWindow`** (`AndroidBackend.swift:430`).
    One activity, so a second window replaces the first; `supportsMultipleWindows`
    is false, as on iPhone. On tablets Android can run several activities
    (multi-instance); doing it means one activity per window and an
    `AndroidBackend.activity` that is no longer a singleton. DONE 2026-10-06:
    every window after the first is a `ScuiWindowActivity` (Kotlin), started
    with NEW_DOCUMENT|MULTIPLE_TASK|LAUNCH_ADJACENT; its content is built in
    Swift and handed over by token. Per-window title, background, insets, size,
    toolbar stack, resize and environment handlers (the static single handlers
    were the last window's, so a second window took the first's away);
    close by finish/back runs the close handler. `supportsMultipleWindows` is
    true. P59 on the emulator: "open second window" put B beside A in split
    screen, both relaid to their halves; append B in B -> scene draft B only in
    B (A keeps A), app draft AB in both; Back closed B and A went full screen;
    reopening B restored its scene draft. P1 (one window, sheets) unchanged.
    - [x] **Android: presentations from a later window** -- sheets, alerts,
      popovers, file dialogs and the synthesiser still use the first activity
      (`AndroidBackend.activity`), so they appear over window A. Views in a
      later window are created with the first activity's context.
      FIXED 2026-10-07: sheets and alerts use the window's own activity's
      FragmentManager (`presentingActivity(for:)`); open, folder and save
      dialogs from a later window register a one-shot launcher on that
      activity's ActivityResultRegistry, so DocumentsUI opens in its task.
      Popovers already followed the anchor's window. P81 (new) on the
      emulator, split screen: sheet, alert, popover and the open dialog from
      window B all appeared over B naming B, the picked file came back to B;
      window A's sheet still over A. Save dialog from B not driven (same path
      as open). Views of a later window are still built with the first
      activity's context; nothing seen to depend on it.
  - [-] **UIKit: sheet detents on iOS 13-14** need a custom
    UIPresentationController (no sheetPresentationController there). Not started.
    CANCELLED 2026-10-06 ("no need"): no iOS 13/14 simulator runtime installed to
    test it on.
- [-] **The csv2 rule (CLAUDE.md) in the tools that still use Python's csv:**
  `testapp/test_support/ios_aim_check.py`, `Scripts/fill_matrix_from_sweep.py`,
  `Scripts/check_action_files.sh`, `Scripts/check_action_file_fields.sh`,
  `Scripts/check_mistakes_numbering.sh`, `Scripts/check_results_columns.sh`.
  CLOSED, no change, 2026-10-06. The global rule is csv2 *or Python's csv
  module*; what it forbids is splitting on commas, and none of these does. Three
  read action files, whose `#` comment lines csv2 refuses by design
  ("record 1 (line 2) starts with '#'. csv2 has no comment syntax", measured)
  -- moving them would mean stripping lines and losing the line numbers their
  reports cite. The only writer, fill_matrix_from_sweep.py, already passes
  `lineterminator="\n"`, so the CRLF that the sweep writers produced does not
  happen here. The four check_*.sh run from Scripts/test.sh on every machine,
  including ones without csv2.
- [x] **macOS sweep leaves the UI lock held after a failed run** (2026-10-07).
  `sweep_drive_macos.zsh P77..P81` recorded P78-P81 "never launched" three
  times; each time `ui-lock.zsh status` showed the lock held by the last app
  that failed (test-p81, test-p79) with no such process alive, and every later
  app waited on it until the 900 s timeout. Run alone with test.zsh, each of
  those apps launched in seconds, and a sweep of P81 alone recorded ok. So a
  test.zsh that dies (or is killed by the sweep's `timeout 900`) does not
  release the UI lock, and one failure cascades into the rest of the sweep.
  The bogus rows were removed before commit; the stale locks were released
  with `ui-lock.zsh release`. Fix: release the lock on every exit path of
  test.zsh (trap, as platform_lock.zsh does), and find why the first app in
  the cascade failed.
  **Done (2026-10-07):** the cause was zsh, not a kill. Under `set -e` the EXIT
  trap does not run when errexit fires inside a function (zsh 5.9:
  `f() { false; }; f` exits 1 with no trap), and run_macos is a function, so
  any failing step before "Launching" left the lock held. test_common.zsh now
  also traps ZERR (only while errexit is on, so capture()'s `noerrexit` does
  not free it) and never releases from a `$(...)` subshell. Proved with a log
  path made a directory: before, `ui lock: held by test-p80` after the run;
  after, free, and a sweep of P80 P81 recorded P81 ok right behind the failed
  P80. The sweep note now carries test.zsh's last line. **Not found:** what
  made P78/P79/P81 fail on 2026-10-07 -- that output was discarded; the next
  occurrence will say.

### Windows side (GTK and WinUI)

- [x] **Five optional features declared by neither GTK nor WinUI:** `ContextMenus`,
  `Cursors`, `KeyEvents`, `ScrollGestures`, `WidgetSnapshots` (AppKit, UIKit and
  Android have all five). `Mesh3DViews` is the sixth, already its own item above.
  GTK DONE 2026-10-06 (GtkBackend+InputTargets.swift, a `Fixed` per target, and a
  hand-written Gtk.EventControllerScroll). Driven on GtkBackend on macOS with P80
  (new) and synthetic events: keys ("a" down/up, Escape), wheel scroll
  (translation 0,16 per notch, one gesture per notch), long press opens the
  menu every time (a kept popover opened once only -- now one per showing),
  snapshot of a red label 56x36 with 1856 of 2016 pixels red. NOT verified:
  choosing a menu item (on GTK-macOS synthetic clicks into a popover do not
  activate it -- the existing `Menu` would not even open that way), right-click
  delivery from CGEvent, cursor shapes (seen only by a person). The snapshot is
  in logical pixels, AppKit's in backing pixels. WinUI's five remain.
  WinUI DONE 2026-10-07 (WinUIBackend+InputTargets.swift, a transparent Canvas
  per target as the tap and hover targets use). Driven on P80 with real
  SendInput (UIA only to locate elements):
  - cursors: `ProtectedCursor` with `InputSystemCursor`, set on the target's
    whole subtree -- hand, cross, ibeam, sizeWE, sizeNS and no read back with
    `GetCursorInfo`. Whether the target alone suffices is NOT settled (the
    target-only run was blocked, see below).
  - context menu: `ContextFlyout` = a `MenuFlyout`; right-click opens First /
    Second at the pointer, invoking Second reads "menu picked: Second".
  - keys: A, Shift+A (modifier events too), Escape, and a KEYEVENTF_UNICODE "z"
    (VK_PACKET, reported from CharacterReceived) -- 10 events. Fixed on the
    way: focus is taken on the NEXT main-queue turn, because the root
    ScrollViewer focuses itself after the target's PointerPressed and won.
  - scroll: three wheel notches -> "scroll: 0, 16 ended: 3", as GTK.
  - snapshot: `RenderTargetBitmap`, pumping messages until the async ops
    finish (2 s limit). A red `Text("SNAP").padding(8).background(.red)`:
    49x32, 1421 of 1568 pixels red, 64 ms. Checked with a temporary P80 edit,
    reverted, not committed.
  Most of the afternoon was lost to injected input being silently dropped:
  first a leftover P75 window in front, then two ASUS utilities running
  elevated (AsMonitorControl.exe, then AsHotplugCtrl.exe). test.zsh now stops
  known blockers before a Windows test (user's instruction), and
  enable_input.zsh no longer skips them while a remote session is connected.
  WinUI 於 2026-10-07 完成五項(InputTargets.swift),P80 以真實 SendInput 驅動：游標六種、右鍵選單、按鍵(含
  VK_PACKET)、捲動、截圖(1421/1568 紅)皆正確。只設 target 是否足以顯示游標尚未確定。下午大半時間耗在輸入被無聲丟棄：
  先是殘留的 P75,後是兩支提權的華碩工具;test.zsh 現在會在 Windows 測試前停掉已知阻擋者。
- [x] **Picker styles:** GTK lacks `.wheel` (`supportedPickerStyles`,
  `GtkBackend.swift:233`); WinUI lacks `.segmented` and `.wheel`
  (`WinUIBackend.swift:209`). An app asking for them is downgraded -- the path
  CLAUDE.md rules out on shipped backends. AppKit, UIKit and Android have all four.
  GTK DONE 2026-10-06 (GtkBackend/WheelPicker.swift: a five-row ListBox in a
  ScrolledWindow, the shape AppKit uses; it was a `fatalError` before). P74
  built against GtkBackend on macOS: the wheel shows Mon..Fri, a click on Wed
  reads "wheel -> Wed". WinUI DONE 2026-10-07 (WinUIBackend+PickerStyles.swift):
  `.segmented` is a row of mutually exclusive ToggleButtons (WinUI 3 has no
  segmented control); `.wheel` a five-row ListView like AppKit and GTK, measured
  with its height held because `naturalSize(of:)` clears width/height and the
  first build came out seven rows tall. P74 on WinUI, driven through UIA
  (Toggle / SelectionItem.Select): "segmented -> Two" with only Two pressed,
  pressing Two again keeps it; "wheel -> Wed", then Sun scrolls into view and
  reads "wheel -> Sun" (p74w-after/-edge-20261007-0754*.png).
  WinUI 於 2026-10-07 完成：`.segmented` 為一列互斥的 ToggleButton,`.wheel` 為五列高的 ListView;
  P74 經 UIA 驅動，兩者讀數皆正確，選 Sun 時會自動捲動到它。
- [x] **`Button(_:role: .destructive)` changes nothing on any backend** (found
  2026-10-07). The core passes the role to `updateButton` in the environment
  (`Button.swift:438`), and no backend reads it there: on GtkBackend (macOS)
  "button, destructive" drew like any other button. Only GTK's
  `updateSimpleButton` (the Menu trigger, which has no role) uses it. Needs a
  decision on what each platform shows -- red label as on iOS, or the
  platform's own destructive style -- before five implementations.
  Decided 2026-10-07: each platform's own style. Core: a new
  `destructiveButtonLabelColor(in:)` on ViewLabelButtons (default nil); Button
  hands it to the label when the role is destructive and the app named no
  colour. P82 is the test app.
  - AppKit DONE: `.system(.red)` plus `NSButton.hasDestructiveAction`; P82 red,
    disabled dimmed, 'blue set' blue.
  - UIKit DONE: `.system(.red)` (systemRed); P82 as on AppKit. Fixing it found
    `Button("x").foregroundColor(...)` ambiguous on UIKitBackend
    (KeyboardToolbar's ToolbarItem overload); now `@_disfavoredOverload`.
  - Android DONE: the theme's `colorError`; P82 on the emulator 2026-10-08:
    destructive labels orange-red, disabled dimmed, save/cancel ordinary, blue kept.
  - GTK (Windows host, 865d9b32): Adwaita `destructive-action`. On GtkBackend
    (macOS) bordered is red; borderless draws grey (the default borderless
    label colour overrides the inherited red) and disabled shows almost no red.
    **Fixed 2026-10-08:** the GTK hook returns, for borderless/plain only, the
    colour the theme gives a `.flat.destructive-action` button's text, read from
    an unshown probe button (bordered stays nil; the class paints it). P82 on
    Windows GTK (dark variant) and WSLg (light): bordered red with white text,
    borderless red, save/cancel unchanged. Disabled: Adwaita draws a disabled
    destructive bordered button as plain insensitive -- no red -- so the faint
    look is the native one. 'blue set' is red with blue text: the app's colour
    wins by design, left as is.
  - WinUI DONE 2026-10-08: the hook returns `SystemFillColorCriticalBrush` from
    the app's theme resources (WinUI has no destructive button style). P82:
    bordered and borderless in the critical red, disabled dimmed, 'blue set'
    blue, save/cancel unchanged. Hover/pressed driven later the same day (real
    SendInput on 'destructive, bordered'): the label stays (255,153,164) at rest,
    hovered, held down and released; only WinUI's own chrome changes (background
    45 -> 47 hovered, 39 held, 50 released). The click fires: the app shows
    'pressed: destructive, bordered'. Earlier this line read "Hover/pressed not
    driven (input blocked by an elevated ASUS window at the time)".

### 2026-10-05 M10 follow-up: what SoftPCB's tab 9 needs from Mesh3DView

- [x] **iOS builds without Swift Bundler by default.** `compile.zsh -ios` runs
  `xcodebuild -scheme <Pn>` and wraps the executable in
  `iosContainer/appTemplate.app` (name, identifier `dev.swiftcrossui.testapp.<Pn>`,
  ad-hoc signature); the bundler is the fallback when that fails. P76 built,
  installed directly with `simctl install`, and replayed through `test.zsh --ios`.
  **Full sweep 2026-10-05: all 101 iOS action files pass with no bundler on the
  machine** (92 on the first pass; the other 9 failed in 4 s because an up-to-date
  xcodebuild did not relink, so the freshness check rejected an old executable --
  compile.zsh now removes it first, and those 9 then passed). No Pn fell back.
- [x] **Android: the GLES path for the same options.** DONE 2026-10-05, built with
  the swift.org 6.4.0 toolchain and the 6.4.0 Android SDK, NDK r30, AVD
  `swift-cross-ui-api36b`.
  - B: 32-bit indices when the context is GLES 3 or has `OES_element_index_uint`
    (`IntBuffer`, `GL_UNSIGNED_INT`); otherwise `ShortBuffer` while every index fits,
    and a one-time warning past 65,535. The old `Int16.max` refusal is gone.
  - D: lines and points with `glDrawArrays`, `gl_PointSize` from a uniform; both
    unlit. `lit` and `depthTested` per mesh (`GL_ALWAYS` + depth mask off), the
    mask restored before `glClear`. Every mesh now gets a draw entry, so the
    matrices stay aligned with it.
  - Accepted: P76 shows all six claims on the emulator and on the iOS simulator;
    P77 (new: 1,002,001 vertices, 2,000,000 triangles, largest index 1,002,000)
    shows one gradient with no hole and no streak on Android, iOS and macOS.
- [x] **Render time in microseconds, off by default.** `Mesh3DScene.measuresRenderTime`
  and `Mesh3DFrameInfo.renderMicros` (nil when not measured): from the start of
  the frame until the GPU finishes it -- `waitUntilCompleted` on Metal, `glFinish`
  on GLES. P72, P76 and P77 have a button for it. Measured once each (not a
  benchmark): macOS P72 329, P76 4437, P77 12312 us; Android emulator P76 3929,
  P77 40144 us. Showing a reading redraws the view; the apps skip the frame that
  redraw produces, so the loop stops (CPU 0% against 10.6-13.7% without the guard).
- [x] **Skip the per-commit geometry comparison.** Not needed, measured
  2026-10-05: `Array ==` returns at once when both arrays share storage (0.003 ms
  for 2,000,000 vertices, against 2.2 ms for equal contents in another buffer,
  `-O`). A scene built from stored arrays is already O(1) per commit; a revision
  token would only add a way to draw stale geometry by forgetting to bump it.
  Documented on `Mesh3D` as "keep the arrays; do not rebuild them per update".

### 2026-10-01 open after the UIScene change (8272b7a2) -- in this order

- [x] **4. Why the iOS executable says `sdk 15.0`.** DONE 2026-10-01. The Swift
  driver's link job hands clang `--sysroot <SDK>`; clang reads an SDK's version
  only from `-isysroot` or $SDKROOT, so it fell back to the deployment target:
  the logged link line re-run with `-###` gave `-platform_version ios-simulator
  15.0.0 15.0.0`, and `15.0.0 27.0` with -isysroot. Not Homebrew's CC (an Apple
  clang build gave the same), not swift-bundler's metadata object, not any link
  flag (each removed in turn). Fixed at the source:
  `testapp/iosContainer/link-sdk.xcconfig` adds `-Xclang-linker -isysroot`
  through XCODE_XCCONFIG_FILE, and the link now writes sdk 27.0 itself. The
  `vtool` rewrite is gone; compile.zsh only CHECKS the field and stops the build
  if it is wrong (shown to fail on an sdk-15 copy).
- [x] **1. Re-aim every iOS action file.** DONE 2026-10-01. Apps now run at
  native size (440x956 points instead of a zoomed 428x926), so layouts moved.
  Swept all 84 files, read each capture against its file's assertion, re-aimed
  the misses (P2 P3 P13 P17 P21 ×2 P22 P23 ×5 P33 P43 P44 P45 ×2 P46 P74 P75
  save) and replayed every re-aimed file until its capture showed the
  assertion. Two tools came out of it: `testapp/test_support/ios_aim_check.py`
  checks each positioned row against the accessibility tree, and the iOS runner
  takes a `dumptree` row that prints the tree mid-file, for targets that only
  sit where they do after earlier rows (P17's More height was mis-aimed from a
  capture taken after the closing scroll). P75 deletes last run's saved file on
  launch so the save file is repeatable.
- [x] iOS: 16 files written 2026-10-01, measured from the native-size tree and
  each replayed and read. Two defects found and fixed on the way:
  DocumentGroup's binding never redrew its window (P62 read (empty) while
  its log said AA; macOS hid it because opening a second document redrew
  window 1), and a sheet whose content was wider than the window was laid
  out at that width and centred, cutting both ends of every line (P49).
- [x] Android: all 20 written 2026-10-01/02, measured from uiautomator dumps and
  replayed (sweep_android 19/19 launched; each capture read). On the way:
  the Android host SDK (Xcode 27 Foundation interfaces the snapshot toolchain
  cannot read) broke every Android build; test_android refused P15-DARK and
  P17-DOE, and a hyphen made an invalid application id; an app that crashed at
  launch still exited 0 and photographed the app behind it; P63 read global
  x=0 y=0 (pending LayoutParams, pixels); a default popover had no panel; a
  popover wider than the window ran off it (Android and iOS); taps aimed into a
  sheet or popover reached the activity behind (P60); main-queue work waited
  up to 50 ms for the tickler. All fixed.
- [x] **Re-aim the Android action files.** DONE 2026-10-02. Every file's taps
  checked against a uiautomator dump (`ios_aim_check.py` reads .xml now), 16
  re-aimed, and a full sweep -- 98/98 launched, no crash, every replay
  finished -- read capture by capture against each file's assertion. Fixed on
  the way: launch focus went to the first text field (keyboard over P2 P15
  P21 P36, and P21's buttons scrolled away on a relayout) -- ShortcutHostLayout
  now takes the default focus; P72's long-press menu had been unreachable since
  the scroll-gesture container took every touch -- it now takes a touch only
  past the slop and hands a still press to the long-click ancestor; the final
  capture now waits for the replay to finish; P75 reveal writes a fresh name
  when the old file belongs to an earlier install.
- [x] **Android per-frame update cost.** Re-measured 2026-10-04 on the new AVD
  after the reboot: P64 54-56 Hz (median gap 16.7 ms, max 117-150 ms), P66
  16-22 samples in 0.6 s (iOS 31). The earlier 37 Hz / 7 samples were the
  stuck emulator eating 7 cores. Findings, all measured, nothing changed yet:
  - Not the update pipeline: no merged or throttled updates during P66's
    animation; each SwiftCrossUI update takes 4-10 ms and runs every frame.
  - Main thread is busy ~20 ms per frame during the animation (P66's 8 ms
    sampler runs every 20-30 ms then, every 8 ms after), and values sometimes
    advance two frames at once -- dropped frames.
  - A ~100 ms main-thread stall at the animation's start (sampler t=76 ->
    178), the same shape as P64's 117-150 ms max gap; ART's JIT thread is
    6-10 % of the process then, so first-run JIT/class loading is the lead.
  - simpleperf: libart 28 %, libswiftCore 18 %. The top symbol was
    `art::mirror::Class::FindClassMethod` (8.9 %): swift-java's
    `javaMethodLookup` runs GetObjectClass + GetMethodID on EVERY call (from
    AndroidBackend.setSize -> setLayoutParams among others). A method-ID cache
    prototyped in the checkout removed it but cut main-thread CPU only ~5 %
    (2.38 s -> 2.26 s over 6 s) and did not move P66, so it was reverted; a
    swift-java fork is not justified by that alone.
  FIXED 2026-10-04 (second pass, counting calls rather than their cost):
  `AndroidBackend.size(of:whenDisplayedIn:)` built a new Java TextView and a
  full TextStyle for every text measurement (50.5 % of the main thread),
  `getTextStyle` rebuilt Typeface/classes every call (19.6 %), and 94-96 % of
  setPosition/setSize calls and ~half of setText calls changed nothing yet
  each requested an Android layout. Now: measurements and text styles are
  cached by key, unchanged positions/sizes/text are skipped. P66 16-22 ->
  24-28 samples (iOS 31); P64 54-56 -> 57-58 Hz, max gap 117-167 -> 67-100 ms.
  Full Android sweep 98/98, captures compared with the run before.
  PARITY 2026-10-04 (third pass): the remaining read-back checks were
  themselves JNI calls (updateTextView 27 %, setPosition 22 %), and
  swift-java's per-call method lookup was 29 %. The last value set on each
  widget is now kept on the Swift side (AndroidBackend+LastSet.swift), so an
  unchanged call costs a dictionary lookup. P66 29-31 samples (iOS 31), P64
  59.0-59.5 Hz with a 33-50 ms worst gap (iOS 58.9-59.8 Hz, 22-43 ms). Not
  done, and not needed at parity: a method-ID cache in swift-java (a fork).
  CLOSED 2026-10-05 with all three platforms measured the same way (full
  sweeps with SCUI_UPDATE_STATS=1, table in
  testapp/measurements/update-stats-20261005.md). Steady state is at parity:
  for the four apps with >= 50 updates, Android median / p95 vs iOS -- P52
  5.8/114 vs 9.5/52, P64 2.5/3.8 vs 3.6/5.1, P66 2.3/5.3 vs 1.0/1.9, P72
  7.4/10.0 vs 5.3/6.1 ms. The gap left is elsewhere, see the next item.
- [x] **Android: the first updates after launch.** Over 58 apps the Android
  median is 1.44x iOS (median of medians 17.0 vs 10.8 ms, p95 52.5 vs 29.2),
  and the difference sits in apps with few updates, i.e. the first ones after
  launch: P2 83 vs 11 ms for its one update, P4 69 vs 28, P7 max 140 vs 50.
  Likely first-run JIT, class loading and first View creation through JNI --
  unproven. Next: have UpdateTimings report the first update separately, then
  decide whether a warm-up or an ART baseline profile is worth it.
  DONE 2026-10-05, and the guess was wrong. The line now ends in
  `first_ms=` and `rest_median_ms=` (UpdateTimings.swift, its tests,
  csv2_rows.zsh and update_stats_table.zsh carry the two columns; files from
  before have them blank). Android, three runs each, first / rest median ms:
  P1 open-the-root-sheet 15.4 / 55.3, 19.5 / 102.6, 22.6 / 43.0; P2
  expand-the-picker-options 70.1 / 92.4, 161.1 / 96.0, 62.6 / 98.1; P12
  increment-the-counter 35.2 / 69.5, 36.5 / 68.7, 36.4 / 12.1. One run each
  of P0 13.0 / 13.3, P4 59.1 / 50.9, P7 32.3 / 9.0, P66 11.0 / 1.8. The
  slow updates are the later ones that open a sheet or a picker, not the
  first after launch, so a warm-up or baseline profile aimed at start-up is
  not supported; only P7 looks like a start-up cost. (iOS runs use different
  action files, so they are not compared per app.) See the next item.
- [x] **Android: updates that create views are slow** (found 2026-10-05,
  above). P1's sheet 43-103 ms and P2's picker 92-98 ms on Android. Next:
  time where those updates go -- widget creation through JNI, layout, or the
  Kotlin side -- before choosing a fix.
  - [x] **P2: a quarter of the update was swift-java class lookups** (2026-10-05).
    simpleperf on the emulator (cpu-clock plus --trace-offcpu, dwarf stacks,
    symbols from the unstripped libP2.so), aligned to the update by a temporary
    end-time marker from UpdateTimings (removed again): of P2's 103.9 ms picker
    update, 25.5 ms was `_withJNIClassFromCustomClassLoader` ->
    `JavaClassLoader.loadClass`, reached from `AndroidBackend.updateButton`
    building a new `SwiftAction` and `SwiftObject` for every button on every
    update, and from `JavaClass<CustomButton>()` reads of constants in
    `buttonPadding` and `kotlinRepresentation`. Also in the window: 28 ms with no
    sample at all (the vCPU not running; likely the emulator), 6 ms Kotlin button
    styling, 3.5 ms ART class loading on the main thread. Fixed in
    AndroidBackend+CustomButton.swift: the Java action is built once per button
    and calls a Swift box whose closure is swapped on each update; `set` is called
    only when style, enabled state or colour scheme change (`LastSet`); the
    constants are read once. P2's picker update, three runs each: 92.4 / 96.0 /
    98.1 ms before, 82.6 / 62.7 / 72.5 after. Checked: P12 clicked twice reads
    "counter: 2" (the swapped closure is the one that runs), P21 reads
    "Button -- clicks: 1" with the disabled one dimmed. Not checked: a button whose
    enabled state changes while the app runs.
  - [x] **P1: the sheet is not this.** 63.0 / 51.4 / 57.8 ms after the fix against
    55.3 / 102.6 / 43.0 before -- no clear change. Next: the same profile on P1.
    DONE 2026-10-05: P1's sheet is a cost paid once, the first time. The same
    profile on its 104.4 ms update: 35 ms on the main thread's CPU and one 57.9 ms
    stretch with no sample at all, inside `__swift_instantiateGenericMetadata` ->
    `swift_getGenericMetadata` (the same four libswiftCore frames on both sides of
    the gap; resolved with llvm-symbolizer against the 6.4.0 Android SDK's
    libswiftCore.so). Opening the sheet three times in one run (open, dismiss,
    open, dismiss, open) gave 82.3 then at most 17.7 ms, and 54.9 then at most
    21.3 ms: only the first open is slow. So it is the runtime building the sheet
    view type's generic metadata, plus the emulator not running the vCPU for part
    of it, not per-update work in AndroidBackend. Not pursued: warming that
    metadata at launch would move the cost, not remove it.
- [x] 3. FIXED 2026-10-04 (CustomRadioGroup dims disabled options to 0.4). P74 disabled radio group: labels stay full black on Android; iOS dims
  them.
- [x] 2. FIXED 2026-10-04 (TableContainer clips to its own frame). P23 table: a long cell wraps to many lines and spills over the text
  below; iOS truncates with an ellipsis. Remaining difference, part of 4:
  Android cells wrap to several lines (column = width / 4) so only ~2.5 of
  12 rows fit, where iOS keeps each row to one truncated line.
- [x] 4. NOT A DEFECT (measured 2026-10-04). Text in narrow places breaking
  per character on Android ("Sci enc e" P16, "Disa ble it" P29, "Re mo ve 3"
  P51, "u n k n o w n" P47, P23's multi-line cells):
  - P16: identical on iOS -- sidebar 106 pt on both, "Science" 2 lines and
    "Humanities" 3 lines there too; the iOS capture compared was cropped.
  - P51: content wider than any phone; iOS overlaps where Android wraps.
  - P47, P29: the emulator is 411 pt wide against iPhone's 440, Roboto runs
    ~4 % wider than SF (178 vs 171 pt), and Material buttons carry more
    padding. With `wm density 393` (440 pt wide) P29's button fits and P47
    becomes 3 lines (iOS 2).
  Not changed: a 440-pt AVD would invalidate every Android action file's
  coordinates, and 411 pt is a common Android width.
- [x] 5. NOT A DEFECT (measured 2026-10-04). P41 date pickers "clipped" on
  Android: the page is wider than the phone on BOTH -- iOS puts .graphical
  at x 525 and .wheel at x 499 in a 440-pt window and scrolls too; the two
  action files simply end at different scroll positions. Android's large
  calendar header is the Material picker's own look.
- [x] iOS, the other way: P57's 500-row List built 29,718 rows on iOS against
  403 on Android. FIXED 2026-10-04 (bca777db): setLazyRows reloaded the whole
  table on every update (343 reloads), and each reload released and rebuilt
  the visible rows; same-count updates now refresh visible rows in place.
  Now 1,913 / 8. A per-cell trace of that run shows 1,906 cellForRowAt calls,
  so each build is one row coming on screen. The rest of the gap to Android
  is the walk, not waste: on iOS the same `scroll 6` rows reach row 446 and
  back (~900), plus a 0..499 burst and 455 scattered rows (6, 33, 71, 119 ...)
  that look like XCUITest's accessibility snapshot making UITableView vend
  off-screen cells -- not yet proven.
- [x] Harness: P75-close-the-window's capture shows P17-DOE left behind by an
  earlier app; the sweep does not clear the task stack between apps.
  FIXED 2026-10-05: the sweep did force-stop and uninstall each app after its
  file, but as dev.swiftcrossui.testapp.${app:l} -- "p17-doe", while the
  package is "p17doe" (test_android.zsh drops the hyphen). am force-stop of a
  package that does not exist says nothing, so P17-DOE and P15-DARK were never
  stopped or removed. Same spelling fixed in verify_effect_android.zsh,
  verify_replay_android.zsh and test_rootscroll_android.zsh. Verified: sweep
  of P17-DOE then P75 -- close-the-window now ends on the home screen.
- [x] Android aim after the AVD change (2026-10-05). SoftPCB-mac found P72
  measured on the old api36/SwiftShader AVD, ~62 pt off on api36b. Every
  app with an Android file was launched and its uiautomator tree checked
  against every positioned row (test_support/ios_aim_check.py): 68 apps, 59
  HIT, 6 AFTER (screen changed first; covered by the sweep captures), 36
  MISS -- each read against its note: all land on their target, the MISS is
  the checker failing to match a note written as an action ("cycle 1: none
  -> top") or a target with no text (drop zone, effect tiles, web view).
  None re-aimed. P72 could not be dumped (it animates, uiautomator never
  idles); its files were re-measured by SoftPCB-mac the same day.
- [x] **Emulator GPU.** DONE 2026-10-04. AVD config pinned to
  hw.gpu.enabled=yes / hw.gpu.mode=host (was no / auto, which fell back to
  software GL under memory pressure). test_android.zsh and sweep_android.zsh
  boot with `-gpu host`; test_android reuses a running emulator, reads the
  renderer from SurfaceFlinger, and if it is SwiftShader/llvmpipe/lavapipe
  restarts that AVD on the host GPU by itself (no flag) and stops if it still
  cannot get one. Proven on an emulator booted with swiftshader_indirect:
  restarted, `Renderer: ... Apple M4 ... Metal`, P1 ran. Full Android sweep
  afterwards: 99 / 99 launched; finals against the previous sweep: 66
  identical, the rest differ only in content (clock, frame counters, files
  the earlier runs saved in Downloads/Recents). That previous sweep was
  already on the host GPU (P72 prints its renderer), so this shows pinning
  changed nothing; it is not a comparison against software rendering.
- [x] **Disk cleanup: testapp/cleanup.zsh** (2026-10-04). Report by default,
  --apply removes regenerable items: iOS simulators' unified logs (skips
  booted ones), DerivedData, clang module cache, Instruments cache, emulator
  crash db, helper processes left by a dead emulator. Opt-in: --erase-sims,
  --wipe-avd, --deep (SwiftPM/Gradle/Homebrew). First run: 11 -> 18 GB free.
  - [x] scui-wear AVD (1.4 GB, unregistered, untouched since 2026-09-05) and
    its android-34 wear image (4.1 GB): removed 2026-10-04 on
    request (image via sdkmanager --uninstall).
  - [x] test_ios.zsh left a new DerivedData/iOSActionFileRunner-<hash> per
    run (166 on 2026-10-04): `test-without-building` had no
    -derivedDataPath. Fixed; two runs after, zero new folders.
  - [x] Stale build trees removed 2026-10-04 (44 GB on /Volumes/Windows):
    testapp/.compile-work (retired, no suffix), the android31 debug trees
    under .compile-work-android (harness builds release), android28,
    Examples/.build. **Vendor/swift-bundler/.build was removed too and had
    to be rebuilt:** the root `swift-bundler` binary loads its
    ErrorKit_ErrorKit resource bundle from that .build by absolute path, so
    "not modified in 7 days" meant read-only use, not unused. Android P1 then
    died bundling with "unable to find bundle named ErrorKit_ErrorKit"; after
    `swift build -c debug --product swift-bundler` there, Android P1 and iOS
    P12 build and run. Never delete Vendor/swift-bundler/.build.
  - [x] `.swift-bundler-stamp` says the root binary was built from
    swift-bundler 4ad3f14f, the submodule is at 922ba2a7: the installer
    would rebuild it. Pre-existing drift, not changed here.
    CLOSED 2026-10-05, moot: nothing in the harness runs the root binary any
    more -- Android packages through package_android.zsh, and compile.zsh -ios
    no longer has a bundler fallback. CI builds its own from the Vendor commit
    (cache keyed by it), so it never used this binary. The untracked root
    swift-bundler and .swift-bundler-stamp were deleted the same day, at the
    user's request. Scripts/build-tool-install-android-on-Mac.sh (its
    CounterExample check) and Scripts/build-android-bundler.sh still build and
    copy them there, so running either brings them back.
  - [x] **Swift Bundler replaced for Android** (2026-10-05). One tracked Gradle
    project, testapp/androidContainer/gradleProject, built in place at
    .compile-work-android/gradleProject; testapp/package_android.zsh relinks
    compile.zsh's product as lib<Pn>.so from SwiftPM's own link command, strips
    .swift_ast, copies the needed .so files (llvm-readelf), builds libshim.so
    with the NDK's clang, and runs Gradle with the app as -P properties. The
    second Swift build in .build-bundler is gone (27 GB deleted). MainActivity
    is now dev.swiftcrossui.testapp.MainActivity in every app; the four
    scripts that launched `<pkg>/.MainActivity` were updated. Verified:
    bundler and new APKs of P1 hold the same 27 entries, and their manifests
    differ only in that class name; full Android sweep 99/99, finals against
    the bundler sweep of the same day 69 identical, the rest P72 (Mesh3D work
    landed between the runs), P38 (live web page), P57/P75 (counters, files).
    Gradle for a second app: 3-4 s, Kotlin UP-TO-DATE. A first version read
    the 111 MB build plan with yaml.safe_load, 17.5 s per app; now 0.04 s.
    Swift Bundler is still built by the installer for compile.zsh -ios's
    fallback; Android no longer needs it.
  - [x] **iOS: an xcodebuild failure is a defect to root-cause, not something
    for the Swift Bundler fallback to absorb** (2026-10-05). The
    fallback at compile.zsh ~1759 prints one stderr line and carries on, which
    is how P76/P77's "Redefinition of module '_SwiftSyntaxCShims'" at 05:24
    went unnoticed until read back later. Next time it happens: stop, find the
    cause, fix it. Then make the fallback fail loudly (or count it in the
    build manifest and the sweep CSV) so a run that used it cannot read as a
    clean xcodebuild pass, and remove it once xcodebuild has held across a
    full iOS sweep. The _SwiftSyntaxCShims case is root-caused below.
    DONE 2026-10-05: after the root-cause fix, a full iOS sweep built all 101
    files with xcodebuild (101 x "built by: xcodebuild + iosContainer",
    101/101 pass), so the fallback was removed from compile.zsh: an xcodebuild
    failure exits 1 with its log and state, and nothing else runs.
    - [x] Fallback made loud (2026-10-05): compile.zsh -ios keeps the xcodebuild
      output in testapp/output/ios-xcodebuild-<Pn>.log, and on failure appends
      the state (product, DerivedData/TestApps-* with creation times, the
      Redefinition lines) and exits 1. Swift Bundler runs only with
      SCUI_IOS_BUNDLER_FALLBACK=1, reported as a warning and in "built by".
      Proven on a real failure: P12 at 07:00 and 07:05, both
      "Redefinition of module '_SwiftSyntaxCShims'", deterministic. The first
      version died with `print: bad option: -` on its own heading -- the check
      would have read as working until a failure tried to use it.
    - [x] Root cause found and fixed (2026-10-05). xcodebuild had no
      -derivedDataPath, so it resolved packages into
      ~/Library/Developer/Xcode/DerivedData/TestApps-*/SourcePackages while
      Swift Bundler (-derivedDataPath = $ios_derived_data) resolved them into
      .compile-work-ios/.../arm64-apple-iphonesimulator/SourcePackages, and both
      shared OBJROOT. Every target's cached PIF (XCBuildData/PIFCache) carries
      the swift-syntax prebuilts' absolute path, and an unchanged target keeps
      its cached PIF: SwiftCrossUIMacrosPlugin's (2026-09-29, bundler) named
      .build's checkout, MacroToolkit's (regenerated) named DerivedData's, and
      the plugin got both sets of -I. Fix: compile.zsh passes the same
      -derivedDataPath as the bundler, and the stale XCBuildData was removed
      once. Verified: P12, which failed twice in a row, builds; after the
      purge xcodebuild -> bundler -> xcodebuild all succeed with the plugin
      recompiled each time and 0 DerivedData/TestApps paths in any log; P76 and
      P77 run on the simulator built by xcodebuild. Adding the flag WITHOUT the
      purge passed P12 but still showed DerivedData paths from the old PIFs --
      the purge is part of the fix on any tree built before it.
    - [x] Homebrew clang in iOS builds (found in the same log): a shell profile
      exporting CC/CXX=/opt/homebrew/opt/llvm/bin/clang made xcodebuild compile
      the C targets with it, explicit modules off ("did not match the configured
      compiler", 354 times in one P12 build). compile.zsh unsets CC and CXX for
      xcodebuild only; the next P12 build: 0 and 0, BUILD SUCCEEDED.
    - [x] The purge is automatic (2026-10-05): before the
      iOS build loop compile.zsh lists every SourcePackages path in
      XCBuildData/PIFCache, and if any is not $ios_derived_data/SourcePackages it
      says so and removes XCBuildData (one full rebuild). Proven both ways: on
      the clean tree P12 built with no message and XCBuildData untouched; with a
      PIF naming DerivedData/TestApps-fake planted, the run named it, removed
      the cache, rebuilt from scratch (rc 0, xcodebuild), and the rebuilt cache
      names only this tree. Covers clones built before 5deb2156 and trees that
      have moved, without a manual step.
  - [x] .compile-work-android/.build-bundler/bundler/apps/<Pn>/<Pn>.project
    was ~1 GB per app plus a duplicate APK each. Swift Bundler deletes and
    regenerates the project on every bundle (APKBundler.swift), so a shared
    folder would reuse nothing; test_android.zsh now moves the APK out and
    drops the project, so one Gradle project exists at a time (2026-10-05).
    Existing ones removed: 400 -> 456 GB free. P1 then P12 built and
    launched; P12's bundle 33 s against 32 s before.
  - [x] Concurrency: test_ios.zsh shares testapp/.bundledApp (runner project,
    build, and the .xctestrun it edits with PlistBuddy) across all apps, and
    compile.zsh shares one .compile-work-<backend> tree per backend, so two
    runs on the same platform at once are not safe -- they were not before
    the DerivedData fix either.
    DONE 2026-10-05 as serialisation, not parallelism: test_support/
    platform_lock.zsh gives Android and iOS a lock each (mkdir + owner PID,
    dead-owner takeover, re-entrant for a child, released through zshexit),
    taken by test_android.zsh, test_ios.zsh and compile.zsh -android/-ios. A
    second run now waits. Verified on both: two runs started 3 s apart, the
    second printed "waiting for the <platform> lock" and ran after the first,
    both rc 0, the nested compile.zsh passed straight through. True parallel
    runs would need a device and a 5-15 GB tree per run; not done.
- [-] **CANCELLED 2026-10-04. Kotlin -> pure JNI rewrite (CustomSegmentedGroup etc.): not
  recommended.** Profiling shows the cost is the NUMBER of JNI crossings;
  Kotlin helpers do several things per crossing, pure JNI would add crossings.
  Only worth it to drop the Kotlin/Gradle build dependency.
- [-] **CANCELLED 2026-10-04. swift-java method-ID cache (fork): deferred** -- not needed at parity.
- [x] **Per-Pn performance table.** Only P52/P64/P66 report numbers. Proposed:
  an env var that makes SwiftCrossUI print update-time statistics (count,
  median, p95, max) at exit; the sweeps collect them per platform so every
  Pn is compared Android vs iOS vs macOS on the same action file.
  DONE 2026-10-05. SCUI_UPDATE_STATS=1 (or --update-stats, which is how it
  reaches an Android app) makes UpdateTimings.swift time every update in
  Publisher.observeAsUIUpdater and print a cumulative "update-stats: count
  median_ms p95_ms max_ms" line on stderr after 1.5 s of quiet, and every 5 s
  while an app animates without pause -- not at exit, since apps under test
  are killed. test_android / test_ios / test_common (macOS, Windows) pass the
  flag and print the last line as "==> update-stats:"; the sweeps export it
  and write testapp/output/update-stats-<platform>.csv2;
  testapp/update_stats_table.zsh joins the three into one Markdown table.
  Verified on all three with P12 and P66 (P66: android 1.6/3.2/9.3 ms n=309,
  ios 1.1/4.0/16.2 n=231, macos 1.3/1.9/2.4 n=310). The sweep CSVs are now
  written through csv2 (test_support/csv2_rows.zsh) instead of Python csv,
  whose writer put CRLF on every line. Not yet: WSL (print_summary_wsl reads
  the log through wsl.exe) and a full three-platform sweep to fill the table.
- [x] **Stack ideal width undercounts (P51).** FIXED 2026-10-01: commit-time
  redistribution offered the stack's overflowed result (522) instead of its
  proposal (408); it now offers the smaller of the two. On iPhone the outer VStack
  reports 522 pt while the two-column HStack inside it draws to 579, so the
  root scroll host stops 57 pt short and the second column is cut even
  scrolled to the end. Not iOS-specific -- any window narrower than the two
  columns. Evidence: a dumptree row after P51's scroll.
- [x] Android P5 re-aimed (2026-10-04, verified: Alert C on top). The AVD
  whose data went bad when /Volumes/Windows dropped was replaced by
  swift-cross-ui-api36b on /Volumes/Windows and the old one deleted; full
  Android sweep on it: 98/98 launched, every capture read.

### Then: iPad testing (after 1-4)

- [x] **Windowed mode.** DONE 2026-10-02: `test_support/ipad-windowed-apps.csv`.
  Fastest: set it once by hand in the iPad Simulator,
  Settings > Multitasking & Gestures > Windowed Apps (it persists). Durable:
  have the XCUITest runner drive the Settings app (`com.apple.Preferences`) so
  a fresh Simulator can be set up unattended. `defaults write
  com.apple.WindowManager GloballyEnabled` and `com.apple.springboard
  SBChamoisWindowingEnabled` did NOT switch it (2026-09-30).
- [x] **Mac input source.** Since 2026-10-03 the active input source is Zhuyin
  (com.apple.inputmethod.TCIM.Zhuyin), and the macOS synthesiser's keys go
  through it: P71's Cmd-S / Cmd-Shift-E fire 0 times and P9 types kana instead
  of "hi" -- with the old Publisher too, so not a code change. Switch to ABC
  before macOS sweeps, or make the synthesiser select an ASCII source itself.
  DONE 2026-10-05: AppKitSynthesiser.prepareForReplay switches to the ASCII
  keyboard layout when the file sends keys and the current source is not one,
  reports it, and finishReplay restores the original. Verified with Zhuyin
  selected: P71 plain 1 / shifted 1 / disabled 0, P9 typed "hi", the log reads
  "Zhuyin -> ABC ... restored to Zhuyin", and Zhuyin was current afterwards.

### 2026-09-12 Windows / WSL handover

- [x] **M1. #32 手勢 — 三份實作完成,拖曳已驅動驗證** — 新增三個協定(`DragGestures`/`MagnifyGestures`/`RotateGestures`,分開是因為 Android 沒有旋轉偵測器)、`onDragGesture`/`onMagnifyGesture`/`onRotateGesture` 三個 modifier,五個 backend 全部實作。**AppKit 的拖曳以真實 `CGEvent` 驅動並對著像素驗過**:面板在螢幕 (80,252)、送出 (150,290)→(230,320),回報 start (70,38)、location (150,68)、translation (80,30),三者一字不差。**縮放與旋轉編過但未驅動**——此處沒有任何合成器產得出觸控板手勢,需要有人在機器前用兩指做一次。順帶抓到的兩件事寫在程式碼裡:pan 辨識器的 slop 門檻會讓 `.began` 的座標偏晚(改用 `translation(in:)` 回推);以及 P65 自己的回報文字變長會推動置中的版面,讓 80 點的拖曳量成 100 點
  - **2026-10-05 由 [~] 改為 [x]:** 當時未驅動的縮放與旋轉,已由 M9(2026-09-17)在 iOS 與 Android 驅動,AppKit 與 X11 以寫明的理由拒絕(見 completed.md 的 M9)。沒有剩下的部分。
- [x] **M3b. #109 popover `arrowEdge` — 兩個 Windows backend 已完成並成對驗收(2026-09-16)** — 決定為 (1):加 `arrowEdge` 當**提示**、backend 可翻轉。落地形狀:獨立協定 `BackendFeatures.PopoverArrowEdges`(一個方法)加上 `.popover(isPresented:arrowEdge:onDismiss:content:)`;**不在 `presentPopover` 上加參數**,那會一次弄壞五個 conformance,而其中四個此處編不動(mistakes 第 10 條)。
  - **2026-10-05 由 [~] 改為 [x]:** 上文已寫明 2026-09-17 五個 backend 全部 conform `PopoverArrowEdges` 並各自以成對動作檔驅動;兩個後續修正也已落地。沒有剩下的部分。
  - **WinUI**(`Flyout.placement`,偏好存在 `Popover` 上以免被 `presentPopover` 的 `.auto` 蓋掉):同一顆按鈕,`.top` 面板在上、`.bottom` 在下,兩張圖含讀數。
  - **GTK**(`GtkPopover.position`):`.top` 尖角**朝下**、`.bottom` 尖角**朝上**。**這一對比 WinUI 那對更強**——方向是 `GtkPopover` 自己畫在圖上的,不是從面板位置推論的。
  - **丟棄過兩組不可證偽的安排**,理由寫在動作檔裡:第二顆按鈕四周都沒空間,`.bottom` 翻到上面、`.leading` 翻到右邊,每一組的兩張圖都相同。**一組不可能不同的對照,無論程式如何運作都證明不了任何事。**
  - **`leading`/`trailing` 在兩邊都解析為 left/right**,因為 `GtkPositionType` 與 `FlyoutPlacementMode` 都不跟隨書寫方向;RTL 版面應當對調,這句話寫在兩個實作裡。
  - ~~**AppKit / UIKit / Android 尚未實作**,那是 Mac 那邊的。~~ **2026-09-17 三個都完成並各自以成對
    動作檔驅動過。** 五個 backend 現在都 conform `PopoverArrowEdges`;P50 的「arrow edge supported」
    在三處都讀到 `yes`。
    - **AppKit**:`NSPopover` 沒有可設定的邊屬性,因此偏好存在 `NSCustomPopover` 上、由
      `presentPopover` 花掉。**第一版對應是反的**:檔案裡原有的註解說「`.maxY` 是下方」(從本 backend
      的翻轉 view 推論而來),而擷圖說相反——`p50-macos-final-20260917-155815.png` 讀數寫 `top` 而面板
      在**下方**、`-155948.png` 寫 `bottom` 而面板在**上方**。`NSPopover` 是在 AppKit 自己 y 向上的
      螢幕座標裡讀 `preferredEdge` 的。修正後:`-160136.png`(top,面板在上、讀數看得見)、
      `-160229.png`(bottom,面板在下)。
    - **UIKit**:`permittedArrowDirections` 指的是**箭頭**在哪一側,與 `Edge` 相反,因此
      `.top -> .down`、`.bottom -> .up`。**而驅動時發現 iPhone 上的 popover 根本不是 popover**:
      compact 寬度下 UIKit 會把它改成 sheet,除非 delegate 拒絕,而 `CustomPopover` 沒有拒絕
      ——`p50-ios-final-20260917-161038.png` 是一塊從畫面頂端整片蓋下、沒有錨定的面板,於是 P50 自己
      「每塊面板都必須落在開啟它的那顆按鈕旁邊」根本無從成立。現已回傳 `.none`。修正後:
      `-161314.png`(top,面板在上、箭頭朝下)、`-161400.png`(bottom,面板在下、箭頭朝上)。
      **那份 `.bottom` 檔案原本預測「兩張會一樣」(下方只有 144 點、面板約 200 點),而執行推翻了它**
      ——UIKit 會把 popover 縮到它擁有的空間,而不是拒絕那一側。
    - **Android**:五個之中唯一「這件事是算術」的。`PopupWindow` 沒有位置屬性,因此
      `createPopover` 改回傳 `CustomPopupWindow`(持有偏好的 Kotlin 子類別),`presentPopover` 算出
      `showAsDropDown` 的位移。**上/下那一對在這台裝置上分辨不出東西,而這是量出來的**:錨點在 914 點
      視窗的 y 755、下方約 140 點對上約 200 點的面板,`showAsDropDown` 會把放不下的 popup 移到上方
      ——`-162100.png`(top)與 `-162204.png`(bottom)是同一塊面板在同一處,各自帶著不同的讀數。
      把錨點捲高也辦不到:內容在 2400 像素中結束於 2391,一列 `scroll` 沒有改變任何 bounds。
      **真的做得出差別的是 `.trailing`**:`-162438.png` 的面板明顯右移、與按鈕同高而非差一列。
    - **兩個後續修正(同日,由「這三件需要修嗎?」問出來的):**
      - **AppKit 的預設側邊改為下方。** 沒有給 `arrowEdge` 的 popover,原本在 AppKit 上開在錨點
        **上方**(`p50-macos-final-20260917-195515.png`,讀數 `none (platform decides)`),而另外四個
        backend 都是下方(`GtkPopover` 預設、`showAsDropDown`、`Flyout` 自動、UIKit 的 `[.up,.down]`)。
        那行呼叫自落地以來一直帶著 `.maxY`,而它上面的註解寫著「那會放在按鈕下方」——意圖對、主張錯,
        而且從來沒有人變動過它去檢查。改為 `.minY` 後:`-195726.png`,面板在下方。
      - **UIKit 在「放不下」時對齊 Android 的做法。** 同一道算術,兩個平台原本答得不一樣:Android 會把
        放不下的 popup **移到**另一側並保持完整,UIKit 則把 popover **縮**進去——而 P50 顯示了代價:
        `-161400.png` 裡面板在按鈕下方,`press me (0)` 與 `close this panel` 被下緣切掉了。
        `UIKitBackend+Popover.swift` 現在會對著 safe area 量出空間(加 13 點箭頭),被要求的那一側
        容不下就改要求相反的一側。修正後:`-200019.png`(同一個 `bottom` 要求,面板在**上方**且完整)、
        `-200123.png`(`top` 重跑,不變)。UIKit 自己的縮小仍是兩側都放不下時的底線。
    - **順帶在 P50 上修掉一個 macOS 的排版缺口**(非 backend):視窗以內容的理想尺寸 780x825 開啟,
      而第 2 區塊的三顆按鈕被畫成三像素高的長條。手動改成 780x1020 就正常、改成更寬的 1400x825 則否,
      因此是高度;`defaultSize` 與 AppKit 儲存的視窗框都蓋不過那次「依理想尺寸重設大小」。P50 現在在
      AppKit 上要求 `.frame(minHeight: 1000)`,而「理想高度比實際能繪製的高度少約 150 點」這件事本身
      寫進了 todo.md。
- [x] **11. #117 phase 3(依需求建列)— AppKit 已落地,靜止時的問題解決了** — 新增 `BackendFeatures.LazyListRows`(conformance 檢查,與 `ScrollingLists` 同樣可一次轉一個 backend)。**量到:10,000 列 423 MB → 104 MB**,而單列基準線是 102 MB —— 也就是「開在一萬列上的清單,成本等於開在空清單上」。400 列 104、2000 列 103,是**平的**而不只是比較小。關鍵一步是**先建一列來種下高度估計值**:少了它,表格以為清單很短、排出遠多於它會顯示的列,provider 被呼叫 500+ 次才顯示 12 列。**未解決且已量過的界限**:捲動時每造訪一列仍多約 30 KB 且不回收(104→225 MB / 600 段),heap 指出是 AppKit 抓著 view(`NSKeyValueDependency` 1,381→25,835),不是框架抓著節點。下一階段在 backend 側:列捲出視野時要釋放或重用它的 view。**UIKit 也已轉換**:10,000 列 449 MB → 170 MB,而 500 列同樣是 170 MB(平的)。**Android 也已轉換,並已在裝置上量過**:10,000 列 385 → **92 MB**,單列 91 MB(`dumpsys meminfo` 的 `TOTAL PSS`,同一支 APK、同一台模擬器),而 10,000 列時 provider 被呼叫不到 500 次。形狀上:`BaseAdapter` 本來就是「問第 N 列」的形狀,缺的是「帶參數且有回傳值」的 Java→Swift 路徑——用 `external fun` + `@JavaImplementation`(先例是 `MainRunLoopTickler.tickle`),並以一個 id 對應到 Swift 側的 provider,因為 JNI native method 沒有被捕捉的狀態。GTK/WinUI 尚未轉換
  - **2026-10-05 由 [~] 改為 [x]:** 剩下的 `LazyListRowLifetimes`(AppKit / UIKit / Android)已由 M5 完成並驅動(見 completed.md);末尾「GTK/WinUI 尚未轉換」早已更正。2026-10-05 P57 在 macOS、iOS、Android 都重跑通過。
  - **末尾那句「GTK/WinUI 尚未轉換」已經過期(2026-09-16 查證),與第 8 條是同一個錯。**
    `Sources/WinUIBackend/WinUIBackend+LazyListRows.swift:81` 宣告
    `extension WinUIBackend: BackendFeatures.LazyListRows`;
    `Sources/GtkBackend/GtkBackend+LazyListRows.swift:4` 宣告
    `extension GtkBackend: BackendFeatures.LazyListRowLifetimes`,而該協定 refine 了
    `LazyListRows`(`Containers/LazyListRows.swift:5`),因此 **GTK 兩者都滿足,否則編不過**。
    五個 backend 全部有 `LazyListRows`;真正的缺口只在 `LazyListRowLifetimes`,而且在
    AppKit / UIKit / Android 那三個(見第 8 條與 M5)。

### 為什麼缺陷排在功能之前 / Why the defects moved above the features

- [x] **WinUI:`frameClockToken?.dispose()` 真的取消訂閱了嗎(由背景段落拆出,2026-10-05)。** 設計上對,但從沒量過:P64 繞過 `AnimationDriver`。實驗很便宜:start → stop → 再 start,量第二段速率——仍約 141 Hz 表示取消有效,約 283 Hz 表示第一次訂閱洩漏、每次動畫再洩漏一次。原文在 completed.md「減少不必要的重繪」一節。Windows 那台機器上做。
  **DONE 2026-10-07 (Windows):** `P64-WinUI.exe --debug --restart` (start, stop, start; no input needed): pass 1 78 ticks / 1.79 s = 42.9 Hz, pass 2 88 / 2.05 s = 42.4 Hz, **0 of 87 sub-frame gaps in pass 2 -> UNSUBSCRIBE OK.** A leaked first subscription would put a second tick inside each frame. The rate itself was 42 Hz, not the ~141 Hz above -- this run was over a Chrome Remote Desktop session, presumably why; the gap count, not the rate, is the verdict (P64 says both rates are weak).
  **2026-10-07 完成(Windows):** P64 `--restart`:第二段 87 個間隔中 0 個落在同一幀內 -> 取消訂閱有效。速率 42 Hz(經 Chrome 遠端桌面執行),判定依據是間隔而非速率。
