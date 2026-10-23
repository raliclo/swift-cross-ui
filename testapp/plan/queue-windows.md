# Windows 一側的佇列 — 2026-09-10(已結,保留作紀錄)

由 Mac 整理。**每一列都附上在 Mac 上查得到的證據,或明說它是待決定而非待實作。**
先讀第 0 節,它會影響接下來能碰的檔案。

**狀態(2026-10-24 查核 git log):** 除 3b、3c(GTK 與 WinUI 上的文字量測檢查、螢幕閱讀器名稱檢查,
沒有找到對應紀錄)之外,每一項都已結案,各節標題附上 commit。

Compiled on the Mac. Every row carries evidence checkable on the Mac, or says
plainly that it is a decision rather than a task. Read section 0 first -- it
changes which files are safe to touch.

**Status (checked against git log on 2026-10-24):** every item is closed, with
its commit in the section heading, except 3b and 3c (the text-measurement and
screen-reader-name checks on GTK and WinUI), for which no record was found.

---

## 0. 先做這件事:rebase,`GridLayoutPlan` 已改名

**#118 已落地,而它改名的正是先前允許 Windows 一側改名的那個型別。** 動到 grid 的分支要先 rebase。

| 舊 | 新 |
| --- | --- |
| `GridLayoutPlan.columnWidths` | `laneSizes` |
| `GridLayoutPlan.columnOffsets` | `laneOffsets` |
| `LayoutSystem.gridRows(of:plan:)` | `gridLines(of:plan:)` |
| `LazyVGrid.resolve(columns:alignment:spacing:proposedWidth:)` | `GridLayoutPlan.resolve(items:axis:alignment:spacing:proposedCrossExtent:)` |
| `alignments: [HorizontalAlignment]` | `alignments: [GridLaneAlignment]`(`.start/.center/.end`) |

新增:`GridLayoutPlan.axis`、`crossAxisExtent`、`Views/LazyHGrid.swift`、`GridItem.verticalAlignment`。
**#120 也已落地**:`Grid` 現在有共用欄與 `gridCellColumns`,`GridRow` 從「body 是 HStack」變成真正的
版面容器。兩者都不需要 backend 支援,所以 GtkBackend 與 WinUIBackend 應該不改一行就跟著對。
**但那句話沒有人驗過**——見第 3 節第一列。

---

## 1. 待 Windows 決定的(不是寫程式)

### ~~1a. #127 走哪一條路~~ — **已答、已實作;WinUI 的編譯修正與驗證見 `25c0cf77`**

Windows 的答覆(`gtk_widget_translate_coordinates` 在已安裝標頭裡、`transformToVisual` 同步且 throws)
定案了路線 (b)。`BackendFeatures.WidgetGeometry.originInWindow(ofWidget:)` 已落地,五個 backend 都寫了。

**Windows 上要查的只有兩件事**:

| 檔案 | 唯一要查的東西 |
| --- | --- |
| `Sources/GtkBackend/GtkBackend+WidgetGeometry.swift` | `graphene_point_t` 在此處是否一如 `Sources/Gtk/Widgets/ScrolledWindow.swift` 那樣經由 `CGtk` 可見。**其餘每一個呼叫該檔都已經在做** |
| `Sources/WinUIBackend/WinUIBackend+WidgetGeometry.swift` | `widget.xamlRoot?.content` 是不是這個 backend 取視窗內容的正確寫法(形狀對、名字未必) |

GTK 那份刻意**不用** `gtk_widget_get_root`——它回傳 `GtkRoot*`(介面),而把它轉成 `GtkWidget*`
是這裡唯一沒有人能在 Mac 上查證的一步。改成用 `gtk_widget_get_parent` 一路往上走,兩個函式收發的
都是 `GtkWidget*`,沒有轉型。

**Android 那份也值得看一下**(`AndroidBackend+WidgetGeometry.swift`):當時 Mac 上的 Android SDK 模組是
Swift 6.3.3、編譯器是 6.4,因此 `compile.zsh -android` 在抵達該檔之前就失敗了。它**不用**
`getLocationInWindow`——那個方法綁定為收一個 Java 會寫入的 `[Int32]`,而橋接層會不會把那份複製寫回,
正是「回傳兩個零而且不報錯」的那種事。改用 `getLeft()`/`getTop()` 沿父節點往上加。

驗收方式:跑 **P63**。Mac 上量到的三個答案(對著像素驗過,不是對著預期):

```
local: x=0 y=0        global: x=92 y=287        named box: x=24 y=31
標記方塊量到 x=92..103、上緣在內容座標 y=287   → global 完全相符
淺藍盒子角落量到 (68, 256) = global − named    → named 完全相符
```

