# queue

## 2026-09-12 Windows / WSL handover

- [ ] **#123 external verification follow-up (2026-09-17)**: WSLg AT-SPI
  reads label/hint/value and excludes decorative, but still exposes the original
  `X` child. Windows external UIA also lists `X` and `decorative`; Narrator and
  control/content-tree filtering remain unverified. See
  `testapp/plan/verification-followup-20260917.md`. 外部探針已執行，不是完整通過。

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

Source corrections to older entries below: #128 is already Double
(`cfe30184`), and WinUI #117 was implemented in `bde16de0`; neither remains
an unimplemented conversion. 原始碼已完成上述兩項，舊條目不可直接當作現況。

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
- [x] **2c. 動作檔已能驅動 AppKit 的 popover** — 兩件事要一起改:(1)`targetWindow()` 不再回傳 popover——popover 會取得 key,於是每一個**非** popover 的座標都在對它解析,而檔案照樣重放成功、每次點擊都落在某個看似合理的位置;(2)`origin=popover` 的事件投遞到 **popover 自己的視窗**,投給後方的視窗會把它 light-dismiss,而「被關掉的 popover」與「沒打中的點擊」是同一張圖。`popoverOrigin` 取的是**內容區**而非視窗框(框比畫出來的面板大 26 點,含箭頭與陰影)。實測:`P50-panel-press-me.csv` 讓 P50 記下 `popover counter 1`
- [x] **3. P32:Toggle 沒有可見的開啟狀態** — 已修。`onStateBezelColor` 來自 `environment.toggleColor`,app 沒設就是 nil,於是「開」什麼都不畫;改為退回 `.controlAccentColor`
- [x] **4. P44:vertical stack 空間耗盡** — 已修:那是誤報。`offered 643 / took 643` 相等,什麼都沒不夠;是 `Spacer` 在沒有餘裕時正確地拿到 0。回報條件補上「確實溢出」,與它自己的訊息一致
- [x] **5. P28:點擊延遲 — 兩條未量的路徑都量完了** — 「真實滑鼠事件合成不出來」不成立:`AppKitSynthesiser` 檔頭那個「CGEvent 送出 0 個事件」量於 `AXIsProcessTrusted() == false`,而這台機器現在是 `true`,`CGEvent.post(.cghidEventTap)` 會送達。實測 click→body:**啟動後第一次點擊(未預熱)16.0 ms**、預熱後 2.9–9.9 ms,三輪。合成路徑先前量到的是 0–2 ms / 像素 69 ms。**沒有任何一條接近一秒。** 工具留在 `testapp/test_support/measure/real_mouse_latency.swift`,檔頭的量測也已補上「已授權」那一半
- [x] **5b. #126 `onEditingChanged`** — 已完成。五個 backend 全數實作,AppKit/UIKit/Android **實測建置通過**,GTK/WinUI 寫了但未執行(待查假設已在檔內指名)。**P61 是它的測試 app**,自帶對照組
- [~] **M1. #32 手勢 — 三份實作完成,拖曳已驅動驗證** — 新增三個協定(`DragGestures`/`MagnifyGestures`/`RotateGestures`,分開是因為 Android 沒有旋轉偵測器)、`onDragGesture`/`onMagnifyGesture`/`onRotateGesture` 三個 modifier,五個 backend 全部實作。**AppKit 的拖曳以真實 `CGEvent` 驅動並對著像素驗過**:面板在螢幕 (80,252)、送出 (150,290)→(230,320),回報 start (70,38)、location (150,68)、translation (80,30),三者一字不差。**縮放與旋轉編過但未驅動**——此處沒有任何合成器產得出觸控板手勢,需要有人在機器前用兩指做一次。順帶抓到的兩件事寫在程式碼裡:pan 辨識器的 slop 門檻會讓 `.began` 的座標偏晚(改用 `translation(in:)` 回推);以及 P65 自己的回報文字變長會推動置中的版面,讓 80 點的拖曳量成 100 點
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
- [~] **M3b. #109 popover `arrowEdge` — 兩個 Windows backend 已完成並成對驗收(2026-09-16)** — 決定為 (1):加 `arrowEdge` 當**提示**、backend 可翻轉。落地形狀:獨立協定 `BackendFeatures.PopoverArrowEdges`(一個方法)加上 `.popover(isPresented:arrowEdge:onDismiss:content:)`;**不在 `presentPopover` 上加參數**,那會一次弄壞五個 conformance,而其中四個此處編不動(mistakes 第 10 條)。
  - **WinUI**(`Flyout.placement`,偏好存在 `Popover` 上以免被 `presentPopover` 的 `.auto` 蓋掉):同一顆按鈕,`.top` 面板在上、`.bottom` 在下,兩張圖含讀數。
  - **GTK**(`GtkPopover.position`):`.top` 尖角**朝下**、`.bottom` 尖角**朝上**。**這一對比 WinUI 那對更強**——方向是 `GtkPopover` 自己畫在圖上的,不是從面板位置推論的。
  - **丟棄過兩組不可證偽的安排**,理由寫在動作檔裡:第二顆按鈕四周都沒空間,`.bottom` 翻到上面、`.leading` 翻到右邊,每一組的兩張圖都相同。**一組不可能不同的對照,無論程式如何運作都證明不了任何事。**
  - **`leading`/`trailing` 在兩邊都解析為 left/right**,因為 `GtkPositionType` 與 `FlyoutPlacementMode` 都不跟隨書寫方向;RTL 版面應當對調,這句話寫在兩個實作裡。
  - **AppKit / UIKit / Android 尚未實作**,那是 Mac 那邊的。
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
- [~] **11. #117 phase 3(依需求建列)— AppKit 已落地,靜止時的問題解決了** — 新增 `BackendFeatures.LazyListRows`(conformance 檢查,與 `ScrollingLists` 同樣可一次轉一個 backend)。**量到:10,000 列 423 MB → 104 MB**,而單列基準線是 102 MB —— 也就是「開在一萬列上的清單,成本等於開在空清單上」。400 列 104、2000 列 103,是**平的**而不只是比較小。關鍵一步是**先建一列來種下高度估計值**:少了它,表格以為清單很短、排出遠多於它會顯示的列,provider 被呼叫 500+ 次才顯示 12 列。**未解決且已量過的界限**:捲動時每造訪一列仍多約 30 KB 且不回收(104→225 MB / 600 段),heap 指出是 AppKit 抓著 view(`NSKeyValueDependency` 1,381→25,835),不是框架抓著節點。下一階段在 backend 側:列捲出視野時要釋放或重用它的 view。**UIKit 也已轉換**:10,000 列 449 MB → 170 MB,而 500 列同樣是 170 MB(平的)。**Android 也已轉換,並已在裝置上量過**:10,000 列 385 → **92 MB**,單列 91 MB(`dumpsys meminfo` 的 `TOTAL PSS`,同一支 APK、同一台模擬器),而 10,000 列時 provider 被呼叫不到 500 次。形狀上:`BaseAdapter` 本來就是「問第 N 列」的形狀,缺的是「帶參數且有回傳值」的 Java→Swift 路徑——用 `external fun` + `@JavaImplementation`(先例是 `MainRunLoopTickler.tickle`),並以一個 id 對應到 Swift 側的 provider,因為 JNI native method 沒有被捕捉的狀態。GTK/WinUI 尚未轉換
  - **末尾那句「GTK/WinUI 尚未轉換」已經過期(2026-09-16 查證),與第 8 條是同一個錯。**
    `Sources/WinUIBackend/WinUIBackend+LazyListRows.swift:81` 宣告
    `extension WinUIBackend: BackendFeatures.LazyListRows`;
    `Sources/GtkBackend/GtkBackend+LazyListRows.swift:4` 宣告
    `extension GtkBackend: BackendFeatures.LazyListRowLifetimes`,而該協定 refine 了
    `LazyListRows`(`Containers/LazyListRows.swift:5`),因此 **GTK 兩者都滿足,否則編不過**。
    五個 backend 全部有 `LazyListRows`;真正的缺口只在 `LazyListRowLifetimes`,而且在
    AppKit / UIKit / Android 那三個(見第 8 條與 M5)。
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

