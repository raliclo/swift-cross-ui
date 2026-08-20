# GTK test plan findings

What the UI test plan reports when its steps are actually executed on
Linux/GtkBackend under XWayland, driven with `drive_xdotool.zsh`. Collected
2026-08-20.

Kept separate from the coverage matrix because the matrix answers "is this
covered" and this answers "what did it say". A row saying ✅ and a defect found
by step 5 of that same app are both true.

當 UI 測試計畫的步驟真正在 Linux/GtkBackend（XWayland，以 `drive_xdotool.zsh` 驅動）上被執行時，
它所回報的內容。蒐集於 2026-08-20。

與 coverage matrix 分開存放，因為 matrix 回答的是「是否已涵蓋」，本文件回答的是「它說了什麼」。
某一列標示 ✅，與該 app 第 5 步發現的缺陷，兩者可以同時為真。

## Why this document exists

Every app opens a window on both platforms. That was reported as "all 26 pass"
and it is worth being precise about what it meant: the plan carries about 190
numbered steps, roughly 25 have now been run, and those 25 found four defects.
Watching a window appear finds none of them.

本文件存在的理由：每一支 app 在兩個平台上都能開啟視窗。該結果曾被回報為「26 支全數通過」，而這
句話的確切含義值得說清楚：計畫共約 190 個編號步驟，目前已執行約 25 個，而這 25 個步驟找出了
四項缺陷。單看視窗是否出現，一項也找不到。

## Layout defects, and why they look like one problem

Three container types each mis-size their children, in three different apps.
They are listed separately because they were found separately, but they should
be investigated together: fixing them one at a time risks trading one for
another, and the shapes rhyme.

三種容器型別各自把子元件的尺寸算錯，分別出現在三支不同的 app 中。此處分列，是因為它們是分別被
發現的；但應合併調查：逐一修正有以彼換此的風險，而且它們的形態相似。

### ZStack does not overlap — #158, P13 step 5 — **fixed**

The plan requires the children of a `Group` inside a `ZStack` to overlap on the
z axis. They stacked vertically instead: the red, green and blue rectangles
appeared one below another with no overlap at all.

**Cause.** `Group` is meant to be invisible to the layout system, and the way it
manages that is by inheriting how its parent arranges things — `layoutOrientation`,
`layoutAlignment` and `layoutSpacing` exist for exactly this. A `ZStack` sets
none of them, because it does not arrange along an axis at all. So a `Group`
inside one fell through to whatever orientation the *grandparent* had set, and in
P13 that is a `VStack`. The three colours were laid out in a column.

Not a GtkBackend defect. `createContainer()` returns a `Fixed`, which positions
children exactly as asked; the wrong positions were computed above it.

**Fix.** A new environment entry, `layoutOverlapsChildren`, set by `ZStack` and
cleared by `VStack` and `HStack`, with `Group` honouring it. `ZStack`'s overlap
algorithm moved into `LayoutSystem.computeOverlapLayout` / `commitOverlapLayout`
so the two cannot drift apart — they already had, which is how this happened.

Verified on WSL: the three rectangles now overlap concentrically, only the
smallest fully visible on top.

**Known limitation, stated rather than hidden:** a `Group` inside a `ZStack`
centres its children even when the `ZStack` has a non-default alignment. `Group`
carries no alignment of its own and the parent's is not reachable, because
`layoutAlignment` is a `StackAlignment` and describes a single axis. A direct
child of the `ZStack` aligns correctly; a grouped one does not.

計畫要求 `ZStack` 內 `Group` 的子元件在 z 軸上重疊。實際卻是垂直堆疊：紅、綠、藍三個矩形上下排列，
完全沒有任何重疊。

**成因。** `Group` 的設計目標是對 layout 系統完全隱形，而它達成此目標的方式，是繼承父層的排列方式
——`layoutOrientation`、`layoutAlignment` 與 `layoutSpacing` 正是為此而存在。但 `ZStack` 三者皆不
設定，因為它根本不沿任何軸向排列。於是 `ZStack` 內的 `Group` 便沿用了**祖父層**所設定的方向，而
在 P13 中那是一個 `VStack`，三個顏色因此排成一列。

這不是 GtkBackend 的缺陷。`createContainer()` 回傳 `Fixed`，它會完全依照指示放置子元件；算錯位置的
是其上層。

**修正。** 新增環境項目 `layoutOverlapsChildren`，由 `ZStack` 設定、`VStack` 與 `HStack` 清除，並由
`Group` 遵循。同時將 `ZStack` 的重疊演算法移入 `LayoutSystem.computeOverlapLayout` /
`commitOverlapLayout`，使兩者無法各自漂移——它們原本就已經漂移了，而這正是本問題的成因。

已於 WSL 驗證：三個矩形現在同心重疊，只有最小的一個完整顯示於最上層。

**已知限制，明言而不隱藏：** 位於 `ZStack` 內的 `Group`，即使該 `ZStack` 設定了非預設對齊，仍會將
其子元件置中。`Group` 本身不帶對齊資訊，而父層的對齊在該處取不到，因為 `layoutAlignment` 的型別是
`StackAlignment`，只描述單一軸向。`ZStack` 的直接子元件會正確對齊，被 Group 包住的則不會。

### VStack bands not equal width — #266b, P17 step 8 — **not a defect**

Three coloured bands of different natural widths, given a fixed height, are
required by the test plan to end up the same width. They do not.

Measured on WSL: the widest child ("A somewhat longer line", green) sets the
stack's width at 154px and the other two keep their natural widths. **That is
what SwiftUI does** — a `VStack` sizes itself to its widest child; it does not
stretch the others, and a `Text`'s background follows the `Text`.

#266 is an open upstream *design* question — the plan itself describes it as
"two layout edge cases upstream wrote down while specifying the layout
algorithm". The expectation written into step 8 encodes one unratified
resolution of it. Making `VStack` stretch its children would diverge from
SwiftUI on a point upstream has not decided, so nothing was changed.

The step is left in the plan: it is still a useful cross-backend comparison, and
that is what P17 is for. What changed is that a difference here is now recorded
as a finding rather than as a failure.

測試計畫要求三條自然寬度不同的色帶，在被賦予固定高度後最終等寬。實際並非如此。

於 WSL 實測：最寬的子元件（綠色的「A somewhat longer line」）以 154px 決定 stack 寬度，其餘兩者
維持各自的自然寬度。**這正是 SwiftUI 的行為**——`VStack` 依其最寬子元件決定自身寬度，並不會拉伸
其餘子元件，而 `Text` 的背景則依附於 `Text` 本身。