### 1b. #122 focus 協定的形狀

四個方法、`focus` 回傳 `Bool`(因為 Android 在 touch mode 下會正當地失敗)。草案在
`testapp/plan/plan-focus-protocol.md`。**該檔已於 2026-09-10 更正一處誤判**:原本寫「GTK 的
`grabFocus` 必須先產生出來」,那是錯的——`Sources/Gtk` 到處直接呼叫 C 符號,`gtk_widget_grab_focus`
可以直接寫。**這條不再卡在程式碼產生。**

當時待答的只有一件:`FocusManager.TryFocusAsync` 是非同步的,而協定裡的 `focus` 是同步的。
**已答,形狀不變**:WinUI 用同步的 `UIElement.focus(_:)`(`ab2d1d51`)。

### 1c. #109 popover `arrowEdge` 分工 — 已接受(`1ef0edaa`)並完成(`bbac9251`、`e098fc7d`)

提案的分工:SwiftCrossUI 那層 + Gtk + WinUI 在 Windows 上做,AppKit / UIKit / Android 在 Mac 上做。

### 1d. #125 `Table` 的 `selection` 與 `sortOrder` — 已完成(selection `c933f1b7` / `f5d48b34`,sortOrder `b308559a`)

欄寬已完成(`2fd81acb`)。剩下兩項需要 **backend → view 的事件回報**,而 `BackendFeatures.Tables` 當時是單向的。
這與 #122 的 `setFocusChangeHandler` 是同一個形狀問題,值得一起定。

---

## 2. 要在 Windows 上寫的程式(GTK 與 WinUI 那兩格在 Mac 上編不了)

### 2a. #28 Animation 的 GTK 與 WinUI 時鐘

查證過:`CADisplayLink` / `CVDisplayLink` / `Timer.scheduled` 當時在整個 `Sources/` 是 **0 命中**,
所以五個 backend 都還沒有 per-frame 時鐘。協定形狀與 AppKit / UIKit / Android 在 Mac 上做。
**已完成:五個 backend 都有 frame clock(`c4a286d7`)。**

**GTK 那一格不缺 API**:`gtk_widget_add_tick_callback` 已經被直接呼叫——
`Sources/Gtk/Widgets/NV12GLView.swift:248`,連 thread 規則都已寫在該檔註解裡。
WinUI 對應的是 `CompositionTarget.Rendering`。

### 2b. #32 手勢的 Gtk 實作

`GestureDrag` / `GestureZoom` / `GestureRotate` 三個類別**已經產生好**
(`Sources/Gtk/Generated/GestureDrag.swift` 等)。AppKit / UIKit / Android 三份在 Mac 上做,
協定形狀先定再寫。**已完成:五個 backend 都有(`7dabfa89`)。**

### 2c. #79 GTK 39px

仍在。`GtkBackend.swift:1282` 的 `titlebarAllowance` 只在 `decorationProbe == "3"` 時非 0,
因此每次正常執行都少 39px。已定案為 (c):繼續挖「present 之前就能回報 frame 的 GTK 呼叫」,
不接受把 39px 寫成行為;走不通要帶著「試過哪些呼叫、各自回傳什麼」回報。**已結案(`20b03488`):**
39px 缺口改成 8px 超出,內容不再被切,代價是視窗多 8px。

### 2d. P38 WinUI WebView

`00c9210e` 修了兩個真的成因(`EnsureCoreWebView2Async` 在 `isLoaded == false` 時被呼叫;
`IAsyncAction` 是區域變數、一回傳就被釋放),而該 commit 自述 **"The frame is still empty"**。
`results.csv2` 中最後一列 `windows,winui,P38` 仍是 2026-08-28。**已修:** WinUIBackend 改以單執行緒
apartment 自行啟動 application(`results.csv2` 2026-09-17 列),2026-10-20 重跑 Navigations 3、通過。

---

## 3. 要在 Windows 上驗的(Mac 改了共用程式碼,而那兩個 backend 的畫面只能在 Windows 上看)

### 3a. #118 / #120 之後,GtkBackend 與 WinUIBackend 的 grid 有沒有跑掉 — 已在兩個 Windows backend 驗過(`25c0cf77`)

兩項都只動框架,理論上兩個 backend 不改一行就對。**「理論上」正是這棵樹一再抓到的那個詞。**
要看的是 P48(LazyVGrid 三節 + 新增的 LazyHGrid 兩節)與 P51(`Grid` 3x3 加一列 `gridCellColumns(3)`)。