- [ ] **M9. magnify / rotate 在 mac 與 iOS 上仍未驅動 — 缺的是動作檔格式本身**
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

- [ ] **#123 複驗(2026-09-17,應 Windows 之請):我們這三個 backend 乾淨,但複驗本身找到一個更大的洞**
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
  - **給那邊的一條線索(GTK)**:AT-SPI **沒有** Android 那種「不重要」過濾,所以那棵樹就是 AT 走訪的樹
    ——`X` 若在裡面就是真的在裡面。GTK4 可以把內層 label 的 accessible role 設為 `NONE`/presentation,
    或對它 `gtk_accessible_update_state(... GTK_ACCESSIBLE_STATE_HIDDEN, TRUE ...)`。我這邊沒有 GTK,
    無法驗,所以這是線索不是結論。
  - **仍未做**:Narrator 的實際朗讀(那邊)、以及 `.accessibilityLabel` 對 `Text` 在其他 backend 上的
    等價檢查(這次只在 iOS 上被問到)。

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

- [x] **T3. AndroidBackend 已遷到 Swift 6 language mode(2026-09-16)** — 五個並行性問題修好並保留:stdio 緩衝移進 C shim(`stdout`/`stderr` 是可變 C 全域,Swift 6 拒絕引用);兩個 `@Entry` 改為手寫 key(macro 產生的是「非 `Sendable` 型別的 `static let`」,而教 macro 加 `nonisolated(unsafe)` 會讓整個套件的同一個診斷消音);一個泛型輔助函式移除了**永遠到不了**的 `default:` 參數;`SharedPreferences` 依 Android 自身的 thread-safety 保證加標註;`ActivityListener` 與兩個 AndroidKit 型別改 `@unchecked Sendable`,因為 **swift-java 的 `@JavaMethod` 展開會把 `self` 與每一個參數送過隔離邊界**。第六個不是模式問題:`CommandLine.arguments` 的 setter 在 Swift 6.0 **被廢除**,而少了它 Android 上 `--debug`/`-rows`/`-actionfile` 全部送不到(runtime 的 argv 是 JVM 的)。先試的「v5 單檔 target」在 `swift build` 下可用、在 swift-bundler 的 `swift build --product` 下**消失**(`no such module`,兩份 manifest 快取都清過,也列進 product 了,原因未明,已放棄)。落地的做法不需要任何 target:那個廢除是**編譯期**閘門,符號仍由 runtime 匯出(以 `nm -D libswiftCore.so` 在實際使用的 Android SDK 上查過),改以 `@_silgen_name` 抵達,`__owned` 明寫。**上機驗過**:四個旗標原樣抵達、零崩潰、程序存活,`focus changes heard: 3`、`refused (correct)`。**順帶抓到一個回歸並記為 mistakes 第 9 條**:把 `AndroidBackend` 加進 `migratedToSwift6` 會讓**非 Android** 的每一次建置以 manifest 自己的打字守衛死掉——而我是在 Android 上驗了五次的,那正是該缺陷不可能出現的平台。
- [~] **T4. #121 step 2 — 與 Windows 撞了同一個功能,採用他們的設計** — 合併時才發現兩邊都實作了 `.keyboardShortcut(_:modifiers:)`:**檔案不同,所以 git 沒報衝突,是編譯器報的**(`invalid redeclaration`)。他們走 **environment**(`environment(\.keyboardShortcut, …)`),而且**已在 GTK 與 WinUI 兩個 backend 上驗過**;我走的是「在 `ResolvedMenu.Item.button` 上加第三個 associated value」,只在 AppKit 驗過。**留他們的**——一個功能兩套機制比其中任何一套都糟,而他們那套已經有兩個 backend 在讀。我的 `ResolvedMenu`/`MenuItem`/`Menu.resolve` 改動與那個 modifier 全部還原,AppKit 與 Android 改讀 `environment.keyboardShortcut`。**AppKit 以 actionfile 重新驗過**(`actions/mac/P71-shortcuts.csv`,選單全程關著):`plain 1、shifted 1、disabled 0`。Android **編過未驅動**。**UIKit 是缺口**,並在原地寫明理由:`UIAction` 收 closure 帶不了按鍵,`UIKeyCommand` 帶得了按鍵卻收 selector、經 responder chain 派送。**測試 app 是新的 P71**,它斷言計數器而非選單外觀——每個 backend 都畫得出「⌘S」,而那樣的截圖與能用的一模一樣。
- [x] **4. #121 鍵盤快捷鍵 — 五個 backend 全數完成(2026-09-16 傍晚由原始碼查得)** — UIKit 那一格已由 Mac 補上(`UIKitBackend+Menu.swift` 讀 `environment.keyboardShortcut`,`cfc442aa` 實作、`8ccfc78a` 驅動通過)。下方那句「只剩 UIKit」是當天稍早為真。原文保留:2026-09-16 由**原始碼**查得(不是讀這份 queue):GTK、WinUI、AppKit、Android 都已讀 `environment.keyboardShortcut`,**UIKit 沒有**。那一行「`ResolvedMenu.Item` 沒有 shortcut 欄位」已經不成立——最後採用的是 environment,不是欄位。
- [x] **5. focus / accessibility(#122 / #123)— 五個 backend 全數完成** — GTK 與 WinUI 於 2026-09-16 補上(`4c7bbf12` / `9746bbeb`),P70 與 P69 都以動作檔驅動過。**限制寫明**:GTK 沒有 accessibility 的讀回路徑(`gtkaccessible.h` 只有 update、沒有 getter,要讀得走 AT-SPI),WinUI 的讀回是行程內的、對 Narrator 實際唸出什麼沒有發言權。原文保留:AppKit / UIKit / Android 已落地並驗過,GTK 與 WinUI 未——形狀議定後三份實作已完成,P69 與 P70 分別以 `ax_dump`、`uiautomator --compressed` 與真實點擊/觸控驗過。交接在 `queue-windows.md`。
- [x] **6. #74 `-GPU` on macOS — 已實作(AppKit + UIKit)** — 那個「設計問題」其實已被協定的形狀回答了:`GraphicsAdapter` 的三個欄位 `name`/`isRemovable`/`isLowPower` **就是 `MTLDevice` 的三個屬性**,而 `AdapterOutcome.requiresRestart` 的文件早就寫著「macOS 不需要這個,Metal 在執行期選擇」。AppKit 用 `MTLCopyAllDevices()`(系統預設排最前,因為 `.systemDefault` 取 `first`)、UIKit 用 `MTLCreateSystemDefaultDevice()`(`MTLCopyAllDevices` 僅限 macOS,而 iOS 只有一張且不可移除)。**明說它不做什麼**:它不會把視窗移到另一張 GPU——window server 依「視窗所在顯示器」決定合成用的 GPU,macOS 上沒有應用程式做得到。P68 驅動並列出介面卡。**Android 已補上**:回報一張以 SoC 命名的介面卡(`SOC_MANUFACTURER`/`SOC_MODEL`，早於 API 31 的裝置退回 `HARDWARE`),而**不是**空清單——空清單會讓框架解析為「沒有可用的繪圖介面卡」，那句話對每一台 Android 裝置都是假的。名字是 SoC 而非 GPU:真名要 `glGetString(GL_RENDERER)`，那需要對 `EGL_DEFAULT_DISPLAY` 做 `eglInitialize`/`eglTerminate`——也就是 app 正在算繪的那個 display，而這台機器驗不了它會不會弄壞算繪
- [x] **7. #28 動畫 / #32 手勢** — 五個 backend 全部 conform(`DragGestures`/`MagnifyGestures`/`RotateGestures`、`FrameClocks`)。**未驅動的只剩 magnify/rotate**:此處合成不出觸控板的雙指手勢,需要有人在機器前做一次。
- [~] **8. #117 phase 3 — 五個 backend 都有 `LazyListRows`;缺的換成 `LazyListRowLifetimes`,而且是在你們那三個** — **GTK 的 `LazyListRows` 早就完成**(`5739d453`):它是由 `LazyListRowLifetimes` **繼承**而來的,因此任何「找具名 extension」的掃描都會說它沒有——那正是這一條原本寫錯的原因。現在真正的缺口在另一個方向:**`LazyListRowLifetimes` 只有 GTK 與 WinUI 有,AppKit / UIKit / Android 沒有**,因此那三個 backend 上被回收的列不會通知框架,只靠 `List.swift` 的 4000 列兜底。WinUI 那份以對照組量過:掃 5000 列,有釋放 146/150 MB、扣住回呼 221/222 MB。原文保留:WinUI / AppKit / UIKit / Android 都 conform `LazyListRows` 並量過(AppKit 423→104 MB、UIKit 449→170、Android 385→92)。**GTK 目前只 conform `LazyListRowLifetimes`**(回收那一半),`LazyListRows` 尚未;Windows 標為 active。那句「400 列 114 MB、10,000 列 423 MB」是**修好之前**的數字,留在此處會讀成現況。
  - **上面那一條自己前後矛盾,而後半段是錯的(2026-09-16 查證,型別系統就是證據)。** 它開頭說
    「GTK 的 `LazyListRows` 早就完成,是由 `LazyListRowLifetimes` **繼承**而來」——**這是對的**;
    結尾卻又說「GTK 目前只 conform `LazyListRowLifetimes`,`LazyListRows` 尚未」。兩句不可能同時
    成立。`Sources/SwiftCrossUI/Backend/BackendFeatures/Containers/LazyListRows.swift:5` 寫的是
    `public protocol LazyListRowLifetimes: LazyListRows`,而
    `Sources/GtkBackend/GtkBackend+LazyListRows.swift:4` 宣告
    `extension GtkBackend: BackendFeatures.LazyListRowLifetimes` —— **編譯器不可能讓它只滿足一半**,
    否則那個 extension 根本編不過。所以 **GTK 兩者都有**,Windows 這一側的 #117 phase 3 沒有缺口。
  - 錯的那半句留在原處,因為它示範的正是這一條開頭已經點名的那個陷阱:**「找具名 extension」的掃描
    看不見繼承而來的 conformance**。同一條目裡先寫對、再照著錯的方式重述一次,說明光是把陷阱寫下來
    並不足以擋住它。
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

---

## 更正:#123 在 GTK/Windows 上**做得到**,我先前說反了

### Correction: #123 IS reachable on GTK/Windows

2026-09-11。我先前寫下「Windows 上的 accessibility 是 WinUI-only,除非 GTK 上游補上 UIA bridge」。
**那句話是錯的**,而且它正是 CLAUDE.md 明令禁止的形狀——把「這個平台沒有內建 X」說成「這個平台
做不到 X」。使用者當場指出來,而規則寫得很清楚:那是**待查證的主張,不是結論**,而且答案仍然是
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

也就是說:**GTK 缺的是「把它自己的樹送出去」,而我們要送的本來就不是它的樹。**
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

**用 `grep -rhoE "BackendFeatures\.[A-Za-z]+"`,不要用 `extension X: BackendFeatures\.Y`。** 後者是我
2026-09-16 的第一個版本,它**兩個方向都錯**:多行的 conformance 寫法

```swift
extension AppKitBackend:
    BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
```

被漏掉(偽陰性,害我以為五個 backend 都沒有 magnify),而註解裡提到協定名稱的行被算進去(偽陽性,
害我以為 UIKit 讀了 `keyboardShortcut`,其實那兩處是我自己寫的「此處**沒有**讀取」)。

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
`extension X: BackendFeatures.Y`. The latter was my first version and it was
wrong in BOTH directions: it missed multi-line conformances (so all five
backends looked like they had no magnify gesture) and it counted comments that
merely name a protocol (so UIKit looked like it read `keyboardShortcut`, when
those two hits were my own comment saying it does NOT). Run both controls before
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
「沒有實作」。2026-09-16 我試著自動分辨兩者,那個判準抓到 0 個繼承項目——所以它是壞的,而我沒有拿它
去開 39 條待辦。**要補完這張表,得先寫出一個能通過正反對照的探針。**

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
是寫的當下為真,而不是現在為真。** 這一段推出去之後我才開始寫,若 Mac 已經有別的形狀,請直接覆蓋
這裡、我照著改。

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

**分工(沿用 #121 那次講定的「各做自己編得動的」):** 協定與 view 端由我落地,GtkBackend 與
WinUIBackend 兩個實作也由我做並驗收;**AppKit / UIKit / Android 三個是 Mac 那邊的**——
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

**那段阻擋警告不是結論,而我把它當成了結論。** 它自己寫著「這是**相關性**,不是已證實的成因」,
而我卻用它來解釋為什麼不驗。實際去跑之後:`SetCursorPos` 生效(`cursor=(406, 621)` 與要求值相符),
**CDP 連著時滑鼠是可用的**。先前那次「點了沒反應」的真正差別在於啟動方式(經 harness 與直接執行),
不是輸入被拒絕。

兩個動作檔都留在 repo 裡,各三次點擊,而**中間那次是拒絕對照**:

| 檔案 | backend | 判決 |
| --- | --- | --- |
| `actions/win/P23-select-rows.csv` | WinUI | 第六列 → `SELECTION now 5`;**標題列 → 一行都沒有**;第一列 → `SELECTION now 0` |
| `actions/win/P23-select-rows-gtk4.csv` | GTK | 完全相同的三個答案,而走的是完全不同的路徑 |

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
it is a correlation rather than a proven cause, and I used it as a conclusion
anyway. Driving it: `SetCursorPos` took, the cursor landed where it was asked to,
and both backends selected. The earlier run that saw nothing differed in how the
app was launched, not in whether input was accepted.

Two action files are kept, three clicks each, the middle one a control:
`actions/win/P23-select-rows.csv` (WinUI) and `-gtk4.csv` (GTK). Sixth row ->
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
Mac side already has a shape for this, overwrite this section and I will follow
it.

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