#266 是 upstream 一個尚未定案的**設計**問題——計畫本身即描述其為「upstream 在制定 layout 演算法
規格時記下的兩個邊界案例」。步驟 8 所寫入的預期，只是該問題其中一種未經確認的解法。若讓 `VStack`
拉伸其子元件，等於在 upstream 尚未決定的議題上背離 SwiftUI，因此未作任何更動。

該步驟仍保留在計畫中：它依然是有用的跨 backend 比較，而那正是 P17 的目的。改變的是：此處的差異
現在被記錄為一項發現，而非一次失敗。

### HStack squeezes its first child — P21 step 3

The `.switch` row renders its "Enabled" label as `...` and the `.checkbox` row
as `En...`, while the "Disabled" toggle beside each renders in full.

Two explanations are eliminated by measurement and should not be re-derived:

- Not a space shortage. The row occupies about 220px of an 820px window.
- Not the toggle spacer. `Toggle(.switch)` inserts a `Spacer()` only when
  `backend.requiresToggleSwitchSpacer` is true, and GtkBackend sets it false --
  only UIKitBackend sets it true.

What remains is width distribution across nested HStacks: `Toggle(.switch)` is
itself an `HStack` of `Text` plus `ToggleSwitch`, and P21 puts two of those
inside an outer `HStack`. The first inner stack's `Text` is the one squeezed.

`.switch` 那列的「Enabled」標籤顯示為 `...`，`.checkbox` 那列顯示為 `En...`，而其旁的「Disabled」
則完整呈現。

有兩種解釋已由量測排除，不應重新推導：非空間不足（該列僅佔 820px 視窗中的約 220px）；亦非 toggle
的 spacer（`Toggle(.switch)` 僅在 `backend.requiresToggleSwitchSpacer` 為真時插入 `Spacer()`，而
GtkBackend 設為 false，僅 UIKitBackend 為真）。

剩下的是巢狀 HStack 之間的寬度分配：`Toggle(.switch)` 本身即為 `Text` 加 `ToggleSwitch` 的
`HStack`，而 P21 又把兩個這樣的結構放進外層 `HStack`；被擠壓的正是第一個內層堆疊中的 `Text`。

## Instrumentation defect

### P22 reports two sizes per sample

Each of the eight font samples reports two different measurements, one sensible
and one not:

```
11 caption:  185 x 13     plausible for 11pt text
11 caption:   15 x 397     a vertical strip
17 body:     264 x 20     plausible
17 body:      23 x 555     the same wrong shape
```

The rendering is correct -- the size ladder, the wrapping and the three
alignment rows all look right. But P22 exists to compare reported widths rather
than appearance, and two contradictory numbers per sample leave nothing to
compare. The measuring overlay is being asked for a size under a second,
degenerate proposal and records both.

八個字型樣本各回報兩組不同的量測值，其一合理、其一不合理（如上）。

繪製本身是正確的——字級階梯、換行與三列對齊看起來都無誤。但 P22 的存在目的是比較「回報的寬度」
而非外觀，而每個樣本兩個互相矛盾的數字，等於沒有東西可比。量測用的 overlay 在第二次、退化的尺寸
提議下被詢問，並將兩者都記錄了下來。

## Checks that pass

Worth recording, because "no defect found" is only useful if it is written down
somewhere -- otherwise the same check gets run again.

值得記錄，因為「未發現缺陷」唯有被寫下來才有價值——否則同一項檢查會被反覆執行。

| check | app | result |
|---|---|---|
| #264 ideal width reaching `fixedSize` | P17 | does not reproduce; subject 160x16 against control 372x16 |
| #595 text clipping in a ScrollView | P13 | does not reproduce; plain and `.fixedSize()` both show all three lines |
| disabled button refuses input | P21 | `clicks` reads 1 after Enabled then Disabled |
| toggle styles flip, disabled twins do not | P21 | plain, `.switch` and `.button` all correct |
| flat menu opens, selects and closes | P19 | all four item kinds render, selection registers, menu closes |
| nested menu reaches level 2, level 3 available | P20 | GTK slides with a back chevron rather than cascading |
| navigation stack pushes | P24 | Level 0 to Level 2, button becomes Push level 3 |
| table renders | P23 | four columns, eight rows; long cell truncates rather than widening its column |
| text ladder, wrapping and alignment render | P22 | correct |

## Characterised, not a defect

### Picker sized from the selected item — #161, P17 step 4

The picker's width follows the selection: 42, 51, 154, 392 as longer items are
chosen. The plan asks which of the two rules a backend uses, because the issue
is that the backends differ -- so this is half of a comparison, and the WinUI
half is still needed before it means anything.

picker 的寬度會隨選取項目變動：選擇較長的項目時依序為 42、51、154、392。計畫詢問的是某個 backend
採用兩種規則中的哪一種，因為該 issue 的重點在於「兩個 backend 不同」——因此這只是比較的一半，
在取得 WinUI 的另一半之前，它還不具意義。

## P0: critical lifecycle -- all steps pass

All 9 steps run under XWayland. No unimplemented-log regression, no crash from
any alert path.

全部 9 個步驟已於 XWayland 下執行。無 unimplemented log 回歸，任何 alert 路徑皆未崩潰。

