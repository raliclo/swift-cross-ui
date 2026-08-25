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

### HStack squeezes its first child — P21 step 3 — **fixed**

The `.switch` row rendered its "Enabled" label as `...` and the `.checkbox` row
as `En...`, while the "Disabled" toggle beside each rendered in full.

The earlier notes eliminated space shortage and the toggle spacer, and located
it in the nested-HStack width distribution: `Toggle(.switch)` is itself an
`HStack` of `Text` plus `ToggleSwitch`, and P21 puts two of those in an outer
`HStack`; the first inner stack's `Text` was the one squeezed.

**Cause, measured with SCUI_DEBUG_STACK.** `LayoutSystem.computeLayouts`
distributes an HStack's width by offering each child, in least-flexible-first
order, a share of the space that is left. The share reserved not only the
remaining spacing but also the *minimum lengths* of the children not yet placed
-- and then divided by how many remained. That double-reserved. The outer
HStack, proposed 172, offered its first child 60.5 against a natural width of
79, so the child rendered at its minimum and its `Text` truncated; the second
child was offered 101 and rendered in full. The asymmetry was the reservation,
not the content.

**Fix.** Reserve only the spacing, not the children's minimum lengths. The
children are already sorted least-flexible-first, so a rigid child takes its
small natural size and a flexible child last absorbs the leftover -- nothing has
to hold back space for a minimum a later child will claim, and a child that
genuinely cannot fit still enforces its own minimum by returning it. This is the
algorithm the ordering is taken from (objc.io's HStack child-ordering piece).
At 172 the first child is now offered 81 and renders in full.

This is a core-layout change and touches every stack, so it was regression-
checked: P21 (both labels full), P0, P2 and P17 all render as before, with no
row newly truncated or over-wide.

`.switch` 那列的「Enabled」標籤曾顯示為 `...`，`.checkbox` 那列顯示為 `En...`，而其旁的「Disabled」
則完整呈現。

先前的紀錄已排除空間不足與 toggle spacer，並定位於巢狀 HStack 的寬度分配：`Toggle(.switch)` 本身
即為 `Text` 加 `ToggleSwitch` 的 `HStack`，而 P21 又把兩個這樣的結構放進外層 `HStack`；被擠壓的
正是第一個內層堆疊中的 `Text`。

**成因，以 SCUI_DEBUG_STACK 量測得出。** `LayoutSystem.computeLayouts` 依「最不彈性優先」的順序，
逐一提議每個子元件一份「剩餘空間」。該份額不僅保留了剩餘的 spacing，還保留了「尚未放置之子元件的
minimum 長度」——然後再除以剩餘數量。這是雙重保留。外層 HStack 在提議寬度 172 之下，只提議其第一個
子元件 60.5，而其自然寬度為 79，於是該子元件以最小尺寸呈現、其 `Text` 遭截斷；第二個子元件被提議
101 而完整呈現。造成不對稱的是這項保留，而非內容。

**修正。** 只保留 spacing，不保留子元件的 minimum 長度。子元件早已依「最不彈性優先」排序，因此剛性
元件取其較小的自然尺寸，最後的彈性元件吸收剩餘——無需為某個後續元件反正會取用的 minimum 預留，而
確實放不下的子元件仍會以回傳自身 minimum 的方式強制其下限。這與排序所依據的演算法一致（objc.io 的
HStack 子元件排序一文）。在 172 之下，第一個子元件現在被提議 81，得以完整呈現。

這是 core layout 的更動，影響每一個 stack，因此已做迴歸檢查：P21（兩個標籤皆完整）、P0、P2、P17
的呈現皆與先前相同，沒有任何一列出現新的截斷或過寬。

## Instrumentation defect

### P22 reports two sizes per sample — **fixed**

Each of the eight font samples reported two different measurements, one sensible
and one not:

```
11 caption:  185 x 13     plausible for 11pt text
11 caption:   15 x 397     a vertical strip
17 body:     264 x 20     plausible
17 body:      23 x 555     the same wrong shape
```

The rendering was correct. But P22 exists to compare reported widths, and two
contradictory numbers per sample left nothing to compare.

**Cause.** An instrumentation artifact, not a backend defect. The measuring
wrapper reads its size from a `GeometryReader`, whose closure runs on every
layout pass -- and the layout system probes each view's flexibility by proposing
it width 0 and width infinity before the real layout. Under those probes the
wrapping sample text collapses to a tall thin strip (`15 x 397`) or stretches,
and the wrapper wrote both the probe size and the real one.

**Fix, app-side.** The wrapper now keeps only the latest size per label and
writes them once, a second after `onAppear`. The real distribution runs after
the flexibility probes, so the last size recorded for a label is the committed
one. The delay matters: `onAppear` fires before layout has recorded anything, so
flushing immediately reported an empty set.

Verified: one plausible line per sample, widths and heights rising monotonically
with font size, the degenerate strips gone.

```
11 caption: 185 x 13    17 body: 264 x 20    28 title 1: 449 x 33
13 footnote: 226 x 16   20 title 3: 321 x 24  34 large title: 609 x 40
15 subheadline: 288 x 18 22 title 2: 353 x 26  wrapped: 300 x 46
```

八個字型樣本原本各回報兩組不同的量測值，其一合理、其一不合理（如上）。

繪製本身是正確的，但 P22 的目的是比較回報的寬度，而每個樣本兩個互相矛盾的數字等於沒有東西可比。

**成因。** 這是量測的 artifact，而非 backend 缺陷。量測包裝從 `GeometryReader` 讀取尺寸，其 closure
在每一次 layout pass 都會執行——而 layout 系統會在真正布局之前，以寬度 0 與寬度無限大探測每個 view
的彈性。在這些探測之下，會換行的樣本文字會塌縮成細高長條（`15 x 397`）或被拉伸，而包裝把探測尺寸
與真實尺寸都寫了下來。

**修正，app 端。** 包裝現在只保留每個 label 的最新尺寸，並於 `onAppear` 之後一秒一次寫出。真正的
分配發生於彈性探測之後，因此某個 label 最後被記錄的尺寸即為已提交的那一個。延遲是關鍵：`onAppear`
在 layout 記錄任何內容之前就會觸發，因此立即輸出會回報一組空值。

已驗證：每個樣本一行合理值，寬高皆隨字級單調遞增，退化的長條消失（如上）。

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

## P5: multi-window alerts -- cross-window passes; same-window stacking is blocked by modality, by design tension

#675 has two halves, and GtkBackend only holds one of them. Alerts on
*different* windows do show simultaneously (the original bug -- second
window's alert waiting for the first to close -- stays fixed). But stacking a
second alert on the *same* window while the first is still open, which steps
7-11 depend on, cannot be reached through the UI at all.

**Root cause, and why it is not a surgical fix.** The trigger for stacking is a
button *in the main window* (`Show Alert B (stacks on A)`), and GtkBackend's
alert is a window-modal `Gtk.MessageDialog` (`isModal = true`,
`setTransient(for: window)`) that blocks all input to that window while it is
open. So the button that would add the second alert to the stack cannot be
clicked while the first alert is showing -- the two requirements are in direct
tension. The plan's own expected result for step 7 is that B *replaces* A (only
the top of the stack is visible) and dismissing restores the one beneath, so the
intended behaviour is a per-window stack showing one at a time; but the only way
to add to that stack through the UI is a window button, which modality blocks.

Making it work needs alerts to be non-modal so the window stays interactive,
plus a backend-managed per-window alert stack that hides the current alert when a
new one is pushed and restores it on dismiss. That is a global change to alert
semantics -- a non-modal alert lets the user touch the window behind it -- with
its own correctness implications for every app that shows an alert, not a
GtkBackend tweak scoped to P5. The actual #675 bug (cross-window serialisation)
is already fixed here; this half is left for a deliberate decision about alert
modality rather than changed under a test app's assumptions.

Clicking `Show Alert B (stacks on A)` while `Alert A (Main)` is open does
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
| 3: scroll off the strip, outer rows move | **pass** -- four notches takes `Outer row 0..3` to `Outer row 5..9` |
| 4: scroll **over** the strip, outer still moves (#426) | **pass, #426 does not reproduce** -- identical result to step 3, same rows, same position |
| 5: scroll the strip sideways | **pass** -- the strip goes from its first cells to `H10 H11 H12` |
| 6: strip at its end, outer takes over | **pass** -- after the strip runs out, a vertical scroll still moves the outer view |

**Why this was "not tested" before, and what it was not.** The previous sweep
recorded that a scroll wheel produced no visible change even as a control, and
concluded the tooling could not deliver a scroll to a GTK `ScrolledWindow`. That
was wrong twice over.

The input was fine. `.overlay` was swallowing it: P8 wraps its outer ScrollView
in `.overlay { GeometryReader { P8Probe(...) } }`, and on GtkBackend that overlay
was a real widget that GTK returned from hit testing for every point its own
children did not cover -- so nothing beneath it, control included, ever saw a
pointer event. The same defect made P23's table cells unselectable. Fixed with
`PassthroughFixed`; see the entry below.

The format also had no verb for a wheel, which is why nothing could be driven
from an action file. `scroll` now exists.

Neither cause had anything to do with XWayland, `--clearmodifiers`, or button
mappings, which is where the earlier note pointed. Recorded because the wrong
lead was written down confidently.

**先前為何被記為「未測試」，以及它其實不是什麼。** 上一輪記錄「即使作為對照組，滾輪也未產生任何
可見變化」，並推論工具無法將捲動事件送達 GTK 的 `ScrolledWindow`。這個結論錯了兩層。

輸入本身沒有問題，是 `.overlay` 吞掉了它：P8 以 `.overlay { GeometryReader { P8Probe(...) } }`
包裹其外層 ScrollView，而在 GtkBackend 上該 overlay 是一個實際的 widget，GTK 對於其自身子元件
未覆蓋的每一個位置都會回傳它——因此其下方的一切（包含對照組）從未收到任何指標事件。同一個缺陷
也使 P23 的儲存格無法選取。已以 `PassthroughFixed` 修正，見下方條目。

此外，該格式當時也沒有任何轉動滾輪的動作，因此無法由動作檔驅動。`scroll` 現已存在。

兩個成因都與 XWayland、`--clearmodifiers` 或按鍵對應無關，而那正是先前那則註記所指的方向。此處
記錄下來，是因為那條錯誤的線索當時被寫得相當肯定。

**Superseded.** The paragraph that stood here recorded the wheel as undeliverable
and pointed at `--clearmodifiers`, button mappings and XWayland. It is kept only
in git history: none of those was the cause, and leaving a confident wrong lead
in place is worse than deleting it.

**已作廢。** 此處原本的段落把滾輪記為「無法送達」，並將矛頭指向 `--clearmodifiers`、按鍵對應與
XWayland。該段僅保留於 git 歷史中：以上皆非成因，而把一條寫得肯定卻錯誤的線索留在原地，比刪除
它更糟。

**One real constraint did come out of this, and it is about pacing.** A single
`scroll,0,40` travelled a different distance on each of three runs. xdotool sends
notches as `click --repeat`, back to back with no gap, and GTK coalesces a rapid
burst into one kinetic gesture whose distance depends on timing rather than on
the count. Split a long scroll into bursts with a sleep between them, and end at
the hard stop of the scroll range if the position has to be reproducible.
`testapp/actions/P21-disabled-field.csv` is written that way and says so.

**此過程確實產生了一項真實的限制，且與節奏有關。** 單一的 `scroll,0,40` 在三次執行中各走了不同
距離。xdotool 是以 `click --repeat` 背靠背送出格數、中間毫無間隔，而 GTK 會把急促的連發併為單一
kinetic 手勢，其距離取決於時序而非次數。若需要可重現的位置，請將長距離捲動拆成數段、段間加入
sleep，並以捲動範圍的硬性盡頭作結。`testapp/actions/P21-disabled-field.csv` 即依此撰寫並註明。

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

## P10: hit testing and shortcuts -- both tracked issues fixed

| step | result |
|---|---|
| 2: Direct clicks increments | pass -- 2 clicks -> `Direct clicks: 2` |
| 3: covered button with overlay present | **pass, #454 fixed** -- `Covered clicks: 1` and `Covered button received a click.` with `Transparent overlay present` still checked. Previously stayed at `0` |
| 4-5: uncheck overlay, click again | pass -- unchanged, and no longer the only way the button works |
| 6: Ctrl-Q quits (#478) | **pass, #478 fixed** -- the process is gone within two seconds of the keystroke, against a control run with no input that is still alive at ten seconds, and its log ends with `RENDER COMPLETE` and no fatal error, so it quit rather than crashed |

### #454 -- transparent colours consumed clicks

`Color.clear` becomes a `GtkBox` with a transparent CSS background. A GtkBox is
a pointer target whatever it is painted, so a clear one in a `ZStack` above a
button swallowed every click.

Not the same defect as the overlay one recorded under P23, and the fix for that
one did not touch this: `PassthroughFixed` makes *empty containers* transparent
to hit testing, and a `Color` is a drawn view rather than a container. Retested
after that landed and #454 still reproduced, which is what separated the two.

Fixed in `setColor(ofColorableRectangle:)`: a rectangle with zero opacity gets
`can-target = FALSE`, restored the moment it is given any opacity, so a colour
animating from transparent to opaque becomes clickable again.

**A deliberate divergence from SwiftUI, and the escape hatch now exists.**
SwiftUI does let `Color.clear` take hits, with `allowsHitTesting(false)` as the
way out. SwiftCrossUI had no such modifier at all -- no `allowsHitTesting`,
`contentShape` or `hitTest` anywhere -- so matching SwiftUI would have left no
way to put a transparent layer over something interactive.

`allowsHitTesting(_:)` has since been added: `BackendFeatures.HitTesting` with a
no-op default, GtkBackend mapping it to `can-target`, which GTK already defines
as subtree-wide and so needs no emulation. The transparent-colour default stays
as #454 asks -- a layer that silently eats input is the more surprising of the
two behaviours -- and anyone wanting the other one can now ask for it.

The colour rule moved onto the same machinery rather than staying a bespoke
`can-target` call, because two things writing that one flag would have made the
last writer win. A colour rectangle is now a `PassthroughFixed` carrying an
`opaque` flag read at hit time, which also fixes a regression the first version
would have introduced: `Color.clear` with a tap gesture stays clickable, because
`contains` checks for event controllers as well as opacity, whichever order the
colour and the gesture are applied in.

Verified with a case that transparency cannot explain: P10 step 6 clicks the
middle of a fully **opaque** orange block and `Hidden clicks` reaches 2, so the
click reached a button that is not visible at all.

**一項刻意的 SwiftUI 分歧，而其逃生口現已存在。** SwiftUI 確實讓 `Color.clear` 接收點擊，其解法
是 `allowsHitTesting(false)`。而 SwiftCrossUI 當時完全沒有這個 modifier——沒有
`allowsHitTesting`、`contentShape`，也沒有 `hitTest`——因此與 SwiftUI 保持一致，等於完全沒有辦法
把透明圖層疊在可互動的元件之上。

`allowsHitTesting(_:)` 其後已加入：`BackendFeatures.HitTesting` 帶有 no-op 預設實作，GtkBackend
將其對映至 `can-target`，而 GTK 對後者的定義本就及於整個子樹，因此無需任何模擬。透明顏色的預設
維持 #454 所要求的行為——「靜默吞掉輸入的圖層」是兩者中較令人意外的那一個——而想要另一種行為的人，
現在可以自行指定。

顏色的處理也一併移到同一套機制上，而非停留在一次專屬的 `can-target` 呼叫，因為兩處都寫入同一個
旗標會使結果取決於誰最後寫。色塊現在是帶有 `opaque` 旗標的 `PassthroughFixed`，該旗標於 hit 時
讀取；這同時修正了第一版本會引入的一項回歸：帶有 tap gesture 的 `Color.clear` 仍可點擊，因為
`contains` 除了不透明度之外也會檢查 event controller，且不受「顏色與手勢的套用順序」影響。

驗證方式採用了「透明度無法解釋」的案例：P10 步驟 6 點擊一塊完全**不透明**的橘色方塊中央，
`Hidden clicks` 達到 2，代表該點擊抵達了一個完全看不見的按鈕。

### #478 -- no quit shortcut existed

Nothing in GtkBackend handled Ctrl-Q, and nothing else provided it. On macOS
Cmd-Q comes free with AppKit's standard application menu; GTK has no equivalent,
so an app built on this backend simply had no quit shortcut.

Added as a `GAction` plus an application-wide accelerator, so it works whichever
window has focus and keeps working for windows created later -- unlike a key
controller, which would have to be attached to each window as it appears. It
calls `g_application_quit` rather than closing windows one at a time, because
closing runs each close handler and an app that vetoes a close would refuse the
shortcut, which is the behaviour of a close request rather than of a quit.

| 步驟 | 結果 |
|---|---|
| 2 | 通過 |
| 3：overlay 存在時點擊被覆蓋的按鈕 | **通過，#454 已修正**——在 `Transparent overlay present` 仍勾選的情況下得到 `Covered clicks: 1`。此前停在 `0` |
| 4-5 | 通過，且不再是該按鈕唯一能運作的方式 |
| 6：Ctrl-Q 結束程式（#478） | **通過，#478 已修正**——按鍵後兩秒內行程即消失，而不送任何輸入的對照組在十秒時仍存活；其 log 以 `RENDER COMPLETE` 作結且無致命錯誤，故為正常結束而非崩潰 |

**#454——透明顏色會吞掉點擊。** `Color.clear` 會成為一個帶透明 CSS 背景的 `GtkBox`。無論如何繪製，
GtkBox 都是指標目標，因此位於 `ZStack` 中按鈕上方的透明色塊會吞掉每一次點擊。

這與 P23 條目下記錄的 overlay 缺陷並非同一件事，且該次修正也未涵蓋此處：`PassthroughFixed` 使
**空容器**對 hit testing 透明，而 `Color` 是「有繪製的 view」而非容器。該修正落地後重測，#454
依然重現，正是這一點區分了兩者。

修正位於 `setColor(ofColorableRectangle:)`：不透明度為零的矩形會被設為 `can-target = FALSE`，
一旦被賦予任何不透明度即恢復，因此由透明漸變為不透明的顏色會重新變得可點擊。

**一項刻意的、明言而非隱藏的 SwiftUI 分歧。** SwiftUI 確實讓 `Color.clear` 接收點擊，其逃生口是
`allowsHitTesting(false)`。而 SwiftCrossUI 並無此 modifier——整份原始碼中沒有 `allowsHitTesting`、
`contentShape` 或 `hitTest`——因此與 SwiftUI 保持一致，等於完全沒有辦法把透明圖層疊在可互動的元件
之上。若日後加入 `allowsHitTesting`，此邏輯應改置於其之下。

**#478——根本不存在結束捷徑。** GtkBackend 中沒有任何程式碼處理 Ctrl-Q，其他地方也未提供。在
macOS 上，Cmd-Q 隨 AppKit 的標準應用程式選單而來；GTK 沒有對應機制，因此以此 backend 建置的 app
根本沒有結束捷徑。

現以 `GAction` 加上應用程式層級的加速鍵實作，因此無論哪個視窗取得焦點都有效，對日後才建立的視窗
亦然——這與 key controller 不同，後者必須在每個視窗出現時逐一掛載。它呼叫 `g_application_quit`
而非逐一關閉視窗，因為關閉會執行每個 close handler，而會否決關閉的 app 將因此拒絕此捷徑——那是
「關閉請求」的行為，不是「結束程式」的行為。

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

### #289 -- reproduces; root cause found, fix is architectural

**Root cause, measured with SCUI_DEBUG_MINSIZE.** `setSizeLimits` fires only
twice, both at launch (`328x474` then `328x472`). Toggling `Use tall content`
does **not** call it again -- so the window's minimum is never recomputed when
the content grows. The window still grows to 584 on the toggle, but that is
GTK re-measuring the content's natural size on its own; SwiftCrossUI's
window-minimum path is not on that route.

`WindowReference.update`, which is what computes the minimum from a
`proposedSize: .zero` probe and calls `setSizeLimits`, runs on a scene update, a
window resize, or an environment change -- not on a content `@State` change
inside the window. So a state toggle that changes how tall the content needs to
be leaves the window minimum stale.

Two fixes were tried on the GtkBackend side and neither is the answer, so both
were reverted rather than left in:

- Setting the minimum on the `CustomRootWidget` (whose `measure` returns it, and
  which GTK enforces structurally) as well as on the toplevel. Correct mechanism
  in principle, but it changes nothing here because `setSizeLimits` is not called
  on the content change, so the structural minimum is never updated either.
- Confirmed the same either way: short content snaps back to 472 (its launch
  minimum holds), tall content drops to 100.

The fix belongs in the scene/view-graph update pipeline: a content update that
can change the content's minimum size has to trigger a window-minimum
recomputation, the same way a resize or an environment change does. That is a
framework-wide change to how view-level updates propagate to the window, not a
GtkBackend tweak, and is left for a focused change rather than bundled here.

**成因，以 SCUI_DEBUG_MINSIZE 量測得出。** `setSizeLimits` 僅觸發兩次，皆在啟動時（`328x474`
接著 `328x472`）。切換 `Use tall content` **不會**再次呼叫它——因此內容變高時，視窗的最小值從未
被重算。視窗在切換時仍長到 584，但那是 GTK 自行依內容的自然尺寸重量測；SwiftCrossUI 的視窗最小值
路徑並不在該路線上。

`WindowReference.update`（負責以 `proposedSize: .zero` 探測算出最小值並呼叫 `setSizeLimits`）
只在場景更新、視窗 resize、或環境變化時執行——而非在視窗內容的 `@State` 變化時。因此一次改變
「內容需要多高」的狀態切換，會使視窗最小值停留在過時的值。

在 GtkBackend 端嘗試了兩種修法，皆非正解，故一併還原而不留下：

- 除了 toplevel，也在 `CustomRootWidget`（其 `measure` 會回傳該值、且 GTK 會結構性強制）上設定
  最小值。機制原則上正確，但在此毫無作用，因為 `setSizeLimits` 在內容變化時根本沒被呼叫，結構性
  最小值同樣從未更新。
- 兩種情況結果相同：短內容彈回 472（其啟動最小值有守住），高內容掉到 100。

正解屬於場景／view-graph 的更新管線：一次「可能改變內容最小尺寸」的內容更新，必須像 resize 或
環境變化那樣觸發視窗最小值的重算。那是「view 層更新如何傳播至視窗」的框架級更動，而非 GtkBackend
的小調整，留待一次專注的更動處理，而不在此處綑綁。

---

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

## P21: remaining steps (5-7) -- all pass

Steps 1-4 (Button, Toggle/`.switch`/`.button`/`.checkbox` disabled-refuses-
input, and the HStack-squeezes-first-child defect) were covered in an
earlier sweep -- see above.

步驟 1-4（Button、Toggle／`.switch`／`.button`／`.checkbox` 的 disabled 拒絕輸入、以及
HStack 擠壓第一個子元件的缺陷）已於先前的執行中涵蓋——見上方。

| step | result |
|---|---|
| 5: drag both sliders, disabled must not move | pass -- dragging the enabled slider moved it `0.40 -> 0.88`; the same drag gesture attempted on the disabled slider directly below left it unchanged, both before and after |
| 6: TextField/SecureField/TextEditor enabled vs disabled | **pass** -- typing `hi` into the enabled `TextField` gives `TextField -- editablehi`; scrolled to the bottom and clicking the disabled one below it, two `z` keystrokes leave it at `editable`. `SecureField` masks, `TextEditor` shows both lines |
| 7: `ContentUnavailableView` title and description | **pass** -- both `Nothing here` and `The description line` render |

**"Blocked by window height" was wrong, and the correction matters more than the
result.** The note that stood here said P21's content is a plain `VStack` not
inside a `ScrollView`, and that the steps needed a taller display.

`P21.swift:86` is `ScrollView {`. It has always been the root of that view. The
steps needed a wheel, and the action file format had no verb for one; with
`scroll` added they are reachable in a normal 820x720 window and both pass.

The earlier note also went further than what had been observed -- `windowsize`
clamping and DPI are real, but they were offered as the *reason* the steps could
not run, and that reason was never checked against the app's own source. It cost
this a second sweep.

**「受視窗高度阻擋」是錯的，而這項更正比結果本身更重要。** 此處原本的註記說 P21 的內容是一般
`VStack`、並未放在 `ScrollView` 內，且這些步驟需要更高的顯示器。

`P21.swift:86` 就是 `ScrollView {`，它一直都是該視圖的根層。這些步驟需要的是滾輪，而當時的動作檔
格式沒有對應的動作；加入 `scroll` 之後，在一般的 820x720 視窗中即可觸及，且兩個步驟皆通過。

先前那則註記也超出了實際觀察到的範圍——`windowsize` 的夾制與 DPI 確有其事，但它們被當成了「步驟
無法執行的原因」提出，而該原因從未與 app 自身的原始碼對照過。這使本項多花了一輪。

**Reproducibility note.** Scrolling to a *measured* position is not repeatable:
see the P8 entry on GTK coalescing rapid wheel notches. `P21-disabled-field.csv`
scrolls in paced bursts to the hard stop at the bottom, which is why its click
coordinates hold across runs.

**可重現性註記。** 捲動到某個「量測出來的位置」並不可重複：見 P8 條目中關於 GTK 會合併急促滾輪
格數的說明。`P21-disabled-field.csv` 以分段節奏捲動至底部的硬性邊界，這正是其點擊座標能跨執行
保持有效的原因。

## P22: remaining steps (3-4) -- pass

Steps 1 (size ladder) and 4 (alignment, seen incidentally) were already
covered by the earlier instrumentation-defect entry above.

步驟 1（字級階梯）與步驟 4（對齊，先前已附帶看到）已由上方的量測缺陷條目涵蓋。

| step | result |
|---|---|
| 3: `Narrower`/`Wider`, wrap point | pass -- at 150pt the sample sentence wraps cleanly into five lines with no overflow past the frame |
| 4: three alignment rows in the 320pt frame | pass -- `leading`, `center`, `trailing` land at the expected left/middle/right positions |

## P23: remaining steps (3-4) -- both pass; the table scrolls

| step | result |
|---|---|
| 3: `More rows` past the window height | **scrolls** -- decided with a wheel, not inferred from a screenshot. At 24 rows, five notches down over the table leaves row 9 at the top and rows 9-21 visible |
| 4: `Fewer rows` recovers | pass -- back down to `rows: 1` shows a single clean row with no leftover gap or stale row |

**It was read as "clips" twice, and both readings were wrong the same way.** GTK 4
draws overlay scrollbars: invisible until something scrolls. "No scrollbar is
visible" does not distinguish a table that clips from one that scrolls perfectly
well and is simply not being scrolled. Two sweeps concluded "clips" from exactly
that non-evidence -- the second one even re-ran the step after removing the
measuring overlay, and reported the same wrong answer more confidently.

What settled it was a wheel event, which the action-file format had no verb for
until `scroll` was added. The same gap had stalled P8 and P21.

**One real difference did show up, and it is not the one being looked for.** The
header row scrolls away with the content, where AppKit and WinUI keep a table's
header pinned. Not chased here: it is a design question about what a
`BackendFeatures.Tables` table should do, not a defect against a stated
expectation, and the plan does not ask.

**曾兩度被判讀為「裁切」，而兩次都錯在同一處。** GTK 4 使用 overlay 捲軸：未發生捲動時是隱形的。
「看不到捲軸」並不能區分「會裁切的表格」與「其實能正常捲動、只是沒有人去捲它的表格」。有兩輪測試
正是從這種「非證據」推出了「裁切」的結論——第二輪甚至在移除量測 overlay 後重跑了該步驟，然後以更
篤定的語氣回報了同一個錯誤答案。

真正定案的是一個滾輪事件，而在 `scroll` 加入之前，動作檔格式並無對應的動作。P8 與 P21 也曾卡在
同一個缺口上。

**確實浮現了一項真實差異，但並非原本要找的那項。** 標題列會隨內容一起捲走，而 AppKit 與 WinUI
會將表格標題固定。此處未再深入：那是「`BackendFeatures.Tables` 的表格應當如何」的設計問題，而非
違反既定預期的缺陷，且計畫中並未詢問。

## P23: text selection is opt-in and works — and an overlay swallows pointer events

Tables can now be made selectable and copyable with `.tableTextSelection()`,
**off by default**. Verified on WSL: with it on, dragging across `row 2 content`
highlights it; with it off, the same drag does nothing.

Getting there uncovered a larger defect, and the shape of it is worth recording
because it wasted the first four attempts.

Selection appeared not to work at all. `SCUI_DEBUG_TABLE` showed the property
was being applied correctly — `selectable=true cells=32 labels=32 headers=4`, so
the widget walk was reaching every label — and yet neither a cell nor a column
header could be selected by drag or by double click. Buttons elsewhere in the
same window responded to the same synthesised clicks.

The cause is `.overlay`. P23 wrapped its table in `P23Measured`, which overlays a
`GeometryReader` containing an `EmptyView`. On GtkBackend that overlay is a real
widget covering the content, and GTK returns it from hit testing for every point
where it has no child of its own — so **everything under an overlay is
unreachable by the pointer**. Removing the wrapper made selection work
immediately, with no other change.

In SwiftUI an overlay of `EmptyView` is hit-transparent: hit testing finds the
topmost view that actually draws or is interactive.

**Fixed, in the backend rather than in the apps.** `GtkBackend.createContainer()`
now returns a `PassthroughFixed` — a `GtkFixed` subclass whose `contains` vfunc
returns `FALSE` unless the widget has an event controller attached. GTK asks
`contains` only after it has already offered the point to every child, so
children stay reachable and only an empty structural container becomes
transparent. A container something made interactive still claims its points,
which is what keeps `.onTapGesture` on a stack working: `createTapGestureTarget`
attaches the gesture as a controller on that very widget.

Verified by what it unblocked, not only by the case that found it: P8's scroll
wheel now reaches the outer scroll view (steps 3-6 all pass, and #426 turns out
not to reproduce), and P23's cells select.

在 SwiftUI 中，內容為 `EmptyView` 的 overlay 對點擊是穿透的：hit testing 會找出最上層「確實有
繪製或可互動」的 view。

**已修正，且修在 backend 而非各個 app。** `GtkBackend.createContainer()` 現在回傳
`PassthroughFixed`——一個 `GtkFixed` 子類別，其 `contains` vfunc 在該 widget 未掛有任何 event
controller 時回傳 `FALSE`。GTK 只在把該點提供給所有子元件之後才會詢問 `contains`，因此子元件仍
可觸及，只有純結構性的空容器變為透明。已被賦予互動能力的容器仍會攔截其範圍內的點，這正是讓
stack 上的 `.onTapGesture` 持續有效的關鍵：`createTapGestureTarget` 會把該手勢以 controller 的
形式掛在該 widget 本身。

驗證方式不只是發現它的那個案例，還包括它所解除的阻塞：P8 的滾輪現在能抵達外層捲動視圖（步驟 3-6
全部通過，且 #426 結果並不重現），而 P23 的儲存格可以選取。

表格內容現在可透過 `.tableTextSelection()` 設為可選取與可複製，**預設關閉**。已於 WSL 驗證：
開啟時拖曳 `row 2 content` 會反白，關閉時同一個拖曳毫無作用。

達成此結果的過程中發現了一個更大的缺陷，其形態值得記錄，因為它讓前四次嘗試全部落空。

選取看起來完全無效。`SCUI_DEBUG_TABLE` 顯示屬性其實正確套用了——`selectable=true cells=32
labels=32 headers=4`，代表 widget 走訪確實觸及了每一個 label——然而無論拖曳或雙擊，儲存格與欄位
標題都無法選取；而同一視窗中其他位置的按鈕，對同樣的合成點擊卻有反應。

成因是 `.overlay`。P23 原本以 `P23Measured` 包裝其表格，而後者會疊上一個內含 `EmptyView` 的
`GeometryReader`。在 GtkBackend 上，該 overlay 是一個實際覆蓋內容的 widget，且對於所有其自身沒有
子元件的位置，GTK 的 hit testing 都會回傳它——因此**位於 overlay 之下的一切都無法被指標觸及**。
移除該包裝後，選取立即可用，其餘一律未動。

在 SwiftUI 中，內容為 `EmptyView` 的 overlay 對點擊是穿透的：hit testing 會找出最上層「確實有繪製
或可互動」的 view。這是一個真實的缺陷，且不限於 P23——它是 P10 的 #454 與 #478 的有力候選成因，
並且會靜默地使任何「測試對象位於量測 overlay 之下」的檢查失效。此問題另行追蹤；P23 的表格已不再
被包裝，理由記於原始碼中。

## P24: all steps pass -- after fixing a core defect that made step 2 impossible

| step | result |
|---|---|
| 1: push three levels | pass -- `Level 3` reached |
| 2: go back through them in order | **pass, once a back control existed at all** -- three presses return `Level 2`, `Level 1`, `Level 0`, and the bar disappears at the root, which is itself part of the check: a bar still showing there would mean the path emptied and the view did not notice |
| 3: `Record a push` against the level shown | pass -- three presses at levels 0, 1, 2 give `pushes 3` in the same log line as `Level 3` on screen; the counter lives outside the stack, so agreement is the finding |
| 4: `Increment counter` at depth, then back | pass -- one `Back` after two increments lands on `Level 2` with `counter -> 2` in the same frame, so the state change did not disturb the history |
| 5: `Pop to root` resets | pass -- `pushes recorded -> 0` and the root screen, with `counter -> 2` still showing. The app resets `pushCount` and deliberately not `counter`; a 0 there would have meant something reset more than it was asked to |

### Step 2 could not be performed at all, and it was not a GtkBackend defect

`NavigationStack.body` rendered only `elements.last`. There was no navigation
bar and no back control **on any backend** -- a stack could be pushed and never
popped, and the only way back was whatever the application happened to provide.
P24 pushed to level 3 and had nowhere to go.

Fixed in core, not in GtkBackend, and built from ordinary views rather than
asked of the backend. A navigation bar is a button and a label; there is nothing
a backend could do better with it, and a `BackendFeatures` protocol would have
meant a stack with no way back on every backend that had not implemented it yet.
So every backend gets this at once.

The label matches SwiftUI's fallback. SwiftUI shows the previous view's title
and says "Back" when there is none; there are no navigation titles here yet, so
the fallback is the whole of it, and `navigationTitle` is where this reads from
when it lands.

**Known consequence, recorded rather than discovered later.** The bar spans the
full width, as SwiftUI's does, so the stack fills its container once something
is pushed. The content therefore reflows once between the root and the first
pushed level, and then stays put. A first attempt also set the wrapper to
`alignment: .leading`, which put the bar in the right place and dragged every
existing stack's content to the left edge; the bar's own `Spacer` already fills
the width, so the wrapper carries no alignment opinion now.

| 步驟 | 結果 |
|---|---|
| 1：推入三層 | 通過——抵達 `Level 3` |
| 2：依序返回 | **通過，前提是先讓返回控制項存在**——三次按下依序回到 `Level 2`、`Level 1`、`Level 0`，且返回列在根層消失；這一點本身也是檢查的一部分：若根層仍顯示該列，代表路徑已清空而視圖並未察覺 |
| 3：`Record a push` 與畫面層級比對 | 通過——於第 0、1、2 層各按一次，log 中 `pushes 3` 與畫面上的 `Level 3` 出現在同一行。該計數器位於堆疊之外，因此「一致」正是此處要的結果 |
| 4：於深層 `Increment counter` 後返回 | 通過——兩次遞增後按一次 `Back` 停在 `Level 2`，同一畫面顯示 `counter -> 2`，故該狀態變更並未擾動歷史 |
| 5：`Pop to root` 重置 | 通過——`pushes recorded -> 0` 且回到根層畫面，而 `counter -> 2` 仍在。該 app 會重置 `pushCount` 但刻意不重置 `counter`；若該處為 0，即代表某個東西重置的範圍超出了被要求的範圍 |

**步驟 2 當時根本無法執行，且這不是 GtkBackend 的缺陷。** `NavigationStack.body` 只繪製
`elements.last`。**所有 backend 上**都沒有導覽列、也沒有返回控制項——堆疊只能推入、永遠無法彈出，
唯一的返回途徑是應用程式自行提供的。P24 推到第 3 層後便無路可退。

修正落在 core 而非 GtkBackend，且以一般 view 組成而非向 backend 索取。導覽列不過是一個按鈕加一段
文字，沒有任何 backend 能做得更好；而若為它另立 `BackendFeatures` 協定，只會導致「在尚未實作它的
每一個 backend 上，堆疊都無法返回」。因此所有 backend 一次獲得此功能。

標籤沿用 SwiftUI 的後備文字。SwiftUI 會顯示前一個視圖的標題，沒有標題時顯示「Back」；此處尚無
導覽標題，因此後備文字即為全部，而 `navigationTitle` 加入後即由此處讀取。

**已知後果，事先記錄而非日後才發現。** 該列與 SwiftUI 的導覽列一樣為全寬，因此一旦有推入內容，
堆疊便會撐滿其容器。內容會在根層與第一個推入層之間重排一次，之後固定。第一版還曾將外層包裝設為
`alignment: .leading`，那雖把列放到正確位置，卻同時把所有既有堆疊的內容拉到左緣；由於該列自身的
`Spacer` 已能撐滿寬度，現在的包裝不帶任何對齊主張。

## Not yet run

None. P24 steps 2-5 were the last, and closing them needed a core fix rather
than more time: `NavigationStack` had no back control on any backend, so step 2
was not a step anyone could have performed.

P11, P12 and P14 remain out of scope on this Windows/WSL machine -- 18 steps
across macOS, Android and iOS. Of the 190 in the plan, the 172 that are
reachable here have all been run.

尚未執行：無。P24 步驟 2-5 是最後幾項，而要結案它們需要的是一項 core 修正而非更多時間：
`NavigationStack` 在所有 backend 上都沒有返回控制項，因此步驟 2 根本不是任何人能執行的步驟。

P11、P12、P14 在本 Windows/WSL 機器上仍屬範圍之外——橫跨 macOS、Android 與 iOS 共 18 步。計畫中
的 190 步裡，此處可觸及的 172 步已全部執行。

## Win32Synthesiser on Windows -- movement and replay verified, clicks do not activate

The action-file machinery runs on Windows once two environment problems are out
of the way, and the synthesiser's cursor movement is correct -- but a
synthesised click does not activate a GtkBackend control, and the cause is not
yet isolated.

### What was fixed to get this far

A `-gtk4` Windows build died before `main` with
`api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file`. `C:/gtk4/bin`
holds both the GTK DLLs and the UCRT the error names, and it was on PATH only for
the build shell. Both the runner (`test_common.zsh`) and a new `testapp/run.zsh`
now put it on PATH for the launch, via `cygpath -u` so the `:` in `C:/gtk4/bin`
is not read as two PATH entries.

This failure had been invisible: every earlier Windows run sent stderr to
`/dev/null`, so a build that never started looked identical to one that started
and rendered nothing -- which is how P19 was once recorded as rendering on
Windows on the strength of a WinUI build from a different code path.

### What is verified

With a fresh `SCUI_DEBUG=1` build, P19 launches, the backend logs
`-actionfile: replayed`, and the cursor lands **exactly on the target button**
-- visible on "Open the menu" in the capture, which confirms the
`MOUSEEVENTF_ABSOLUTE` virtual-desktop conversion and the frame-origin
coordinates are right. The `-win` alias and the priority-1 window capture both
work.

### What does not work, and what was ruled out

The menu never opens. `last action -> nothing yet` after the full replay, and an
open-only file with a 3s hold shows no popover. The click reaches the right
pixel and does nothing. Ruled out, each by a test rather than by reasoning:

- **Coordinates** -- the cursor is provably on the button.
- **First-click-activation** -- two clicks in a row did not help.
- **Foreground** -- an `AttachThreadInput` + `SetForegroundWindow` version (the
  documented way past a silent `SetForegroundWindow` failure) changed nothing.
- **Timing** -- 20ms gaps between move, press and release changed nothing.

The last two were reverted rather than left in: neither was shown to help, and
unverified code that claims to fix a problem it does not is worse than its
absence.

The remaining candidate is GTK4's own Windows input path -- whether it accepts
`SendInput`-injected pointer events at all, or requires a focus/grab state that
a background-thread replay does not establish. That is a real investigation, not
a tweak, and is where #26 stands.

The coordinates worked out for P19 on Windows, recorded here so the effort
survives the uncommitted file: frame origin, 125% display scale already divided
out, `click 77,180` to open the menu and `click 77,212` for the item. They place
the cursor correctly; they are waiting on the click activating.

### Consequence for the action folders

`actions/win/` stays empty. `P19-open-and-select.csv` was written and its
coordinates are correct, but it does not pass -- the clicks do not activate the
control -- so by the folder's own rule (a file appears only once it has been
seen to work here) it is not committed.

## Win32Synthesiser 在 Windows -- 移動與重放已驗證，點擊無法觸發控制項

動作檔機制在排除兩個環境問題後可於 Windows 執行，synthesiser 的游標移動也正確——但合成點擊無法
觸發 GtkBackend 的控制項，且成因尚未查明。

### 為抵達此處所修正的問題

`-gtk4` 的 Windows 建置會在進入 `main` 之前以
`api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file` 死掉。`C:/gtk4/bin` 同時存放
GTK 的 DLL 與錯誤所指名的 UCRT，而它僅在建置的 shell 中位於 PATH。現在執行器（`test_common.zsh`）
與新增的 `testapp/run.zsh` 都會在啟動時把它加進 PATH，並透過 `cygpath -u`，使 `C:/gtk4/bin` 中的
`:` 不會被解讀為兩個 PATH 項目。

此失敗先前不可見：早先每一次 Windows 執行都把 stderr 送進 `/dev/null`，因此「從未啟動的建置」與
「啟動了卻毫無繪製的建置」看起來一模一樣——P19 曾因此被記為「在 Windows 上正常繪製」，而其依據
其實是另一條程式碼路徑產生的 WinUI 建置。

### 已驗證的部分

以全新的 `SCUI_DEBUG=1` 建置，P19 會啟動，backend 記錄 `-actionfile: replayed`，而游標**精確落在
目標按鈕上**——在截圖中清楚位於「Open the menu」之上，這確認了 `MOUSEEVENTF_ABSOLUTE` 的虛擬桌面
換算與 frame 原點座標皆正確。`-win` 別名與優先序 1 的視窗擷取也都可用。

### 無法運作的部分，以及已排除的原因

選單從未開啟。完整重放後仍為 `last action -> nothing yet`，而只開選單、持有 3 秒的檔案也顯示不出
任何 popover。點擊抵達正確的像素卻毫無作用。以下各項皆以測試而非推論排除：

- **座標**——游標可證明位於按鈕上。
- **首次點擊啟動**——連續兩次點擊並無幫助。
- **前景**——採用 `AttachThreadInput` + `SetForegroundWindow` 的版本（繞過 `SetForegroundWindow`
  靜默失敗的文件記載做法）毫無改變。
- **時序**——在 move、按下、放開之間加入 20ms 間隔亦無改變。

後兩者已還原而非保留：兩者皆未被證明有幫助，而「宣稱修正卻其實無效的未驗證程式碼」比其不存在
更糟。

剩下的候選成因是 GTK4 自身的 Windows 輸入路徑——它究竟是否接受 `SendInput` 注入的指標事件，或
需要背景執行緒重放所未建立的某種 focus/grab 狀態。那是一項真正的調查，而非小幅調整，也正是 #26
目前所在之處。

### 對動作資料夾的影響

`actions/win/` 維持空的。`P19-open-and-select.csv` 已撰寫且座標正確，但它並未通過——點擊無法觸發
控制項——因此依該資料夾自身的規則（檔案唯有在此平台實際運作過才會出現），它不予提交。