Mac 上量到的數字,供對照:

| 項目 | 數字 |
| --- | --- |
| P51 各欄(修改後) | C2 = 106..155、C3 = 166..215,**三列完全相同** |
| P51 跨欄那列 | 16..215(第一欄左緣到第三欄右緣) |
| P48 第 5 節 lane 間距 | 42 = 34 + 8 |
| P48 第 6 節對齊階梯 | 儲存格頂端相距 **52、52**(若三者都置中會是 48、48) |

### 3b. 文字量測與繪製是不是走同一條路?

AppKit 上不是,而那讓 P34 兩位數的列被切在字形中間:量的是 `NSString.boundingRect`、畫的是
`NSTextField`,而前者對每一個試過的字串都少報約 **4 pt**(系統字型 12:量得 155.3、實需 159.3)。
已修(`3058be0d`),改成向負責繪製的 widget 要數字。

**同一個問題形狀存在於任何「量測 API 與繪製路徑不同」的 backend。** GTK 用 Pango layout 量、
用 `GtkLabel` 畫;WinUI 用 `TextBlock.Measure` 量、也用 `TextBlock` 畫。值得各跑一次
「容器是否比它最寬的子元件窄」的檢查——症狀是最後一個字形被切掉,而**不會有任何東西報錯**。

### 3c. 每一顆按鈕對螢幕閱讀器叫什麼名字?

AppKit 上先前是**空的**:P17、P28、P34 的每一個 `AXButton`,title 與 desc 都是空字串。
`NSCustomButton` 有一個 `accessibilityLabel()` override 本應提供它,但它從不會被詢問(純 `NSView`
在 AX 樹中透明,被看見的是內層 `NSButton`),而且它讀的 `subviews.first` 也是錯的那一個。
已修(`78fc4b0e`)。

工具在 `testapp/test_support/measure/ax_dump.swift`,一支 app 一行地列出每顆按鈕的名字。
**GTK 與 WinUI 值得各跑一次對應的檢查**(Accerciser / Windows 的 Accessibility Insights)——
這一項的失效是完全靜默的:畫面正確、點擊正確、只有螢幕閱讀器什麼都念不出來。

---

## 4. 兩個量測問題(已答,`1ef0edaa`)

1. **#113 那個「48 顆按鈕時一次按壓約 0.3 秒」是在哪個 backend 上量的?** AppKit 上量到的是
   **min 10.5 ms / median 20.7 ms**,少了一個數量級以上。若那是 GTK 或 WinUI 的數字,那代表同一份
   版面程式碼在不同 backend 之間差 30 倍——那本身就是下一個要追的東西,而且方向與「優化版面」相反。
   完整結果在 `testapp/plan/plan-113-layout-cost.md`(四條 arm、五個尺寸、指數 n^0.95–0.96,
   **不是 n^1.5**)。

2. **P28 那份「一秒延遲」的回報是在哪台機器上?** macOS 上兩條路徑都量完了:真實滑鼠事件
   click→body 為**冷啟 16.0 ms、預熱後 2.9–9.9 ms**,合成路徑 0–2 ms、到像素 69 ms。沒有一條
   接近一秒。若那份回報來自 Windows,那要重量的是 Windows 那一側。

**答覆(`1ef0edaa`):** (1) 0.3 秒是 GtkBackend、Windows 11、100% 縮放的數字(`P52-buttonstyle-findings.md`),
但它量的是 `.bordered` 的**按壓轉場**,AppKit 量的是**每格版面成本**——同一支 app、不同的量,在對齊之前
30 倍只是兩個不同量測的比值。(2) `results.csv2` 沒有任何 Windows 的 P28 列,那份「一秒」沒有量測可依。


---

# 追加 — 2026-09-11

## A. GTK 與 WinUI 待轉換:#117 phase 3(依需求建列)— 已完成(WinUI `bde16de0`、GTK `5739d453`)

新增 `BackendFeatures.LazyListRows`(**conformance 檢查**,未 conform 的 backend 行為完全不變)。
方向是反轉的:不再由框架建好每一列交出一個陣列,而是清單在要顯示第 N 列時回頭向框架要。

已轉換並量過:

| | 10,000 列(靜止) | 捲完整份清單 |
| --- | --- | --- |
| AppKit | 423 → **104 MB**(單列基準 102) | 225 MB 且爬升中 → **134 MB 且平** |
| UIKit | 449 → **170 MB**(500 列同樣 170) | 未量(模擬器無捲動合成) |
| Android | 385 → **92 MB**(單列 91,10,000 列 92) | 未量 |