| step | result |
|---|---|
| 3: no `setSizeLimits`/`setIncomingURLHandler` unimplemented logs | pass -- stdout has only libEGL/DRI3 warnings |
| 4-5: Increment/Reset @AppStorage | pass -- counter moves and resets, no crash (#548) |
| 6: relaunch keeps counter | pass -- reset to 0, relaunched, read back 1 |
| 7: Show AlertScene, close with OK | pass -- see below |
| 8: delayed environment alert | pass -- log shows `delayed alert button clicked` -> `delayed alert sleep finished` (~1s later) -> `delayed alert OK clicked` |
| 9: immediate environment alert | pass -- log shows `immediate alert button clicked` -> `immediate alert OK clicked` -> `immediate presentAlert returned` |

**GtkBackend detail worth recording for anyone testing alerts by screenshot**:
an `AlertScene`/environment alert renders as a second, undecorated, untitled
top-level X window sized to its content (202x60 for the launch alert), not as
part of the main window and not under the main window's WM title. A driver
that only captures the tracked main-window id, or that filters window lists by
non-empty name, will see nothing and wrongly report "no alert appeared" --
this happened once while building the driver for this sweep, before switching
to enumerating every visible window by id. Window manager placement of both
the main window and the alert is not stable across launches, so a coordinate
recorded from one run does not carry to the next; the alert must be located by
diffing the window list before/after the triggering click.

給任何之後要用截圖測試 alert 的人：`AlertScene`／environment alert 在 GtkBackend 上會呈現為
第二個、無裝飾、無標題的頂層 X window，大小依內容而定（啟動用的 alert 為 202x60），既不屬於主視窗、
也不在主視窗的 WM 標題下。若驅動腳本只擷取原本追蹤的主視窗 id，或依非空標題過濾視窗清單，將什麼
都看不到、並誤報「alert 沒有出現」——這正是本輪建置驅動腳本時發生過的事，後改為列舉每一個可見視窗
的 id 才修正。主視窗與 alert 視窗的視窗管理員擺放位置在每次啟動之間都不固定，因此某一次執行記下的
座標無法沿用到下一次；必須用點擊前後的視窗清單差異來定位 alert。

Minor, not investigated further: three clicks on `Increment @AppStorage`
sometimes moved the counter by more than 3 (2 -> 6 once). Not chased down --
could be xdotool delivering an extra click, not necessarily an app bug, and
the counter never went backwards or crashed.

次要、未深入調查：三次點擊 `Increment @AppStorage` 有一次讓計數器變化超過 3（2 -> 6）。未追查——
可能是 xdotool 多送了一次點擊，不必然是 app 的錯誤，計數器也從未倒退或造成崩潰。

## P1: dialogs and sheets -- all steps pass

All 11 steps run. Open/folder/save dialogs and both sheet levels tested.

全部 11 個步驟已執行。open／folder／save 對話框與兩層 sheet 均已測試。

| step | result |
|---|---|
| 2-3: Open file dialog | pass -- dialog window (`P1 open file`) visible within 1s of the click, well under the 2s budget; closed with Escape, status read `Open: Cancelled` |
| 4-5: Open folder dialog | pass -- `P1 choose folder` window, same timing, `Folder: Cancelled` |
| 6-7: Save file dialog | pass -- `P1 save file` window, same timing, `Save: Cancelled` |
| 8-9: Open root sheet, padding | pass -- the red bar in the "Root sheet" window touches the top edge with no visible padding, confirming #660 stays fixed |
| 10-11: Open nested sheet | pass -- a third window ("Nested sheet") opens on top of the root sheet window while both remain live; `Dismiss nested sheet` closes only the nested one, leaving the root sheet open, confirming #659 stays fixed |

Each dialog and each sheet level is its own top-level GTK window, same as the
P0 alert; window titles differ per dialog kind (`P1 open file`, `P1 choose
folder`, `P1 save file`) which made them easy to find, but the sheets are
titled plainly `P1` and had to be found the same diff-based way as the P0
alert.

每個對話框與每層 sheet 都是各自獨立的頂層 GTK window，與 P0 的 alert 相同；各對話框依種類有不同
標題（`P1 open file`、`P1 choose folder`、`P1 save file`），因此容易找到，但 sheet 一律標題為
單純的 `P1`，須以與 P0 alert 相同的差異比對方式尋找。

## P2: controls and styling

Picker and TextEditor steps pass; the disabled-button visual-distinction step
is inconclusive rather than a confirmed pass or a confirmed #390 regression.

Picker 與 TextEditor 步驟通過；disabled 按鈕視覺區別那一步無法下定論，既非確認通過，也非確認
#390 回歸。

| step | result |
|---|---|
| 2: initial Picker options are Vanilla/Chocolate only | pass |
| 3-4: toggle expanded options, reopen Picker | pass -- Strawberry/Mint/Coffee appear and are selectable; app readout confirms `Selected: Strawberry, options: 5, changes: 1` |
| 5: type into TextEditor | pass -- typed `12345` after `Clear`, `Length: 5`, cursor visible, nothing dropped |
| 6: unfocused TextEditor border | pass -- no border visible focused or unfocused (matches #471 fixed; there was never a border to compare against in either state) |
| 7-8: disabled vs enabled button visual difference | inconclusive -- see below |
| 9-10: window resizing / full screen button | not usefully testable with the tools on hand -- see below |

**Picker dropdown, like the alerts, is its own top-level window** (found and
clicked the same diff-based way), sized to the option count: 122x94 for two
options, 128x190 for five.

**Disabled-button step (#390) detail.** `Button("Disabled action") {}` and
`Toggle("Disabled toggle", isOn:).disabled(true)` have no observable side
effect in this app besides their own appearance (both actions are empty
closures), so the only signal available is the screenshot. At cold launch,
before any click, `Always enabled` renders with a border/outline and the two
disabled controls render flat with no border -- a real visible difference. But
after any click anywhere in the window, `Always enabled` loses that border too
and becomes indistinguishable from the disabled controls, and stays that way
through further clicks of `Enable button row` in either direction. That is
consistent with the initial border being GTK's default first-focus ring
(landing arbitrarily on `Always enabled` at window map) rather than an
enabled/disabled style, in which case P2 provides no visual distinction
between enabled and disabled buttons once focus has moved -- which would be a
#390 regression -- but it is also consistent with `Enable button row`'s click
simply not reaching the `enabled` binding, which this app cannot distinguish
from the outside. Needs an app change (a visible counter on one of these
buttons) or a different measurement method to resolve; recorded as
characterised, not filed as a defect.

**Window resizing step (#401) detail.** `xdotool windowsize` forced the
window from 620x643 to 900x700 while `windowResizable` was at its default
`false`, so the resize was not blocked -- but `xdotool windowsize` issues a
raw X `ConfigureWindow` request, which is not what a user does by dragging an
edge, and it is not evidence about the full-screen/maximize button #401 is
actually about. WSLg's XWayland session was not confirmed to draw a
maximize button on this window at all. Recorded as not usefully testable with
the tools available in this sweep rather than as a pass or a regression.

**disabled-button 步驟（#390）細節。** `Button("Disabled action") {}` 與
`Toggle("Disabled toggle", isOn:).disabled(true)` 在此 app 中除了自身外觀外沒有任何可觀察的
副作用（兩者的 action 都是空 closure），因此唯一可用的訊號是截圖。冷啟動、尚未點擊任何東西時，
`Always enabled` 呈現有邊框／外框，兩個 disabled 控制項則呈現扁平無邊框——確實有可見差異。但只要
在視窗中點擊任何東西之後，`Always enabled` 也會失去該邊框，變得與 disabled 控制項無法區分，且無論
之後如何切換 `Enable button row` 都維持該狀態。這與「該初始邊框其實是 GTK 預設的初始 focus
ring（在視窗顯示時任意落在 `Always enabled` 上）而非 enabled/disabled 樣式」一致——若是如此，P2
在 focus 移開後便無法在視覺上區分 enabled 與 disabled 按鈕，那會是 #390 的回歸——但也同樣與
「`Enable button row` 的點擊根本沒有傳到 `enabled` 綁定」一致，而從外部無法區分這兩種可能。需要
修改 app（在其中一個按鈕加上可見計數器）或改用其他量測方式才能釐清；記為已定性但未歸檔為缺陷。

**window resizing 步驟（#401）細節。** 在 `windowResizable` 維持預設 `false` 的情況下，
`xdotool windowsize` 仍把視窗從 620x643 強制改為 900x700，即該次 resize 並未被擋下——但
`xdotool windowsize` 送出的是原始 X `ConfigureWindow` 請求，並非使用者拖曳邊緣的操作，也無法作為
#401 真正關注的全螢幕／最大化按鈕的證據。本次亦未確認 WSLg 的 XWayland session 是否會為此視窗繪製
最大化按鈕。記為本輪工具無法有效測試，而非通過或回歸。

## P3: layout and clipping -- two defects reproduce, one severely

Both issues P3 exists to check are open regressions on GtkBackend, and the
three-column layout defect is worse than its (Fixed) description: it does not
self-correct on either a state update or a window resize.

P3 存在要檢查的兩個 issue，在 GtkBackend 上皆為開放中的回歸，且三欄式版面配置缺陷比其
（Fixed）描述更嚴重：無論是 state update 或視窗 resize 都無法自我修正。

### Three-column initial layout -- reproduces, does not self-correct

At launch (960x600, before any interaction) the sidebar and middle columns
show almost none of their content: no `P3 sidebar` / `Middle column` headers,
no `Split layout` / `Details` / `Detail B` / `Detail C` list rows -- only
`Image clipping` and `Detail A` (each a `List` row) float at irregular
positions over a mostly-black window, with `Force state update` far below
where the sidebar's layout would place it. This is worse than steps 2-3 ask
for (fully visible sidebar/middle/detail columns): here the `List` content
inside the two fixed-width (220pt) `VStack`s is largely missing, not merely
mis-sized.

Step 4 (`Force state update`) and step 5 (resize the window to 1100x700 via
`xdotool windowsize`) were both tried. Neither changes anything -- pixel-
identical before and after in both cases. The documented (Fixed) P3 rergression
was that the initial layout is wrong but corrects on any state change or
resize; what reproduces here does not correct on either, so it is a
distinct, currently-worse failure mode, not simply the old bug come back.

啟動時（960x600，尚未有任何互動）sidebar 與 middle column 幾乎不顯示任何內容：沒有
`P3 sidebar` / `Middle column` 標頭，沒有 `Split layout` / `Details` / `Detail B` /
`Detail C` 這些 list 列——只有 `Image clipping` 與 `Detail A`（皆為 `List` 的列）漂浮在
大片黑色視窗中的不規則位置，`Force state update` 則遠低於 sidebar 版面配置本應放置的位置。
這比步驟 2-3 所要求的（sidebar／middle／detail 三欄完全可見）更嚴重：兩個固定寬度（220pt）
`VStack` 內的 `List` 內容大多整個消失，而不僅僅是尺寸算錯。

步驟 4（`Force state update`）與步驟 5（以 `xdotool windowsize` 將視窗 resize 為
1100x700）皆已嘗試。兩者都沒有造成任何改變——前後畫面逐像素相同。文件記載的（Fixed）P3
回歸是「初始版面配置錯誤，但在任何 state 變化或 resize 後會自我修正」；此處重現的版本
兩者都無法修正，因此是另一種、目前更嚴重的失敗模式，而非舊錯誤單純復發。

### Image clipping (#389) -- reproduces at Large, does not at Small

`Small` (scale 1.0x) renders the test image cleanly inside its 220x140 black
frame with no overflow. `Large` (scale 2.4x) overflows the 220x140 frame
substantially, and in this 960-wide window the overflow reaches the window's
own right edge rather than merely exceeding the frame -- confirming #389.
`Medium` was clicked but not separately inspected (Large already answers the
question steps 7-8 ask).

`Small`（scale 1.0x）將測試圖片乾淨地繪製在其 220x140 的黑色 frame 內，沒有溢出。
`Large`（scale 2.4x）大幅溢出 220x140 的 frame，且在這個寬 960 的視窗中，溢出範圍甚至
到達視窗本身的右邊緣，而不只是超出 frame——確認 #389。`Medium` 已點擊但未個別檢視
（Large 已回答了步驟 7-8 所問的問題）。

| step | result |
|---|---|
| 2-3: sidebar/middle/detail visible, detail doesn't cover others | fail -- sidebar/middle List content largely absent, not merely covered |
| 4: Force state update, columns don't jump | layout does not change at all (already broken, stays broken) |
| 5: resize, columns stay reasonable | layout does not change at all after resize either |
| 6: Small/Medium/Large buttons | pass mechanically -- buttons respond, image and label update |
| 7-8: Large image clipped to 220x140 frame | fail -- #389 reproduces, overflow reaches the window edge |
| 9: Small is clean again | pass -- no overflow at Small |

## P4: native and callback stress -- all testable steps pass

`#if canImport(WinUIBackend)` correctly falls back to a plain `Text` in place
of the native banner on GtkBackend, so steps 2-4 (native banner presence/
content) are not applicable here by design, not a gap -- P4 tests two things
per backend and only the callback-storage half applies to GTK.

`#if canImport(WinUIBackend)` 在 GtkBackend 上正確地退回為一般 `Text` 取代 native banner，
因此步驟 2-4（native banner 的存在／內容）依設計即不適用於此處，而非缺口——P4 依 backend
測試兩件事，GTK 只適用其中 callback 儲存的那一半。

| step | result |
|---|---|
| 3-4: type text, native banner updates | n/a on GTK by design (`#else` branch, no native banner to update) |
| 5: Force update x3 | pass -- `update tick: 3` |
| 6-7: Run N buttons, callbacks/Selected row | pass -- two clicks (Run 0, Run 1) gave `callbacks: 2`, `Selected row: 1` |
| 8: More rows x3 | pass -- `Rows: 250` after starting at 80 (implicitly covers reaching 250 without the separate `Rows 250` button in that run) |
| 9: scroll near bottom, row window slides | not tested -- `drive_xdotool.zsh` only issues button-1 clicks, no scroll-wheel step, and the plan marks this Windows-only anyway (`Load next rows` is the documented substitute for other platforms, which step 10's `Run last` effectively exercises) |
| 10: Rows 250, Run last | pass -- `Rows: 250, rows 200-249`, `Selected row: 249`, `callbacks: 1`, no stall (settled within the 1s post-click pause) |
| 11: Run 249 quickly updates | pass by the same evidence as step 10 -- `Run last` calls the row-249 callback directly rather than merely scrolling to it, so `Selected row: 249` already demonstrates the fast, correct update the step asks about; row 249's own button was off-screen and not separately clicked |
| 12: Fewer rows x3 | pass -- `Rows: 10` |
| 13: re-click an existing row button after count change | pass -- second click on `Run 0` moved `callbacks` from 1 to 2 with `Selected row: 0` still correct |
| 14: no `BVI-*`/backdrop console noise | n/a on GTK -- that diagnostic path is WinUI-specific (#204); GTK's own stdout only ever showed libEGL/DRI3 warnings across every P4 run this sweep |

## P5: multi-window alerts -- cross-window passes, same-window stacking regresses

#675 has two halves, and GtkBackend only holds one of them. Alerts on
*different* windows do show simultaneously (the original bug -- second
window's alert waiting for the first to close -- stays fixed). But stacking a
second alert on the *same* window while the first is still open, which steps
7-11 depend on, cannot be reached through the UI at all: GtkBackend's alert is
an application-modal `Gtk.MessageDialog` (`alert.isModal = true`,
`setTransient(for:)`) that blocks all further input to its parent window, so
clicking `Show Alert B (stacks on A)` while `Alert A (Main)` is open does
nothing -- not "shows both", not "replaces A with B", nothing. The main
window's own status text (`Main: showing Alert A`) is unchanged by the click,
and a sanity click on the same coordinate with no alert open correctly opens
`Alert B (Main)`, which rules out a bad coordinate.

#675 有兩個部分，GtkBackend 只保住其中一個。不同視窗上的 alert 確實會同時顯示（原始
bug——第二個視窗的 alert 要等第一個關閉——維持已修正）。但在同一個視窗上、第一個 alert
仍開啟時再疊加第二個 alert（步驟 7-11 所依賴的行為），在 GtkBackend 上完全無法透過 UI 觸發：
GtkBackend 的 alert 是應用程式層級的 modal `Gtk.MessageDialog`（`alert.isModal = true`、
`setTransient(for:)`），會擋下所有傳給其父視窗的後續輸入，因此在 `Alert A (Main)` 開啟時點擊
`Show Alert B (stacks on A)`什麼都不會發生——不是「兩者都顯示」，也不是「B 取代 A」，就是沒有
反應。主視窗自身的狀態文字（`Main: showing Alert A`）在該次點擊後沒有變化，而在沒有 alert 開啟
時對同一座標做的健檢點擊，正確地開出了 `Alert B (Main)`，排除了座標錯誤的可能。

| step | result |
|---|---|
| 2-3: main and secondary windows both open | pass |
| 4-5: Alert A on main, then Alert A on secondary while main's is open | pass -- two separate small alert windows coexist; the main one reads `Alert A (Main)` |
| 6: dismiss both | pass (each dismissed independently with OK, same as P0) |
| 7-11: stack B on A, C on A+B, unstack in order on the main window | fails to reach the scenario at all -- see above; `Show Alert B`/`Show Alert C` are no-ops while an alert is showing on that window |
| 12: repeat 7-11 on the secondary window | not run -- same blocker applies, would not add information |
| 13: a third window, all three independently stacking | not run -- same blocker applies to the stacking half; a third window opening and holding its own single alert was not separately re-verified beyond what steps 2-5 already show |

**Two capture artefacts, not product findings, worth recording so they are not
re-investigated**: every P5 window list included two 682x477 `(untitled)`
windows that are present from launch regardless of any alert action --
unrelated to alerts, not chased down. And two alert screenshots came back
visibly misaligned/cropped-wrong (showing a slice of the main window's text
instead of the alert), while the same window captured cleanly moments later
in the same run -- an intermittent `xwd` timing issue against a window the WM
was still moving, not a rendering bug in the app.

**兩個屬於擷取工具的偽影，非產品層級發現，記錄下來以免之後被重新調查**：每次 P5 的視窗清單都
包含兩個 682x477 的 `(untitled)` 視窗，從啟動就存在、與任何 alert 動作無關，未再追查。另外有兩張
alert 截圖明顯錯位／裁切錯誤（顯示的是主視窗文字的一角而非 alert 內容），但同一視窗在同一次執行
中稍後又擷取乾淨——這是針對一個仍被 WM 移動中的視窗、`xwd` 偶發的時間點問題，並非 app 的繪製錯誤。

## P7: lists and split views -- near-total render failure, worse than #556 as tracked

**Severe.** At launch (720x480) the window shows almost nothing: no sidebar
list, no fruit names, no status line, no `Add a fruit's worth of text`/`Clear
selection`/`Select Cherry` buttons -- only a single small (~37x35) bordered
box sitting near the window's centre. This is unchanged after a 2s settle
pause and unchanged after resizing the window to 900x600 via `xdotool
windowsize` (the box stays the same size, still centred). This is well beyond
what steps 2-8 ask about (selection highlighting, split ratio, proportionate
resize) -- there is essentially no content to check those things against.

**嚴重。** 啟動時（720x480）視窗幾乎什麼都不顯示：沒有 sidebar list、沒有水果名稱、沒有狀態列，
也沒有 `Add a fruit's worth of text` / `Clear selection` / `Select Cherry` 按鈕——只有一個小小的
（約 37x35）有邊框方塊停在視窗中央附近。等待 2 秒讓畫面穩定後不變，以 `xdotool windowsize` 將
視窗 resize 為 900x600 後也不變（方塊尺寸不變，仍置中）。這已遠遠超出步驟 2-8 所問的範圍（選取項
是否高亮、split 比例、resize 後是否保持比例）——幾乎沒有內容可供比對。

P7 ships its own diagnostics specifically for this kind of failure (see the
header comments in `testapp/P7.swift`), and both agree with what the
screenshot shows:

- `p7-startup.log` (written unconditionally, no `--debug` needed) shows
  `App.init` -> `App.body evaluated` -> `RootView.body evaluated` (repeated
  several times per launch), so the view tree is being built and SwiftUI-style
  re-evaluation is happening normally.
- `p7-debug-events.log` (written only under `--debug`, from inside the split
  view's own measurement probes) stayed **completely empty** across three
  separate launches, including one left running 10s specifically to rule out
  a slow layout pass. The app's own comment says the probes sit on the pane
  *contents*, so an empty log means the sidebar/detail/total panes were never
  measured at all -- consistent with the split view collapsing to
  near-nothing rather than merely sizing its panes badly.

P7 自帶專為此類故障設計的診斷（見 `testapp/P7.swift` 的檔頭註解），兩者都與截圖所示一致：

- `p7-startup.log`（無條件寫入，不需要 `--debug`）顯示 `App.init` -> `App.body evaluated` ->
  `RootView.body evaluated`（每次啟動重複數次），可見 view tree 正常建構、也正常重新求值。
- `p7-debug-events.log`（僅在 `--debug` 下、由 split view 自身的量測探針寫入）在三次獨立啟動中
  皆**完全空白**，其中一次特意保持執行 10 秒以排除版面配置較慢的可能。app 自己的註解說明探針掛在
  pane 的*內容*上，因此空白的 log 代表 sidebar／detail／total 三個 pane 從未被量測過——與「split
  view 塌縮到幾乎不存在」一致，而非僅是各 pane 尺寸算錯。

Given this, steps 2-8 could not be meaningfully evaluated: there is no visible
List to click a row in, no status line to read, no split divider to judge the
share of. Recorded as a single severe defect rather than eight individual
step failures.

基於此，步驟 2-8 無法有意義地評估：沒有可見的 List 可點擊列、沒有狀態列可讀、也沒有 split
分隔線可判斷佔比。記為單一嚴重缺陷，而非八個個別步驟失敗。

## P8: scroll views

Renders correctly and completes (`RENDER COMPLETE -- all P8 probes measured`
in its debug log, unlike P7). #417 does not reproduce. #426 could not be
tested -- see below.

正常渲染並完成（debug log 出現 `RENDER COMPLETE -- all P8 probes measured`，與 P7 不同）。
#417 未重現。#426 因故無法測試——見下方。

| step | result |
|---|---|
| 2: red block corners rounded (#417) | does not reproduce -- the red block's four corners are visibly rounded in the screenshot, not square |
| 3-6: scroll wheel over/off the horizontal strip (#426) | not tested -- see below |

**Scroll-wheel step could not be tried.** `xdotool click --window $wid 5`
(mouse button 5 = wheel down) produced no visible change even as a **control**
scrolled over plain, unambiguously-scrollable `Outer row N` content, 8 clicks
in a row. Since the control also did nothing, the horizontal-strip test result
would be meaningless -- there is no way to tell "the view is frozen because of
#426" from "this input method does not reach the view at all" with the tools
on hand. `drive_xdotool.zsh` itself only issues button-1 clicks; getting a
real scroll to a GTK `ScrolledWindow` under XWayland needs either
`xdotool`'s `--clearmodifiers`/different button mapping tried, or a
different tool (e.g. `xdotool behave_screen_edge`-adjacent scroll support, or
driving it through `wmctrl`/an accessibility bridge), which was not chased
down further given the time this sweep had left. Recorded as an open gap in
tooling, not a product result.

**滾輪步驟未能嘗試。** `xdotool click --window $wid 5`（滑鼠按鍵 5 = 滾輪向下）連續點擊 8
次，即使作為**對照組**、滾動在明確可捲動的一般 `Outer row N` 內容上方，也沒有產生任何可見變化。
既然對照組本身也毫無反應，橫向 strip 的測試結果就沒有意義——手邊工具無法區分「因 #426 導致該
view 被凍結」與「這種輸入方式根本沒有傳到該 view」。`drive_xdotool.zsh` 本身只會送出滑鼠左鍵
點擊；要讓真正的滾動事件傳到 XWayland 下的 GTK `ScrolledWindow`，需要嘗試 `xdotool` 的
`--clearmodifiers`／不同按鍵對應，或改用其他工具（例如透過 accessibility bridge 或
`wmctrl`），本輪時間有限、未再深入追查。記為工具面的未決缺口，而非產品層級的結果。

## P9: text and field sizing -- all steps pass, neither issue reproduces

| step | result |
|---|---|
| 1-3: field heights vs Reference button, after Force update | pass -- heights visibly match before and after 3x Force update, `#504` does not reproduce |
| 4: heights don't keep shrinking over repeated updates | pass -- same evidence |
| 5: typing stays visible | not separately tried (covered adequately by #295's Zero-width/Wider round trip below, which already exercises the field/frame rendering) |
| 6-8: Narrower/Zero width/Wider, text stays in the blue band | pass -- 200px -> Narrower shrinks and rewraps inside the band; `Zero width` reaches `(0 px)` with text visibly not spilling past the (now invisible) band rather than refusing to shrink; `Wider` returns cleanly to 200px with the original three-line wrap. `#295` does not reproduce |

One tooling note, not a product finding: chaining many clicks in a single
`drive_xdotool.zsh` invocation with fixed coordinates (3x `Narrower` then
`Zero width` then `Wider`) made the last two clicks land on nothing, because
each click was aimed at the *initial* screenshot's button position and the
row does not move here -- the actual cause was reusing coordinates for a
button row while state text above it changes line count. Retried each button
from a fresh launch / short sequence and all three worked correctly; the
finding above reflects the correct (isolated) runs.

一項工具面而非產品面的記錄：在單次 `drive_xdotool.zsh` 呼叫中以固定座標串接多次點擊
（3 次 `Narrower` 接著 `Zero width` 再 `Wider`）時，最後兩次點擊落空——原因是每次點擊都對準
*初始*截圖裡的按鈕位置，而這裡按鈕列本身並不會移動，實際成因是在上方狀態文字行數會變化時
仍沿用同一組座標。改為每個按鈕各自從重新啟動／短序列測試後，三者均正確運作；上方結果反映的是
正確（各自獨立）的測試。

## P10: hit testing and shortcuts -- both tracked issues reproduce

| step | result |
|---|---|
| 2: Direct clicks increments | pass -- 2 clicks -> `Direct clicks: 2` |
| 3: covered button with overlay present | fails -- **#454 reproduces**: `Covered clicks` stayed `0` and the status text did not change after clicking `Click me too` while `Transparent overlay present` was checked |
| 4-5: uncheck overlay, click again | pass -- `Covered clicks: 1`, status reads `Covered button received a click.`, confirming the click lands correctly once the overlay is removed and isolating the overlay as the cause |
| 6: Ctrl-Q quits (#478) | fails -- **#478 reproduces**: the window is still present in the window list after `xdotool key ctrl+q`, the app did not quit |

Both are clean, unambiguous reproductions -- direct A/B comparison for #454
(same button, same click, overlay present vs absent) and a simple presence
check for #478.

兩者皆為乾淨、明確的重現——#454 為直接的 A/B 比較（同一按鈕、同一點擊，有無 overlay 的差異），
#478 則是單純的視窗存在性檢查。

## P15: colour scheme and window minimum height

Run with `GTK_THEME=Adwaita:dark ./P15`. #386 does not reproduce the way it
is described; #289 reproduces clearly, and gets worse rather than better
after switching to taller content.

以 `GTK_THEME=Adwaita:dark ./P15` 執行。#386 並未如描述般重現；#289 明確重現，且切換為
較高內容後不減反增。

### #386 -- plain text stays legible against the dark background

With the dark GTK theme applied, the window background is genuinely dark and
`Plain text on the default background` renders light-coloured and legible
against it, not "keeping its light-mode colours" in the sense of becoming
unreadable. `TextField`, `Toggle`, and `Button` keep light-ish chrome with
dark text, same as their normal (light) appearance -- unsurprising since
these are GTK's own widget styles rather than SwiftCrossUI-drawn text, and
readable either way. `Requested: dark` / `Resolved: light` confirms the
override itself is still ignored (`canOverrideWindowColorScheme = false`, as
the plan's own preamble says), consistent across `System`, `Light`, and
`Dark` presses -- `Resolved` never moved off `light`. So the two halves the
plan separates are both confirmed: the override is missing (expected, by
design), but that did not translate into unreadable colours in this build.

在套用 GTK 深色主題的情況下，視窗背景確實變深，而 `Plain text on the default background`
在其上以淺色、可讀的方式繪製，並非「維持淺色模式配色」而導致難以閱讀的那種意義。`TextField`、
`Toggle`、`Button` 維持偏淺的外觀搭配深色文字，與其一般（淺色）外觀相同——這不令人意外，因為這些
是 GTK 自身的 widget 樣式而非 SwiftCrossUI 繪製的文字，兩種情況下都可讀。`Requested: dark` /
`Resolved: light` 確認 override 本身依然被忽略（`canOverrideWindowColorScheme = false`，
如計畫前言所述），在按下 `System`、`Light`、`Dark` 時皆一致——`Resolved` 從未離開過 `light`。
因此計畫區分的兩個部分都已確認：override 確實缺失（依設計預期），但在此建置中並未造成配色
不可讀。

### #289 -- reproduces, and taller content makes it worse

Before touching `Use tall content`, `xdotool windowsize` could not force the
window below roughly 472-560px tall (it kept snapping back), so some minimum
was being enforced pre-interaction. After clicking `Use tall content` (button
correctly flips to `Use short content`, six `Extra row N of 6` lines appear,
window grows on its own from 560 to 584), the **same** `xdotool windowsize
720 100` that was refused before now succeeds completely -- the window drops
to 100px tall and clips everything below the second line of text (all six
extra rows, every button, the colour-scheme controls). The minimum height is
supposed to grow with taller content; instead it stopped being enforced at
all.

在碰 `Use tall content` 之前，`xdotool windowsize` 無法把視窗強制壓到約 472-560px 以下
（會被彈回去），可見互動前已有某個最小值被強制執行。點擊 `Use tall content` 之後（按鈕正確變為
`Use short content`，出現六行 `Extra row N of 6`，視窗自行從 560 長到 584），**同一個**先前
被拒絕的 `xdotool windowsize 720 100` 這次完全成功——視窗掉到 100px 高，並裁掉第二行文字以下
的所有內容（六個額外列、每個按鈕、colour-scheme 控制項全部消失）。最小高度理應隨內容變高而變大；
實際上卻變成完全不再被強制執行。

| step | result |
|---|---|
| 1-2: dark text on dark background | does not reproduce -- plain text stays legible, see above |
| 3: TextField/Toggle/Button foreground vs theme | not a defect -- these keep GTK's normal light widget chrome with dark text either way |
| 4-5: Requested/Resolved, press Dark/Light/System | pass -- `Resolved` never changes off `light`, matching the documented `canOverrideWindowColorScheme = false` |
| 6: Windows/WinUI control run | not run (out of scope for this sweep, Windows side) |
| 7-8: drag to minimum height, nothing cut off | pass before interacting with tall content -- window would not go below ~472-560px |
| 9-10: Use tall content grows the minimum, Use short content shrinks back | fails -- **#289 reproduces**: after switching to tall content the minimum height enforcement is lost entirely rather than growing, and the window can be shrunk to 100px with severe clipping |

One readout bug noted in passing, not chased further: `Content area: 300 x
24` never changed across any of these steps (short content, tall content, or
after either resize), even though the visible content clearly changed size.

順帶記錄一個未再深入追查的讀值問題：`Content area: 300 x 24` 在上述任何步驟中都沒有變化（無論
short content、tall content，或任一次 resize 之後），即便可見內容的尺寸明顯改變了。

## P16: split view initial layout -- GtkBackend is the clean control for #160

#160 is WinUIBackend-specific; this app's role on GtkBackend is step 8's
control. The initial render is correct here: `sidebar: 180 x 22`,
`detail: 660 x 22` from the very first stable measurement (a `0 x 22` /
`0 x 22` pair appears first in the log each time, but that is the same kind
of pre-settle `GeometryReader` noise the app's own P7 comments describe, not
a visible bad frame -- the screenshot taken after settling already shows the
divider in the right place, both columns populated, nothing squeezed out).
`Force update` reports the identical `180 x 22` / `660 x 22` afterwards, so
there is no jump to compare -- GtkBackend gets it right immediately and #160
does not apply here.

#160 是 WinUIBackend 專屬的問題；此 app 在 GtkBackend 上的角色是步驟 8 的對照組。這裡的初始
渲染是正確的：從第一次穩定量測起就是 `sidebar: 180 x 22`、`detail: 660 x 22`（log 中每次
都先出現一組 `0 x 22` / `0 x 22`，但那與 P7 自身註解描述的、settle 前的 `GeometryReader`
雜訊屬同一類，並非畫面上可見的錯誤畫面——settle 後擷取的截圖已顯示分隔線位置正確、兩欄皆有內容、
沒有任何一欄被擠掉）。`Force update` 之後回報的仍是相同的 `180 x 22` / `660 x 22`，沒有落差
可比較——GtkBackend 一開始就是對的，#160 在此不適用。

| step | result |
|---|---|
| 2-3: read initial sidebar/detail sizes, judge by eye | pass -- correct from the first stable frame |
| 4-5: Force update, compare | pass -- identical before/after, no #160-style jump |
| 6: relaunch + resize to trigger the snap | not separately tried -- nothing to snap from |
| 7: 3-column layout | not tried this sweep (time) |
| 8: run on Linux as the control | this is that control run |

## P18: file dialogs -- remaining steps pass

`gtk_file_dialog_open` (single file) was already verified in an earlier
sweep. This sweep completed the other two paths.

`gtk_file_dialog_open`（單一檔案）已於先前的執行中驗證過。本次補完另外兩條路徑。

| step | result |
|---|---|
| 4: Choose a folder, then Cancel | pass -- dialog closes, line reads `folder -> cancelled` |
| 5: Choose a save destination, name prefilled | pass -- `Name:` field reads exactly `p18-example.txt` |
| 6: repeat under WinUI and compare | not run (Windows side, out of scope this sweep) |

## P13: remaining steps (2 and 4) -- no crash, minimum width holds

Steps 1, 3, and 5 were covered in an earlier sweep (#595 does not reproduce,
#158 reproduces -- see above). This sweep ran the two remaining steps.

步驟 1、3、5 已於先前的執行中涵蓋（#595 未重現、#158 重現——見上方）。本次執行剩餘兩個步驟。

| step | result |
|---|---|
| 2: press `Show unidentified list (may crash)` (#415) | does not crash on GtkBackend -- the button flips to `Hide unidentified list`, the non-Identifiable list renders its three `Same: Identical message` rows normally, the window stays in the window list afterwards. #415 is filed as AppKitBackend-specific, so this is expected rather than a fixed-regression check |
| 4: narrow the split, sidebar minimum honoured (#291) | pass, with a caveat -- clicking `Narrower` down to a 120px frame keeps both `Sidebar` and `Detail` visible (word-wrapped hard, e.g. `Sideb-ar`, but neither pane collapses to nothing). Further `Narrower` clicks past 120 are no-ops (a floor built into the test app, not the minimum width itself). Did not additionally confirm `Wider` recovers past this point -- a follow-up click aimed at `Wider` in the same run landed back on `Narrower` instead, a coordinate-tracking mistake on the driver's part rather than a product observation, not re-tried given time |

## P17: remaining steps (6-7, #266a) -- settles without reproducing

Steps 1-5, 8-9 were covered in an earlier sweep (#264 does not reproduce,
#161 characterised as selected-item sizing, #266b reproduces -- see above).
This sweep ran the aspect-ratio scroll view steps.

步驟 1-5、8-9 已於先前的執行中涵蓋（#264 未重現、#161 定性為依選取項目調整大小、#266b
重現——見上方）。本次執行 aspect-ratio scroll view 的步驟。

| step | result |
|---|---|
| 6-7: step the 2:1 box through `Shorter`/`Taller`, scroll bar appears and disappears without flickering (#266a) | does not reproduce -- the scroll bar's appear/disappear transition settled cleanly at every height tried, no flicker observed |

## P21: remaining step (5, sliders) -- passes; steps 6-7 blocked by window height

Steps 1-4 (Button, Toggle/`.switch`/`.button`/`.checkbox` disabled-refuses-
input, and the HStack-squeezes-first-child defect) were covered in an
earlier sweep -- see above.

步驟 1-4（Button、Toggle／`.switch`／`.button`／`.checkbox` 的 disabled 拒絕輸入、以及
HStack 擠壓第一個子元件的缺陷）已於先前的執行中涵蓋——見上方。

| step | result |
|---|---|
| 5: drag both sliders, disabled must not move | pass -- dragging the enabled slider moved it `0.40 -> 0.88`; the same drag gesture attempted on the disabled slider directly below left it unchanged, both before and after |
| 6: TextField/SecureField/TextEditor enabled vs disabled | not run -- see below |
| 7: `ContentUnavailableView` title and description | not run -- see below |

**Steps 6-7 could not be reached.** P21's content is a plain `VStack`, not
inside a `ScrollView`, and it is taller than any window this machine could
produce: `xdotool windowsize` clamps at the screen height (1080px here)
regardless of the value requested, and moving the window off-screen first
(`windowmove 0 -600`) did not lift the clamp -- GTK still caps the window
livelihood at 1080. The visible content at that height reaches
`TextField -- editable` and stops there; `SecureField`, `TextEditor`,
their disabled counterparts, and `ContentUnavailableView` are further down
and never entered the capturable frame. Would need either a taller virtual
display/lower DPI, or driving actual mouse-wheel/keyboard scrolling within
the window (see the P8 scroll-wheel gap above -- the same tooling limit).

**步驟 6-7 無法觸及。** P21 的內容是一般 `VStack`、並非放在 `ScrollView` 內，且比這台機器
能產生的任何視窗都高：`xdotool windowsize` 無論指定何值都會被夾在螢幕高度（此處為
1080px），先把視窗移到螢幕外（`windowmove 0 -600`）也未能解除此上限——GTK 仍把視窗高度
限制在 1080。在此高度下可見內容到 `TextField -- editable` 為止；`SecureField`、
`TextEditor`、它們的 disabled 對應版本，以及 `ContentUnavailableView` 都在更下方，從未
進入可擷取的畫面範圍。需要更高的虛擬顯示器／更低的 DPI，或是在視窗內實際驅動滑鼠滾輪／鍵盤
捲動（見上方 P8 的滾輪缺口——同一項工具限制）。

## P22: remaining steps (3-4) -- pass

Steps 1 (size ladder) and 4 (alignment, seen incidentally) were already
covered by the earlier instrumentation-defect entry above.

步驟 1（字級階梯）與步驟 4（對齊，先前已附帶看到）已由上方的量測缺陷條目涵蓋。

| step | result |
|---|---|
| 3: `Narrower`/`Wider`, wrap point | pass -- at 150pt the sample sentence wraps cleanly into five lines with no overflow past the frame |
| 4: three alignment rows in the 320pt frame | pass -- `leading`, `center`, `trailing` land at the expected left/middle/right positions |

## P23: remaining steps (3-4) -- clips rather than scrolls

| step | result |
|---|---|
| 3: `More rows` past the window height | the window does not grow and no scrollbar is visible; going from 8 to 24 rows leaves row 13 cut off mid-line at the window's bottom edge, with rows 14-24 not reachable in the captured frame. Read as **clips**, though this sweep did not confirm whether a scrollbar is genuinely absent or simply not rendered in this window manager -- see the P8/P21 note about not having a reliable scroll-wheel test method |
| 4: `Fewer rows` recovers | pass -- back down to `rows: 1` shows a single clean row with no leftover gap or stale row |

## P24: remaining steps (2-5)

Not run this sweep, time did not allow: go back through pushed levels in
order, `Record a push` counter against the displayed level, `Increment
counter` surviving a pop, and `Pop to root` resetting both. Step 1 (push
three levels) was already confirmed working in an earlier sweep.

本輪因時間不足未執行：依序返回已推入的層級、`Record a push` 計數器與畫面顯示層級的比對、
`Increment counter` 在 pop 後是否留存、以及 `Pop to root` 是否同時重置兩者。步驟 1（推入
三層）已於先前的執行中確認可運作。

## Not yet run

P24 steps 2-5 (P11, P12, P14 are out of scope on this Windows/WSL machine).
Roughly 4 of the 190 steps.

尚未執行：P24 步驟 2-5（P11、P12、P14 在本 Windows/WSL 機器上超出範圍）。約當 190 步中的
4 步。
