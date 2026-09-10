# 給 Windows 端的佇列 — 2026-09-10

由 Mac 端整理。**每一列都附上這台機器上查得到的證據,或明說它是待決定而非待實作。**
先讀第 0 節,它會影響你接下來要碰的檔案。

Compiled on the Mac side. Every row carries evidence checkable from this
machine, or says plainly that it is a decision rather than a task. Read section
0 first -- it changes which files you can touch.

---

## 0. 先做這件事:rebase,`GridLayoutPlan` 已改名

**#118 已落地,而它動的是你被綠燈允許改名的那個型別。** 若你手上有動到 grid 的分支,先 rebase。

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

## 1. 要你決定的(不是要你寫程式)

### ~~1a. #127 走哪一條路~~ — **已答、已實作,只剩你們編一次**

你們的答覆(`gtk_widget_translate_coordinates` 在已安裝標頭裡、`transformToVisual` 同步且 throws)
定案了路線 (b)。`BackendFeatures.WidgetGeometry.originInWindow(ofWidget:)` 已落地,五個 backend 都寫了。

**要你們做的只有兩件事**:

| 檔案 | 唯一要查的東西 |
| --- | --- |
| `Sources/GtkBackend/GtkBackend+WidgetGeometry.swift` | `graphene_point_t` 在此處是否一如 `Sources/Gtk/Widgets/ScrolledWindow.swift` 那樣經由 `CGtk` 可見。**其餘每一個呼叫該檔都已經在做** |
| `Sources/WinUIBackend/WinUIBackend+WidgetGeometry.swift` | `widget.xamlRoot?.content` 是不是這個 backend 取視窗內容的正確寫法(形狀對、名字未必) |

GTK 那份刻意**不用** `gtk_widget_get_root`——它回傳 `GtkRoot*`(介面),而把它轉成 `GtkWidget*`
是這裡唯一沒有人能在 Mac 上查證的一步。改成用 `gtk_widget_get_parent` 一路往上走,兩個函式收發的
都是 `GtkWidget*`,沒有轉型。

**Android 那份也請順手看一下**(`AndroidBackend+WidgetGeometry.swift`):這台機器的 Android SDK 模組是
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
`testapp/plan/plan-focus-protocol.md`。**該檔已於 2026-09-10 更正一處我方誤判**:我曾寫「GTK 的
`grabFocus` 必須先產生出來」,那是錯的——`Sources/Gtk` 到處直接呼叫 C 符號,`gtk_widget_grab_focus`
今天就能寫。**這條不再卡在程式碼產生。**

仍要你回答的只有一件:`FocusManager.TryFocusAsync` 是非同步的,而協定裡的 `focus` 是同步的。
若非同步不可,形狀要改。

### 1c. #109 popover `arrowEdge` 分工

Mac 端的提案:你做 SwiftCrossUI 那層 + Gtk + WinUI,我做 AppKit / UIKit / Android。等你點頭。

### 1d. #125 `Table` 的 `selection` 與 `sortOrder`

欄寬你已完成。剩下兩項需要 **backend → view 的事件回報**,而 `BackendFeatures.Tables` 目前是單向的。
這與 #122 的 `setFocusChangeHandler` 是同一個形狀問題,值得一起定。

---

## 2. 要你寫的程式(Mac 端編不了那兩格)

### 2a. #28 Animation 的 GTK 與 WinUI 時鐘

查證過:`CADisplayLink` / `CVDisplayLink` / `Timer.scheduled` 在整個 `Sources/` 是 **0 命中**,
所以五個 backend 都還沒有 per-frame 時鐘。Mac 端會定協定形狀並做 AppKit / UIKit / Android。

**GTK 那一格不缺 API**:`gtk_widget_add_tick_callback` 已經被直接呼叫——
`Sources/Gtk/Widgets/NV12GLView.swift:248`,連 thread 規則都已寫在該檔註解裡。
WinUI 對應的是 `CompositionTarget.Rendering`。

### 2b. #32 手勢的 Gtk 實作

`GestureDrag` / `GestureZoom` / `GestureRotate` 三個類別**你已經產好了**
(`Sources/Gtk/Generated/GestureDrag.swift` 等)。Mac 端做 AppKit / UIKit / Android 三份,
協定形狀會先送過來對。

### 2c. #79 GTK 39px

仍在。`GtkBackend.swift:1282` 的 `titlebarAllowance` 只在 `decorationProbe == "3"` 時非 0,
因此每次正常執行都少 39px。已定案為 (c):繼續挖「present 之前就能回報 frame 的 GTK 呼叫」,
不接受把 39px 寫成行為;走不通要帶著「試過哪些呼叫、各自回傳什麼」回報。

### 2d. P38 WinUI WebView

`00c9210e` 修了兩個真的成因(`EnsureCoreWebView2Async` 在 `isLoaded == false` 時被呼叫;
`IAsyncAction` 是區域變數、一回傳就被釋放),而該 commit 自述 **"The frame is still empty"**。
`results.csv2` 中最後一列 `windows,winui,P38` 仍是 2026-08-28。

---

## 3. 要你**驗**的(Mac 端改了共用程式碼,而我看不到你的畫面)

### 3a. #118 / #120 之後,GtkBackend 與 WinUIBackend 的 grid 有沒有跑掉

兩項都只動框架,理論上兩個 backend 不改一行就對。**「理論上」正是這棵樹一再抓到的那個詞。**
要看的是 P48(LazyVGrid 三節 + 新增的 LazyHGrid 兩節)與 P51(`Grid` 3x3 加一列 `gridCellColumns(3)`)。

Mac 端量到的數字,供你對照:

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

## 4. 兩個要你回答的量測問題

1. **#113 那個「48 顆按鈕時一次按壓約 0.3 秒」是在哪個 backend 上量的?** AppKit 上量到的是
   **min 10.5 ms / median 20.7 ms**,少了一個數量級以上。若那是 GTK 或 WinUI 的數字,那代表同一份
   版面程式碼在不同 backend 之間差 30 倍——那本身就是下一個要追的東西,而且方向與「優化版面」相反。
   完整結果在 `testapp/plan/plan-113-layout-cost.md`(四條 arm、五個尺寸、指數 n^0.95–0.96,
   **不是 n^1.5**)。

2. **P28 那份「一秒延遲」的回報是在哪台機器上?** macOS 上兩條路徑都量完了:真實滑鼠事件
   click→body 為**冷啟 16.0 ms、預熱後 2.9–9.9 ms**,合成路徑 0–2 ms、到像素 69 ms。沒有一條
   接近一秒。若那份回報來自 Windows,那要重量的是 Windows 那一側。