Android 這一列的量測是 `adb shell dumpsys meminfo` 的 `TOTAL PSS`,而非 app 自報的 resident
size——在同一支 app 上,自報值(167 MB)與 `dumpsys`(92 MB)差了近一倍,兩者量的不是同一件事,
因此欄位裡放的是**兩端用同一把尺**的那一個。10,000 列時 provider 被呼叫**不到 500 次**。

**寫這段時 GtkBackend 與 WinUIBackend 尚未轉換**(後來 WinUI `bde16de0`、GTK `5739d453`)。兩者原生都有這一側:`GtkListView` 帶 factory、
`ItemsRepeater`。要實作的只有一個方法:

```swift
func setLazyRows(
    ofSelectableListView listView: Widget,
    count: Int,
    estimatedRowHeight: Int,
    provider: @escaping (Int) -> (widget: Widget, height: Int)?
)
```

**兩個陷阱,兩個都是量出來的,請在寫之前讀:**

1. **回答高度問題時不可以呼叫 `provider`。** 表格會逐列問高度以算出清單長度;若靠建立該列來回答,
   第一次版面計算就會把一萬列全部建出來——正是本項所要避免的事。用 `estimatedRowHeight`,
   並只對「已經建過」的列記住真實高度。
2. **沒有識別碼的 row view 不會被回收,而那是一個先於本項就存在的洩漏。** AppKit 的
   `rowViewForRow` 每列都 `NSTableRowView()` 且不設 identifier:捲動時存活的 row view 從 30 變成
   **1,745**、行程從 104 MB 變成 225 MB。UIKit 是同一形狀的 `UITableViewCell()` 而非 `dequeue`。
   **eager 路徑把它藏住了**——同一份清單本來就要 423 MB,另外那 120 MB 不會有人注意到。
   GTK 與 WinUI 的等價處也要一併檢查。

驗收用 **P57**,它現在自己讀常駐記憶體(Darwin 用 `MACH_TASK_BASIC_INFO`、其餘用 `/proc/self/statm`
的**第二**個欄位——第一個是虛擬大小,在 64 位元行程上是數十 GB,看起來嚇人而毫無意義)。

## B. Android 現在編得過了,而那不是程式碼問題

先前每一次 `compile.zsh -android` 都以「module compiled with Swift 6.3.3 cannot be imported by the
Swift 6.4 compiler」失敗,而**第一個錯誤指名的是建置目錄裡一個過期的 `SwiftSyntax.swiftmodule`**
——那是症狀,不是成因。真正的成因是:主機 `swift` 是 6.4,安裝的 Android SDK 是
`swift-6.3.3-RELEASE_android.artifactbundle`。**而一個相符的 toolchain 一直都裝在
`~/Library/Developer/Toolchains` 裡。**

`testapp/compile.zsh` 現在會自己比對兩者版本、選用相符的 toolchain 並印出它選了哪一個;找不到時
會直接說出原因,而不是讓那面 module 格式錯誤的牆去當訊息。

**代價是五個 Android backend 檔案被寫出來、提交,卻從未被編譯過**(手勢、frame clock、accessibility
名稱、GraphicsAdapters、延遲列)。現在五個都編過了,而它們檔頭那句「此處未編譯」也一併更正為
「編得過,但沒有在裝置上跑過」——因為那兩件事不是同一件事。

## C. 自上次清單以來完成的其他項目

| 項目 | 狀態 |
| --- | --- |
| #123 accessibility 名稱 | AppKit / UIKit / Android 三份完成並驅動(P67:`plain label` / `padded label` / `two` /(空)) |
| #74 `-GPU` | 五個 backend 全部實作。AppKit/UIKit 走 Metal,Android 回報一張以 SoC 命名的介面卡(P68) |
| #28 Animation | `withAnimation` + 四種曲線 + `Color` 插值;P66 量到 0.5 秒補間產出 31 個相異值、29 個相異顏色 |
| `origin=popover` on AppKit | 完成。要**兩個**修正:事件要投給 popover 自己的視窗,且 `targetWindow()` 不能再回傳 popover(它會取得 key) |
| P50 popover 版面缺陷 | `updatePopover` 把 content view 的 frame 設成 `.zero`,覆蓋掉 AppKit 的置中,內容被釘在外殼左下角。外殼 314x180 對內容 288x154,那 26 點被整份推到上緣與右緣 |


---

## #123 accessibility(2026-09-16):AppKit / UIKit / Android 先落地,GTK 與 WinUI 同日完成(`9746bbeb`)

`BackendFeatures.Accessibility` 已存在,四個方法,**conformance 檢查**(未 conform 的 backend 只會
`warnOnce`,不會 `fatalError`),與 `ScrollingLists`、`LazyListRows` 同一種安排:

```swift
func setAccessibilityLabel(ofWidget widget: Widget, to label: String?)
func setAccessibilityHint(ofWidget widget: Widget, to hint: String?)
func setAccessibilityValue(ofWidget widget: Widget, to value: String?)
func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool)
```

AppKit / UIKit / Android 已實作並各自以外部探針驗過。**測試 app 是 P69**(新的;P67 不變,它問的是
另一個問題)。

**AppKit / UIKit / Android 上遇過、GTK 與 WinUI 也很可能遇到的三件事:**

| 陷阱 | 症狀 | 真正的原因 |
| --- | --- | --- |
| 在 `commit` 裡套用屬性 | modifier 看起來從未執行 | `updateButton` 在**下一幀的 `computeLayout`** 重寫標籤。屬性要在 `computeLayout` 裡、於子元件之後套用 |
| 從外面找「內層那個真正的元素」 | 標籤落在一個螢幕閱讀器不造訪的包裝上 | 平台的「這是不是無障礙元素」旗標預設為 false;而「唯一的控制項」在按鈕裡是**兩個** |
| 用 dump 工具驗 `hidden` | 被隱藏的文字看起來仍在 | Android 的 `uiautomator dump` 預設帶 `FLAG_INCLUDE_NOT_IMPORTANT_VIEWS`,要加 `--compressed` |

第三列對 WinUI 特別相關:**先確認檢視工具過濾的是什麼**,再下「沒生效」的結論。那一項在 Android 上
花掉的時間,全部花在一個正確的實作上。

GTK 側:`gtk_widget_set_tooltip_text` **不是** hint;`AtkObject` 的 `accessible-name` /
`accessible-description` 才是,而 GTK4 的 `gtk_accessible_update_property` 是抵達它的現代寫法
(`GTK_ACCESSIBLE_PROPERTY_LABEL` / `_DESCRIPTION`)。寫這段時無法在 Mac 上查它是否在 GTK 綁定裡;
GtkBackend 的 #123 已於 `9746bbeb` 實作。


---

## #122 focus(2026-09-16):AppKit / UIKit / Android 先落地,GTK(`38394d14`)與 WinUI(`ab2d1d51`)同日完成

`BackendFeatures.FocusableViews` 已存在,形狀與 `plan-focus-protocol.md` 議定的完全一致,**`focus` 回傳
`Bool`**,採 conformance 檢查(未 conform 只 `warnOnce`)。AppKit / UIKit / Android 已實作,**測試 app
是 P70**。

**WinUI 那一格當初唯一沒解的衝突:`FocusManager.TryFocusAsync` 是非同步的,而 `focus` 是同步的。**
當時從 Mac 得到的資料點是:`focus` 的回傳值**真的被用到**——P70 的 `@FocusState` 在被拒絕時會把
屬性寫回 `false`,那是畫面上看得見的一列,所以「同步回傳一個猜測的 `true`」會是最糟的選項。
**已解,形狀不變:** WinUIBackend 用的是同步、回傳 `Bool` 的 `UIElement.focus(_:)`(`ab2d1d51`)。

**AppKit / UIKit / Android 上遇過、GTK 與 WinUI 也很可能遇到的三個坑:**

| 陷阱 | 症狀 | 真正的原因 |
| --- | --- | --- |
| 把 handler 裝在 **widget** 上 | 焦點明明移動了,handler 從不觸發 | widget 是容器;平台的「焦點改變」回呼只為它被裝上的那個 view 觸發。要裝在**視窗/樹**那一層(AppKit:`NSWindow` 的 first responder;Android:`ViewTreeObserver.OnGlobalFocusChangeListener`) |
| 每一幀重建 observer | 改變被**靜默**吞掉 | 這段從 `computeLayout` 跑,每幀都跑;新 observer 的基準值取自當下狀態,於是拿改變跟自己比。要保留 observer、只換 handler |
| 相信 `.disabled(true)` 會擋住焦點 | 被停用的控制項拿得到鍵盤,Tab 落在上面且什麼都不做 | `.disabled` 走 environment,設在外層包裝上;responder 搜尋會越過它走到內層仍然啟用的控制項 |

第一列與第二列**都不會報錯**,而且都會產生一個看起來完全正常的畫面。P70 之所以同時顯示「焦點在哪裡」
與「被告知過幾次」,就是為了讓它們現形:計數器停在 0 而游標看得見,就是第一列。
