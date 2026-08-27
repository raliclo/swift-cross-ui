# GtkBackend: silent no-ops and fidelity gaps — a ranked inventory
# GtkBackend：靜默 no-op 與擬真度落差——排序清單

Surveyed 2026-08-26 against `develop` @ `d6e35a15`. Re-verify anything here before
relying on it: every claim is a snapshot of the code on that day, and four agents
were editing `Sources/` while this was written.

實測於 2026-08-26，對照 `develop` @ `d6e35a15`。引用本文任何一條之前請重新驗證：所有陳述都
只是當日程式碼的快照，而撰寫本文時另有四個 agent 正在修改 `Sources/`。

## What counts as a finding / 何謂一條發現

A backend method that SwiftCrossUI calls, that returns normally, and that does
nothing or something visibly wrong — with no log line, no assertion, and nothing
an app author could notice except by comparing against another backend.

SwiftCrossUI 會呼叫、能正常返回，卻什麼都沒做或做錯了的 backend 方法——沒有日誌、沒有
assertion，除非拿另一個 backend 對照，否則 app 作者無從察覺。

## How this is ordered / 排序方式

Highest severity × cheapest fix first, because that is the order the fixes will be
worked through in. An expensive fix for a severe defect (#12, the time picker)
therefore sits below a one-line fix for a mild one.

嚴重度 × 修復成本，最嚴重且最便宜者在前，因為修復將依此順序進行。因此「嚴重但昂貴」的項目
（#12 時間選擇器）會排在「輕微但一行可解」的項目之後。

Severity vocabulary / 嚴重度用語:

| Term | Meaning | 意義 |
|---|---|---|
| **broken** | The app looks broken. A feature the author wrote is absent from the screen. | app 看起來壞了。作者寫的功能在畫面上不存在。 |
| **wrong** | Subtly wrong. It draws, but not what was asked for. | 微妙地錯誤。畫得出來，但不是所要求的東西。 |
| **refinement** | A refinement is lost. Nobody would file a bug from a screenshot. | 只是失去了一項精緻化。單看截圖沒人會回報 bug。 |

## Confirmation status / 驗證狀態

| Mark | Meaning | 意義 |
|---|---|---|
| **[src]** | Read off the source. Unambiguous from the code alone. | 直接讀原始碼得出，僅憑程式碼即可確定。 |
| **[hdr]** | Checked against the installed GTK 4 headers at `/c/gtk4/include/gtk-4.0/`. | 已對照安裝於 `/c/gtk4/include/gtk-4.0/` 的 GTK 4 標頭檔確認。 |
| **[?]** | Suspected. Needs a measurement that was not run. Each such entry says how to run it. | 僅為推測，需要尚未執行的實測。每一條都寫明如何驗證。 |

Nothing in this document was confirmed by launching an app. No screenshot was
taken and the UI lock was never acquired: none of the findings below turned out to
need a picture to settle, and the ones that would (#10) need a test app that this
survey was not permitted to write.

本文件沒有任何一條是以啟動 app 確認的。未截任何圖，也從未取得 UI lock：以下發現沒有一條
需要靠畫面才能定案；唯一需要的那條（#10）需要一支本次調查不被允許撰寫的測試 app。

---

# The inventory / 清單

Twenty-one findings. Eight are in `GtkBackend.swift`'s windowing section, two in
scroll, three in fonts, five in controls, three elsewhere. Plus one meta-finding
(#6) that changes how you should read six of the others, and an appendix of seven
things that look like defects and are not.

共二十一條。其中視窗八條、捲動兩條、字型三條、控制項五條、其他三條。另有一條後設發現
（#6），它會改變你對其中六條的解讀；以及七條「看似缺陷、實則不是」的附錄。

---

## 1. ~~`swap(childAt:withChildAt:in:)` never touches GTK's z-order~~ — **FIXED 2026-08-27** **[src] [hdr]**

Fixed as described below, with `gtk_widget_insert_after`. The whole sibling
order is re-established from the array rather than moving just the two, because
computing each one's new anchor while the other is also moving is easy to get
wrong when they are adjacent, and re-walking also repairs an order that drifted
while the GTK half was missing.

**Verifying it turned up a second defect that had been hiding this one.** There
was no test for z-order because none could be written: `ForEach` inside a
`ZStack` did not overlap at all. `layoutOverlapsChildren` was added when #158
was fixed for `Group`, and its own documentation says it exists so that "`Group`
and `ForEach`" can be transparent — but only `Group` ever read it. So a `ForEach`
in a `ZStack` fell back to the *grandparent's* axis and laid its children out in
a column, where z-order is invisible. Both are fixed; `testapp/actions/win/P13-zorder.csv`
drives the check, and P13 gained the section it drives.

已依下述方式修復，使用 `gtk_widget_insert_after`。此處是依陣列重建整個兄弟順序，而非只搬動那兩個
——因為在「另一個也正在移動」時推算各自的新錨點，於兩者相鄰時很容易出錯；重新走訪同時也會修復
「GTK 那一半缺席期間已經飄掉的順序」。

**驗證它的過程中，挖出了另一個一直遮著它的缺陷。** 先前之所以沒有 z 順序的測試，是因為根本寫不
出來：`ZStack` 中的 `ForEach` 完全不重疊。`layoutOverlapsChildren` 是在為 `Group` 修 #158 時加入的，
其文件明寫此旗標的存在是為了讓「`Group` 與 `ForEach`」保持透明——但實際讀取它的只有 `Group`。
於是 `ZStack` 中的 `ForEach` 退而採用**祖父層**的軸向，把子元件排成一欄，而 z 順序在那裡根本看不見。
兩者皆已修復；`testapp/actions/win/P13-zorder.csv` 驅動該項檢查，P13 也新增了它所驅動的段落。

<details><summary>The original finding / 原始發現</summary>

## 1. `swap(childAt:withChildAt:in:)` never touches GTK's z-order — **broken**, cheap **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:958`

**Asked to do** (`BackendFeatures/Core/GenericContainers.swift`, and by the
symmetry of AppKit's and WinUI's implementations): swap two children of a
container, which in a `ZStack` means swapping which one draws on top.

**Actually does**: swaps two entries in SwiftCrossUI's own bookkeeping array and
nothing else. The comment says so outright:

> Gtk.Fixed doesn't let us rearrange children, so we just swap them in our own
> list so that at least everything works on the SCUI side. The only side effect of
> this approach is that overlapping widgets may end up with unexpected z ordering.

**Other backends**: `AppKitBackend.swift:485` does a real `container.subviews.swapAt`.
`WinUIBackend.swift:619` does a real remove/insert pair on `container.children`.
GtkBackend is the only one that fakes it.

**Fixable in GTK 4**: yes. The comment's premise is out of date. `gtk_widget_insert_after`
and `gtk_widget_insert_before` are both present — `gtkwidget.h:900` and `:904` —
and they are exactly the GTK 4 way to reorder a widget among its siblings. Reorder
the two real widgets alongside the array swap.

**Why it is top of the list**: it is a silent wrong result for a `ZStack` whose
ordering is state-driven, the fix is a couple of lines, and the API question is
already settled.

---

**1. `swap(childAt:withChildAt:in:)` 完全沒有動到 GTK 的 z-order — 嚴重度 broken，成本低 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:958`

**被要求做的事**（`BackendFeatures/Core/GenericContainers.swift`，以及 AppKit 與 WinUI
實作的對稱性）：交換容器的兩個子元件；在 `ZStack` 中即為交換誰畫在上層。

**實際做的事**：只交換 SwiftCrossUI 自己記帳用陣列中的兩個項目，其餘什麼都沒做。註解自己
就寫明了：「Gtk.Fixed 不允許我們重排子元件，因此我們只在自己的清單裡交換……唯一的副作用是
重疊的 widget 可能得到非預期的 z 順序。」

**其他 backend**：`AppKitBackend.swift:485` 真的呼叫 `container.subviews.swapAt`；
`WinUIBackend.swift:619` 真的對 `container.children` 做移除／插入。GtkBackend 是唯一造假的。

**GTK 4 是否可修**：可以。註解的前提已經過時。`gtk_widget_insert_after` 與
`gtk_widget_insert_before` 都存在——`gtkwidget.h:900` 與 `:904`——而它們正是 GTK 4 用來在
兄弟節點之間重排 widget 的方式。在交換陣列的同時，一併重排這兩個真實 widget 即可。

**為何排第一**：對於順序由 state 決定的 `ZStack`，這是一個靜默的錯誤結果；修復只需數行；
而 API 的疑問已經解決。

---

</details>

## 2. `isWindowProgrammaticallyResizable(_:)` always answers `true` — **wrong**, one line **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:381`

```swift
public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
    // TODO: Detect whether window is fullscreen
    return true
}
```

**Asked to do**: report whether SwiftCrossUI may resize this window itself. A
fullscreen window must answer `false`, or the layout system fights the compositor.

**Actually does**: returns a constant.

**Other backends**: `AppKitBackend.swift:155` returns `!window.styleMask.contains(.fullScreen)`.
`WinUIBackend.swift:321` carries the identical TODO and the identical constant, so
this is a shared gap rather than a GTK one — but it is a one-line fix on GTK and
not on WinUI.

**Fixable in GTK 4**: yes, trivially. `gtk_window_is_fullscreen()` is present at
`gtkwindow.h:251`. The `Gtk.Window` Swift wrapper does not expose it yet
(`Sources/Gtk/Widgets/Window.swift` has `resizable` and `deletable` only), so the
fix is one accessor plus `return !window.isFullscreen`.

---

**2. `isWindowProgrammaticallyResizable(_:)` 永遠回答 `true` — 嚴重度 wrong，一行可解 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:381`

**被要求做的事**：回報 SwiftCrossUI 是否可自行調整此視窗大小。全螢幕視窗必須回答 `false`，
否則版面系統會與合成器互相拉扯。

**實際做的事**：回傳一個常數。

**其他 backend**：`AppKitBackend.swift:155` 回傳 `!window.styleMask.contains(.fullScreen)`；
`WinUIBackend.swift:321` 帶著一模一樣的 TODO 與一模一樣的常數，所以這是共通缺口而非 GTK 專屬
——但在 GTK 上它是一行可解，在 WinUI 上不是。

**GTK 4 是否可修**：可以，而且極簡單。`gtk_window_is_fullscreen()` 存在於 `gtkwindow.h:251`。
Swift 端的 `Gtk.Window` wrapper 目前尚未公開它（`Sources/Gtk/Widgets/Window.swift` 只有
`resizable` 與 `deletable`），因此修復為「新增一個 accessor」加上 `return !window.isFullscreen`。

---

## 3. `updateRadialGradientWidget` ignores both radii — **broken**, two lines **[src]**

`Sources/GtkBackend/GtkBackend+Gradient.swift:49`

**Asked to do** (`Sources/SwiftCrossUI/Views/Gradients/RadialGradient.swift:5-12`):

> `startRadius`: The radius at which the first gradient stop will be placed. All
> space inside this radius gets filled with the color of the first gradient stop.
> `endRadius`: The radius at which the last gradient stop will be placed. All space
> outside this radius gets filled with the color of the last gradient stop.

**Actually does**: uses the two radii only to decide whether to reverse the stop
order, then emits

```
radial-gradient(circle at X% Y%, <stops>)
```

A CSS `radial-gradient` with no `<extent>` defaults to `farthest-corner`, so
`endRadius` is discarded and the gradient always fills the widget. `startRadius`
is discarded entirely: there is no solid inner disc. A `RadialGradient(colors:…,
startRadius: 40, endRadius: 60)` in a 300pt box draws as a full-box gradient on
GTK and as a small ring on every other backend.

**Other backends**: SwiftCrossUI ships a helper written for exactly this situation
— `RadialGradient.adjustedStops` at `RadialGradient.swift:97`, documented as
*"Stops adjusted to accomodate startRadius on backends without native support."*
`AppKitBackend+Gradient.swift:175`, `UIKitBackend+Gradient.swift:190` and
`WinUIBackend+Gradient.swift:57` all use it. **GtkBackend is the only backend that
does not**, and it hand-rolls a partial substitute (`invertedStops`, same file:143)
that covers only the direction half of the problem.

**Fixable in GTK 4**: yes. Substitute `gradient.adjustedStops` for
`gradient.gradient.stops` / `invertedStops(...)` — that alone fixes `startRadius`
and the inversion, and makes `invertedStops` dead. `endRadius` additionally needs
the CSS extent written explicitly, e.g. `circle <endRadius>px at X% Y%`.

---

**3. `updateRadialGradientWidget` 忽略兩個半徑 — 嚴重度 broken，兩行可解 [src]**

`Sources/GtkBackend/GtkBackend+Gradient.swift:49`

**被要求做的事**（`RadialGradient.swift:5-12`）：`startRadius` 是第一個色標所在的半徑，其
內部全部填滿第一個色標的顏色；`endRadius` 是最後一個色標所在的半徑，其外部全部填滿最後一個
色標的顏色。

**實際做的事**：兩個半徑只被用來決定是否反轉色標順序，然後輸出
`radial-gradient(circle at X% Y%, <stops>)`。CSS 的 `radial-gradient` 若未指定 `<extent>`
會預設為 `farthest-corner`，因此 `endRadius` 被丟棄，漸層永遠填滿整個 widget；`startRadius`
則完全被丟棄，不存在實心的內圓。在 300pt 的方框中，
`RadialGradient(colors:…, startRadius: 40, endRadius: 60)` 在 GTK 上畫成整框漸層，在其他每個
backend 上畫成一個小圓環。

**其他 backend**：SwiftCrossUI 為此情境備有專用 helper——`RadialGradient.swift:97` 的
`adjustedStops`，文件寫著「為不具原生支援的 backend 調整色標以容納 startRadius」。
`AppKitBackend+Gradient.swift:175`、`UIKitBackend+Gradient.swift:190` 與
`WinUIBackend+Gradient.swift:57` 都在使用它。**GtkBackend 是唯一沒有使用的 backend**，並自行
寫了一個只涵蓋方向那一半的替代品（同檔案 `:143` 的 `invertedStops`）。

**GTK 4 是否可修**：可以。將 `gradient.gradient.stops` ／ `invertedStops(...)` 換成
`gradient.adjustedStops`，這一步就解決了 `startRadius` 與反轉問題，並使 `invertedStops` 成為
死碼。`endRadius` 另需在 CSS 中明確寫出 extent，例如 `circle <endRadius>px at X% Y%`。

---

## 4. `updateAngularGradientWidget` mis-renders a reversed sweep — **wrong**, one line **[src]**

`Sources/GtkBackend/GtkBackend+Gradient.swift:82`

**Asked to do**: place the stops across the sweep from `startAngle` to `endAngle`.

**Actually does**: computes `sweep = endAngle - startAngle ?? 360` and scales each
stop location by `sweep / 360`. Correct when `endAngle > startAngle`. When
`endAngle < startAngle` the sweep is negative, so every stop location comes out
negative and the emitted CSS reads `rgba(…) -37.5%` — which CSS clamps, drawing a
flat block of the last colour rather than a reversed gradient.

**Other backends**: `AngularGradient.adjustedStops` (`AngularGradient.swift:140`)
handles precisely this: it flips the stop order when `range < 0`, takes `abs`, and
re-sorts. Same story as #3 — the helper exists and GtkBackend hand-rolls a partial
version instead.

**Fixable in GTK 4**: yes, one line. Replace the local `stops` computation with
`gradient.adjustedStops`. Note the `fromDegrees` quarter-turn correction just above
it is right and should stay.

---

**4. `updateAngularGradientWidget` 對反向掃掠繪製錯誤 — 嚴重度 wrong，一行可解 [src]**

`Sources/GtkBackend/GtkBackend+Gradient.swift:82`

**被要求做的事**：將色標分布於 `startAngle` 到 `endAngle` 的扇形上。

**實際做的事**：計算 `sweep = endAngle - startAngle ?? 360`，再把每個色標位置乘上
`sweep / 360`。當 `endAngle > startAngle` 時正確。當 `endAngle < startAngle` 時 sweep 為負，
每個色標位置都變成負數，輸出的 CSS 會是 `rgba(…) -37.5%`——CSS 會將其夾限，畫出一整片最後一個
顏色的色塊，而非反向漸層。

**其他 backend**：`AngularGradient.swift:140` 的 `adjustedStops` 正是處理這件事：`range < 0`
時反轉色標順序、取絕對值、再重新排序。與 #3 同一個故事——helper 已存在，GtkBackend 卻自行寫了
一個不完整的版本。

**GTK 4 是否可修**：可以，一行。把區域的 `stops` 計算換成 `gradient.adjustedStops`。其上方的
`fromDegrees` 四分之一圈修正是正確的，應予保留。

---

## 5. `.semibold` and `.bold` render identically — **wrong**, one line **[src]**

`Sources/GtkBackend/GtkBackend.swift:2763`, weight table at `:2781-2802`

**Asked to do** (`Sources/SwiftCrossUI/Values/Font.swift`, `Font.Weight`): render
nine distinct weights.

**Actually does**: maps them onto eight CSS numbers, with `.semibold` and `.bold`
both landing on `700`. `Text("x").fontWeight(.semibold)` and `Text("x").bold()`
are then pixel-identical on GTK and visibly different on AppKit. The whole ladder
is also shifted up one CSS step — `.regular` becomes `500` (CSS *medium*), `.light`
becomes `400` (CSS *normal*) — which the comment justifies:

> For some reason I had to tweak these a bit to make them match up with AppKit's
> font weights. The Gtk3 backend, since removed, needed no such tweaking.

**Other backends**: `AppKitBackend.swift:1276` maps each of the nine to its own
`NSFont.Weight`, `.semibold` and `.bold` included.

**Fixable in GTK 4**: yes. Pango/CSS have both `600` (semibold) and `700` (bold),
so the collapse is a table error, not a platform limit. The one-line fix is
`case .semibold: 600`. Whether the *rest* of the ladder should be un-shifted is a
separate, riskier change and should not be bundled with it — the shift was
deliberate and matching AppKit was measured, whereas the `.semibold`/`.bold`
collision looks like a slip.

---

**5. `.semibold` 與 `.bold` 繪製結果完全相同 — 嚴重度 wrong，一行可解 [src]**

`Sources/GtkBackend/GtkBackend.swift:2763`，字重對照表在 `:2781-2802`

**被要求做的事**（`Sources/SwiftCrossUI/Values/Font.swift` 的 `Font.Weight`）：繪製九種不同
的字重。

**實際做的事**：對映到八個 CSS 數值，`.semibold` 與 `.bold` 同時落在 `700`。於是
`Text("x").fontWeight(.semibold)` 與 `Text("x").bold()` 在 GTK 上像素完全相同，在 AppKit 上
則明顯不同。整個階梯也被往上位移了一階——`.regular` 變成 `500`（CSS 的 *medium*）、`.light`
變成 `400`（CSS 的 *normal*）——註解對此有說明：「不知為何我必須微調這些數值，才能與 AppKit
的字重對得上。已移除的 Gtk3 backend 不需要這種微調。」

**其他 backend**：`AppKitBackend.swift:1276` 將九種各自對映到獨立的 `NSFont.Weight`，包含
`.semibold` 與 `.bold`。

**GTK 4 是否可修**：可以。Pango／CSS 同時具備 `600`（semibold）與 `700`（bold），因此這是對照
表的錯誤而非平台限制。一行修復為 `case .semibold: 600`。至於階梯其餘部分是否應該取消位移，
那是另一個風險較高的改動，不應與本項綁在一起——位移是刻意為之且對齊 AppKit 是實測過的，而
`.semibold`／`.bold` 的碰撞看起來則像是筆誤。

---

## 6. ~~META: every diagnostic this backend emits is compiled out of the builds it is tested in~~ — **FIXED 2026-08-27** **[src]**

Fourteen sites audited, eleven changed, in two classes: an unconditional
`logger.warning` where the message is for the author of an app, and
`DebugFeatures.isEnabled` where the check costs something per event. Three were
deliberately left alone — `Publisher.tag` and `Cancellable.tag` are write-only
fields for a debugger with nothing to print, and `BaseStubs` is a compile-time
conformance check. Verified by counting strings in a pure release binary before
and after, not by reading the source.

One correction to the finding below: GtkBackend has **one** `debugLogOnce` call
site, not two. The second went with `da4720ab`, which added the compact date
picker.

已稽核 14 處、變更 11 處，分為兩類：訊息對象是「app 作者」者，改為無條件的 `logger.warning`；
每次事件都要付出代價的檢查，則改用 `DebugFeatures.isEnabled`。三處刻意不動——`Publisher.tag` 與
`Cancellable.tag` 是給 debugger 看的唯寫欄位，沒有東西可印；`BaseStubs` 則是編譯期的 conformance
檢查。驗證方式是在純 release 二進位檔上比對改前改後的字串數量，而非閱讀原始碼。

對下方發現的一項更正：GtkBackend 只有**一個** `debugLogOnce` 呼叫點，不是兩個。第二個隨
`da4720ab`（加入 compact date picker 的那次）一併移除了。

<details><summary>The original finding / 原始發現</summary>

## 6. META: every diagnostic this backend emits is compiled out of the builds it is tested in — **wrong**, small **[src]**

`Sources/GtkBackend/GtkBackend.swift:121-133`

```swift
func debugLogOnce(_ message: String, …) {
    #if DEBUG
        …logger.notice("\(message)")
    #endif
}
```

`testapp/compile.zsh:65-76` builds **release by default** (`BUILD_CONFIG=debug` is
the opt-in), which is also the stated project policy in `CLAUDE.md`. A release
build does not define `DEBUG`. Therefore both `debugLogOnce` call sites —
`:415` ("GTK does not support setting maximum window sizes") and `:2740`
("time picker is unimplemented on GtkBackend") — print nothing in the
configuration everything is actually tested in. The two gaps below (#7, #12) are
*documented* to the source reader and *silent* to the app author, which is the
exact failure mode this survey is about.

The same pattern appears once in SwiftCrossUI proper: `DatePickerStyleModifier.swift:5`
uses `assertionFailure` for an unsupported date picker style, likewise compiled
out in release. See #13.

Contrast `WindowReference.swift:113`, which uses `logger.warning` for an
unsupported window level, with a comment explaining why silence was rejected —
that is the pattern the two `debugLogOnce` sites should follow.

**Fix**: either switch `debugLogOnce` to `logger.notice` unconditionally (it is
already once-per-site, so it cannot spam), or gate it on `SCUI_DEBUG` — which is
the project's actual "can this binary be driven and diagnosed" switch, see
`Sources/DebugFeatures/README.md` and `Package.swift:168-184` — rather than on the
compiler's optimisation level.

---

**6. 後設發現：此 backend 發出的每一則診斷訊息，在它實際被測試的 build 中都被編譯掉了 — 嚴重度 wrong，成本小 [src]**

`Sources/GtkBackend/GtkBackend.swift:121-133`

`debugLogOnce` 的內容包在 `#if DEBUG` 裡。而 `testapp/compile.zsh:65-76` **預設建置 release**
（`BUILD_CONFIG=debug` 才是選擇性加入），這也是 `CLAUDE.md` 明訂的專案政策。release build
不會定義 `DEBUG`。因此兩個 `debugLogOnce` 呼叫點——`:415`（「GTK 不支援設定視窗最大尺寸」）
與 `:2740`（「GtkBackend 尚未實作時間選擇器」）——在所有東西實際受測的組態下都不會印出任何
訊息。下方兩條缺口（#7、#12）因此對讀原始碼的人是「有記載的」，對 app 作者則是「靜默的」，
而這正是本次調查所針對的失效樣態。

同樣的模式在 SwiftCrossUI 本體出現一次：`DatePickerStyleModifier.swift:5` 對不支援的日期
選擇器樣式使用 `assertionFailure`，同樣在 release 中被編譯掉。見 #13。

對照 `WindowReference.swift:113`，它對不支援的 window level 使用 `logger.warning`，並以註解
說明為何不採靜默——那才是這兩個 `debugLogOnce` 呼叫點應該遵循的模式。

**修復**：要嘛把 `debugLogOnce` 改為無條件的 `logger.notice`（它本來就是每個呼叫點只印一次，
不會洗版），要嘛改以 `SCUI_DEBUG` 為條件——那才是本專案真正的「此執行檔能否被驅動與診斷」
開關，見 `Sources/DebugFeatures/README.md` 與 `Package.swift:168-184`——而不是以編譯器的
最佳化等級為條件。

---

</details>

## 7. `setBehaviors(…)` ignores `minimizable` — **wrong**, expensive on Linux, cheap on Windows **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:300`

**Asked to do** (`BackendFeatures/Windowing.swift:62`):

> `minimizable`: Whether the window can be minimized by the user.

**Actually does**: sets `deletable` and `resizable`, and leaves `minimizable`
unread. The parameter is silently discarded:

```swift
// TODO: Figure out if there's some magic way to disable minimization
//   in a framework where the minimize button usually doesn't even exist
```

A window declared `.windowMinimizable(false)` still minimises.

**Other backends**: `AppKitBackend.swift:200` inserts/removes `.miniaturizable`
from the style mask. `WinUIBackend.swift:378` sets `OverlappedPresenter.isMinimizable`.
Both implement it.

**Fixable in GTK 4**: **not on Linux.** `gtkwindow.h` has `gtk_window_minimize`
and `gtk_window_unminimize` (`:194`, `:196`) but no `set_minimizable` / no
minimizable property — grep the header, there is nothing else. Under Wayland the
decorations are the compositor's anyway. **On Windows it is cheap**: a GTK window
there is an ordinary `HWND`, so clearing `WS_MINIMIZEBOX` with `SetWindowLongPtr`
works — the same route `scui_window_set_topmost` already takes for `.floating`
(see `supportedWindowLevels` at `:338` and its bilingual rationale, which is the
model to copy for this).

**Recommendation**: mirror the `WindowLevels` design. Either add a capability
property, or at minimum replace the TODO with a `logger.warning` that fires once —
per #6, the current silence is the defect, and the platform limit is real only on
half the platforms this backend runs on.

---

**7. `setBehaviors(…)` 忽略 `minimizable` — 嚴重度 wrong，Linux 上昂貴、Windows 上便宜 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:300`

**被要求做的事**（`BackendFeatures/Windowing.swift:62`）：「`minimizable`：使用者是否可以
最小化此視窗。」

**實際做的事**：設定了 `deletable` 與 `resizable`，`minimizable` 從未被讀取，該參數被靜默
丟棄。宣告為 `.windowMinimizable(false)` 的視窗仍然可以被最小化。

**其他 backend**：`AppKitBackend.swift:200` 對 style mask 增刪 `.miniaturizable`；
`WinUIBackend.swift:378` 設定 `OverlappedPresenter.isMinimizable`。兩者都有實作。

**GTK 4 是否可修**：**Linux 上不行。** `gtkwindow.h` 有 `gtk_window_minimize` 與
`gtk_window_unminimize`（`:194`、`:196`），但沒有 `set_minimizable`、也沒有 minimizable
property——去 grep 該標頭檔，沒有別的了。在 Wayland 下，裝飾本來就屬於合成器。**在 Windows
上則很便宜**：GTK 視窗在該平台就是普通的 `HWND`，用 `SetWindowLongPtr` 清掉 `WS_MINIMIZEBOX`
即可——與 `scui_window_set_topmost` 為 `.floating` 所走的路線相同（見 `:338` 的
`supportedWindowLevels` 及其雙語理由，那正是本項應該模仿的樣板）。

**建議**：比照 `WindowLevels` 的設計。要嘛新增一個能力 property，要嘛至少把 TODO 換成一次性的
`logger.warning`——依 #6，現在的靜默本身才是缺陷，而平台限制只在此 backend 所執行的一半平台上
成立。

---

## 8. `setWindowEnvironmentChangeHandler(of:to:)` is an empty body — **refinement**, medium **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:900`

```swift
public func setWindowEnvironmentChangeHandler(
    of window: Window,
    to action: @escaping @Sendable @MainActor () -> Void
) {
    // TODO: Notify when window scale factor changes
}
```

**Asked to do** (`BackendFeatures/Core/CoreWindowing.swift:142`): call `action`
when the window's environment changes — *"This may involve updating
`EnvironmentValues/windowScaleFactor`, etc."*

**Actually does**: nothing. The `action` closure is discarded without being stored.
This is the most literal empty-body no-op in the file.

**Other backends**: `AppKitBackend.swift:419` registers for
`didChangeBackingPropertiesNotification` and `didBecomeKeyNotification`.
`WinUIBackend.swift:574` hooks `window.activated`.

**Actual consequence is smaller than it looks**: `createWindow` (`:255`) sets
`window.notifyIsActive` to fire the *root* environment change handler, which
recomputes every window's environment — so `scenePhase` does still track focus.
What is genuinely lost is the scale-factor half, which ties into #9.

**Fixable in GTK 4**: yes. `GtkWidget` has a `scale-factor` property (its getter is
`gtk_widget_get_scale_factor`, `gtkwidget.h:541`), so `notify::scale-factor` is the
signal to connect. Cost is a `Gtk` wrapper addition, not one line.

---

**8. `setWindowEnvironmentChangeHandler(of:to:)` 是空實作 — 嚴重度 refinement，成本中等 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:900`

**被要求做的事**（`BackendFeatures/Core/CoreWindowing.swift:142`）：當視窗環境改變時呼叫
`action`——「這可能涉及更新 `EnvironmentValues/windowScaleFactor` 等。」

**實際做的事**：什麼都沒做。`action` closure 未經儲存即被丟棄。這是本檔案中最字面意義上的
空實作 no-op。

**其他 backend**：`AppKitBackend.swift:419` 註冊 `didChangeBackingPropertiesNotification`
與 `didBecomeKeyNotification`；`WinUIBackend.swift:574` 掛上 `window.activated`。

**實際後果比看起來小**：`createWindow`（`:255`）將 `window.notifyIsActive` 設為觸發*根*環境
變更 handler，而後者會重算每個視窗的環境——因此 `scenePhase` 仍會跟隨焦點。真正失去的是縮放
係數那一半，這與 #9 相連。

**GTK 4 是否可修**：可以。`GtkWidget` 有 `scale-factor` property（其 getter 為
`gtk_widget_get_scale_factor`，`gtkwidget.h:541`），因此要連接的訊號是 `notify::scale-factor`。
成本是新增 `Gtk` wrapper，而非一行。

---

## 9. ~~`computeWindowEnvironment(…)` never reports the window scale factor~~ — **FIXED 2026-08-27** **[src] [hdr]**

Both GtkBackend and WinUIBackend now write it.
`gtk_widget_get_scale_factor` on one side and the already-computed
`CustomWindow.scaleFactor` on the other — WinUI had the value and simply never
used it. Deliberately the toolkit's answer rather than the display's, matching
the decision in `InputEvent.WindowGeometry.scale`: GTK's is an integer and the
two disagree at 125% on Windows.

Verified on WSL, because on this machine GTK reports 1 either way and a working
implementation is indistinguishable from the old hardcoded 1: `GDK_SCALE=1`
gave 1.0 and `GDK_SCALE=2` gave 2.0 through the value actually written into the
environment.

Still open, and the harder half the original TODO named: neither backend
notifies when the factor changes, so a window dragged between displays of
different scale keeps the value it started with.

GtkBackend 與 WinUIBackend 現在都會寫入此值：一邊用 `gtk_widget_get_scale_factor`，另一邊用早已
算好、卻從未被使用的 `CustomWindow.scaleFactor`。刻意採用 toolkit 的答案而非顯示器的，與
`InputEvent.WindowGeometry.scale` 的決定一致：GTK 的是整數，而在 Windows 的 125% 之下兩者並不一致。

於 WSL 驗證，因為在這台機器上 GTK 兩種情況都回報 1，可運作的實作與舊有的寫死 1 無法區分：
`GDK_SCALE=1` 得 1.0、`GDK_SCALE=2` 得 2.0，且量的是真正寫進 environment 的那個值。

仍未處理、亦即原 TODO 所稱較難的那一半：兩個 backend 都不會在該比例變動時發出通知，因此視窗被拖到
不同縮放的顯示器時，會保留它啟動時的值。

<details><summary>The original finding / 原始發現</summary>

## 9. `computeWindowEnvironment(…)` never reports the window scale factor — **refinement**, one line **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:891`

**Asked to do**: return the environment for this window, scale factor included.

**Actually does**: returns the root environment with only `scenePhase` set, leaving
`EnvironmentValues.windowScaleFactor` at its declared default of `1`
(`EnvironmentValues.swift:326`). On a 200 % display the environment reports 100 %.

**Other backends**: `AppKitBackend.swift:408` sets `.with(\.windowScaleFactor,
window.backingScaleFactor)`. `WinUIBackend.swift:564` carries the same TODO as
GtkBackend, with an added honest note — *"easy enough, but we would also have to
keep it up-to-date then, which is kinda annoying for now"*. So this is a shared
gap, not a GTK one.

**Who actually reads it**: within SwiftCrossUI, only `Image.swift:159`/`:188`,
to decide whether to re-render an image after a scale change — and GtkBackend sets
`requiresImageUpdateOnScaleFactorChange = false` (`:70`), so that path is off
anyway. Hence **refinement**, not **wrong**: nothing visible changes today. It
becomes visible the moment anything else starts reading `windowScaleFactor`.

**Fixable in GTK 4**: yes, one line, `gtk_widget_get_scale_factor` (`gtkwidget.h:541`).
Doing it without #8 means the value is right at window creation and stale after a
monitor change.

---

**9. `computeWindowEnvironment(…)` 從不回報視窗縮放係數 — 嚴重度 refinement，一行可解 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:891`

**被要求做的事**：回傳此視窗的環境，含縮放係數。

**實際做的事**：回傳只設定了 `scenePhase` 的根環境，`EnvironmentValues.windowScaleFactor`
維持在其宣告的預設值 `1`（`EnvironmentValues.swift:326`）。在 200 % 的顯示器上，環境回報 100 %。

**其他 backend**：`AppKitBackend.swift:408` 設定 `.with(\.windowScaleFactor,
window.backingScaleFactor)`；`WinUIBackend.swift:564` 帶著與 GtkBackend 相同的 TODO，並附上
一句誠實的說明：「其實不難，但那樣就還得讓它保持最新，目前有點麻煩」。因此這是共通缺口而非
GTK 專屬。

**實際上誰會讀它**：在 SwiftCrossUI 內只有 `Image.swift:159`／`:188`，用來決定縮放改變後是否
重繪圖片——而 GtkBackend 設定 `requiresImageUpdateOnScaleFactorChange = false`（`:70`），該路徑
本來就關閉。因此嚴重度是 **refinement** 而非 **wrong**：目前畫面上什麼都不會改變。一旦有其他
東西開始讀 `windowScaleFactor`，它就會變得可見。

**GTK 4 是否可修**：可以，一行，`gtk_widget_get_scale_factor`（`gtkwidget.h:541`）。若不一併
處理 #8，則該值只在視窗建立時正確，換螢幕後就過時。

---

</details>

## 10. The line-limit measurement label is never rooted — **wrong** if confirmed, one line **[?]**

`Sources/GtkBackend/GtkBackend.swift:162` (creation), `:1396-1417` (use)

**Asked to do** (`BackendFeatures/PassiveViews/TextViews.swift:49`): return the
size the text would have; `size(of:…)` also applies `environment.lineLimitSettings`
by measuring a synthetic *n*-line string.

**Suspected defect**: `measurementCustomLabel` is built with
`self.createTextView()` and never added to a window or any parent. The measurement
at `:1399` calls `updateTextView(measurementCustomLabel, content: "", environment:)`
— which sets the environment's font size and weight as CSS — and then measures with
`Pango(for: measurementCustomLabel)`.

The reason to doubt that the CSS lands: this backend already measured, and
documented at `:820-825`, that GTK only resolves style for a widget with a root —

> it must sit inside a window: GTK only resolves theme CSS for a widget that has a
> root, so a loose label reports the default white (measured: 1.0/1.0/1.0 under
> every theme, which reads as "dark" everywhere and is wrong everywhere).

If the same holds for the per-widget CSS provider (which is display-wide with a
per-widget class — see `Sources/Gtk/Widgets/Widget.swift:34-54` and
`Sources/Gtk/Utility/CSS/CSSProvider.swift`), then the line-limit height cap is
computed at GTK's *default* font size regardless of the requested font.
`Text(…).font(.largeTitle).lineLimit(2)` would then be capped at two lines of
body-sized text and clipped.

**Why it is unconfirmed**: the two cases differ — the ambient-theme measurement
read a *theme* colour, whereas this reads a provider the app installed on the
display itself. I did not run it. **No `testapp/P*.swift` uses `lineLimit` at all**
(grepped, zero hits), which is consistent with this being an unnoticed gap.

**How to settle it**: a view with `.font(.largeTitle).lineLimit(2)` over long text,
next to the same text with `.lineLimit(nil)`, on GtkBackend and one other backend.
If GTK clips the two-line version to roughly body height, it is confirmed.

**Fix if confirmed**: put `measurementCustomLabel` in an unshown `Gtk.Window`, the
same trick `sampleAmbientColorScheme` (`:835`) already uses, or measure with the
real target widget's Pango context instead of the shared one.

---

**10. 行數限制的量測用 label 從未被放入視窗 — 若證實則嚴重度 wrong，一行可解 [?]**

`Sources/GtkBackend/GtkBackend.swift:162`（建立處）、`:1396-1417`（使用處）

**被要求做的事**（`TextViews.swift:49`）：回傳文字的尺寸；`size(of:…)` 同時透過量測一個合成
的 *n* 行字串來套用 `environment.lineLimitSettings`。

**推測的缺陷**：`measurementCustomLabel` 以 `self.createTextView()` 建立，且從未被加入任何
視窗或 parent。`:1399` 處的量測呼叫
`updateTextView(measurementCustomLabel, content: "", environment:)`——該呼叫會把環境的字級與
字重設為 CSS——然後以 `Pango(for: measurementCustomLabel)` 量測。

懷疑 CSS 不會生效的理由：此 backend 自己就已實測並記錄於 `:820-825`：GTK 只會為具有 root 的
widget 解析樣式——「它必須位於視窗之內：GTK 只會為具有 root 的 widget 解析主題 CSS，因此游離的
label 會回報預設的白色（實測：在每個主題下皆為 1.0/1.0/1.0）」。

若這對「每個 widget 各自的 CSS provider」同樣成立（該 provider 是加在整個 display 上、以
per-widget class 選取——見 `Sources/Gtk/Widgets/Widget.swift:34-54` 與
`Sources/Gtk/Utility/CSS/CSSProvider.swift`），則行數限制的高度上限便是以 GTK 的*預設*字級
計算，與所要求的字型無關。`Text(…).font(.largeTitle).lineLimit(2)` 會被限制在兩行「內文尺寸」
的高度而遭截斷。

**為何未證實**：兩個情境有差異——環境主題那次量測讀的是*主題*顏色，而這裡讀的是 app 自己安裝
於 display 的 provider。我沒有實際執行。**`testapp/P*.swift` 中完全沒有任何一支使用
`lineLimit`**（已 grep，零筆），這與「這是一個未被注意到的缺口」相符。

**如何定案**：在 GtkBackend 與另一個 backend 上，並排顯示長文字的
`.font(.largeTitle).lineLimit(2)` 與同樣文字的 `.lineLimit(nil)`。若 GTK 把兩行版本裁到約等於
內文高度，即為證實。

**證實後的修復**：把 `measurementCustomLabel` 放進一個不顯示的 `Gtk.Window`，即
`sampleAmbientColorScheme`（`:835`）已在用的同一招；或改以真正目標 widget 的 Pango context
量測，而非共用那一個。

---

## 11. `scrollBarWidth` is a hardcoded `0` — **refinement**, small **[src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:68`

**Asked to do** (`BackendFeatures/Containers/ScrollContainers.swift:7-18`):

> Gets the layout width of a backend's scroll bars. […] If the backend uses overlay
> scroll bars then this width should be 0. This value may make sense to have as a
> computed property for some backends such as `AppKitBackend` where plugging in a
> mouse can cause the default scroll bar style to change. If something does cause
> this value to change, ensure that the configured root environment change handler
> gets called […]

**Actually does**: `public let scrollBarWidth = 0` — a stored constant, so it can
never change and the root environment handler can never be called for it.

**Other backends**: `AppKitBackend.swift:38` is a computed property that asks
`NSScroller.preferredScrollerStyle` and returns a real width when the style is not
overlay. `WinUIBackend.swift:146` is also computed but returns a constant 12.

**Is `0` right?** Under GTK 4's default it is: `GtkScrolledWindow.overlay-scrolling`
defaults on, and `updateScrollContainer` uses `GTK_POLICY_AUTOMATIC`, so the bars
float over the content and take no layout width. It stops being right when overlay
scrolling is off — `gtk_scrolled_window_set_overlay_scrolling` exists at
`gtkscrolledwindow.h:149`, and desktops expose a matching accessibility setting.
Then the bars take real width, SwiftCrossUI allots none, and content is
over-allocated by roughly a scrollbar.

**Fixable in GTK 4**: yes — read `gtk_scrolled_window_get_overlay_scrolling`, and
when it is off measure a `GtkScrollbar`'s natural width. Low value until someone
turns overlay scrolling off, which is why this is **refinement**.

---

**11. `scrollBarWidth` 是寫死的 `0` — 嚴重度 refinement，成本小 [src] [hdr]**

`Sources/GtkBackend/GtkBackend.swift:68`

**被要求做的事**（`ScrollContainers.swift:7-18`）：「取得此 backend 捲軸的版面寬度。……若
backend 使用 overlay 捲軸，此寬度應為 0。對某些 backend（例如 `AppKitBackend`，插上滑鼠會改變
預設捲軸樣式）而言，將其設為 computed property 是合理的。若有任何原因導致此值改變，請確保根
環境變更 handler 會被呼叫……」

**實際做的事**：`public let scrollBarWidth = 0`——一個儲存常數，因此它永遠不會改變，根環境
handler 也永遠不會為它被呼叫。

**其他 backend**：`AppKitBackend.swift:38` 是 computed property，會查詢
`NSScroller.preferredScrollerStyle`，在樣式非 overlay 時回傳真實寬度。`WinUIBackend.swift:146`
也是 computed，但回傳常數 12。

**`0` 正確嗎？** 在 GTK 4 的預設下是正確的：`GtkScrolledWindow.overlay-scrolling` 預設開啟，
而 `updateScrollContainer` 使用 `GTK_POLICY_AUTOMATIC`，因此捲軸浮在內容之上、不佔版面寬度。
當 overlay scrolling 被關閉時它就不再正確——`gtk_scrolled_window_set_overlay_scrolling` 存在於
`gtkscrolledwindow.h:149`，而桌面環境有對應的無障礙設定。屆時捲軸會佔用真實寬度，
SwiftCrossUI 卻分配為零，內容因而被多分配了約一條捲軸的寬度。

**GTK 4 是否可修**：可以——讀取 `gtk_scrolled_window_get_overlay_scrolling`，關閉時量測一個
`GtkScrollbar` 的自然寬度。在有人關掉 overlay scrolling 之前價值不高，因此嚴重度為
**refinement**。

---

## 12. `updateDatePicker` silently drops all time components — **broken**, expensive **[src]**

`Sources/GtkBackend/GtkBackend.swift:2731`, warning at `:2740`

**Asked to do** (`BackendFeatures/DatePickers.swift:16-22`): honour `components`,
which may be `.date`, `.hourAndMinute` or `.hourMinuteAndSecond`.

**Actually does**: `components` is read once, only to emit a `debugLogOnce`
warning, and then never used. The widget is always a bare `Gtk.Calendar`. A
`DatePicker(…, displayedComponents: .hourAndMinute)` — a time-only picker — renders
as a full month calendar with no time field anywhere. Per #6 the warning does not
print in release builds.

**Other backends**: `AppKitBackend.swift:1542-1557` builds
`NSDatePicker.ElementFlags` from `components`, handling `.date`,
`.hourMinuteAndSecond` and `.hourAndMinute` separately.

**Fixable in GTK 4**: yes, but not cheaply. GTK 4 has no time-picker widget; one
has to be composed from `GtkSpinButton`s. A half-built `TimePicker` already exists
in this very file at `:3039`, marked at `:3032`:

> This class is incomplete and unused. It was meant to implement time components for
> DatePicker, but I couldn't get the spin buttons to work. TODOs include: Fix the
> spin buttons; Update the strings in the AM/PM picker when the locale changes;
> Replace the calls to `calendar.date(bySetting:value:of:)` with something that
> actually does what we need; Implement range when possible

**Ranked here rather than at the top** despite being the most visible defect in the
list, because finishing `TimePicker` is a day of work, not a line. The
**cheap partial fix worth taking first** is #6's: make the warning fire in release
so the author is told the feature is missing instead of seeing a calendar and
assuming their code is wrong.

---

**12. `updateDatePicker` 靜默丟棄所有時間元件 — 嚴重度 broken，成本高 [src]**

`Sources/GtkBackend/GtkBackend.swift:2731`，警告在 `:2740`

**被要求做的事**（`DatePickers.swift:16-22`）：遵從 `components`，其可能為 `.date`、
`.hourAndMinute` 或 `.hourMinuteAndSecond`。

**實際做的事**：`components` 只被讀取一次，且僅用於發出一則 `debugLogOnce` 警告，之後再也
沒被使用。該 widget 永遠是一個純粹的 `Gtk.Calendar`。
`DatePicker(…, displayedComponents: .hourAndMinute)`——一個純時間選擇器——會繪製成一整個月曆，
畫面上找不到任何時間欄位。依 #6，該警告在 release build 中不會印出。

**其他 backend**：`AppKitBackend.swift:1542-1557` 由 `components` 建構
`NSDatePicker.ElementFlags`，分別處理 `.date`、`.hourMinuteAndSecond` 與 `.hourAndMinute`。

**GTK 4 是否可修**：可以，但不便宜。GTK 4 沒有時間選擇器 widget，必須用 `GtkSpinButton`
組出來。本檔案 `:3039` 已有一個半成品 `TimePicker`，並在 `:3032` 標註：「此類別不完整且未被
使用。它原本是要為 DatePicker 實作時間元件，但我沒能讓 spin button 正常運作。」

**儘管它是清單中最顯眼的缺陷，卻排在這裡**，因為完成 `TimePicker` 是一天的工作量，不是一行。
**值得優先採取的廉價部分修復**就是 #6 所述：讓該警告在 release 中確實發出，如此作者會被告知
功能缺失，而不是看到一個月曆並以為自己的程式碼寫錯了。

---

## 13. `.compact` date picker style falls back silently — **wrong**, medium **[src]**

`Sources/GtkBackend/GtkBackend.swift:73`

```swift
public let supportedDatePickerStyles: [DatePickerStyle] = [.automatic, .graphical]
```

**Asked to do** (`BackendFeatures/DatePickers.swift:9-12`): *"The supported date
picker styles. Must include `DatePickerStyle/automatic`."*

**Actually does**: correctly declares what it supports — the defect is downstream.
`Sources/SwiftCrossUI/Views/Modifiers/DatePickerStyleModifier.swift:5` handles an
unsupported style with `assertionFailure`, which is compiled out in release (#6),
then silently substitutes `.automatic`. So `.datePickerStyle(.compact)` on GTK
produces a full calendar with no warning of any kind.

**Other backends**: `AppKitBackend.swift:29` lists `[.automatic, .graphical, .compact]`
and maps `.compact` to `.textFieldAndStepper` at `:1564`.

**Fixable in GTK 4**: two independent halves.
(a) The silence — change `assertionFailure` to a once-only `logger.warning`,
matching what `WindowReference.warnAboutWindowLevelOnce` (`:113`) already does for
window levels. That is the cheap half and it is not GtkBackend's file.
(b) Actually supporting `.compact` needs a compact widget, which is #12's
`TimePicker`/`GtkSpinButton` problem again.

---

**13. `.compact` 日期選擇器樣式靜默退回 — 嚴重度 wrong，成本中等 [src]**

`Sources/GtkBackend/GtkBackend.swift:73`

**被要求做的事**（`DatePickers.swift:9-12`）：「支援的日期選擇器樣式。必須包含
`DatePickerStyle/automatic`。」

**實際做的事**：它正確宣告了自己支援什麼——缺陷在下游。
`Sources/SwiftCrossUI/Views/Modifiers/DatePickerStyleModifier.swift:5` 以
`assertionFailure` 處理不支援的樣式，而該呼叫在 release 中被編譯掉（#6），接著靜默代換為
`.automatic`。因此在 GTK 上 `.datePickerStyle(.compact)` 會產生一個完整月曆，且沒有任何警告。

**其他 backend**：`AppKitBackend.swift:29` 列出 `[.automatic, .graphical, .compact]`，並在
`:1564` 把 `.compact` 對映到 `.textFieldAndStepper`。

**GTK 4 是否可修**：兩個各自獨立的部分。(a) 靜默問題——把 `assertionFailure` 改為一次性的
`logger.warning`，比照 `WindowReference.warnAboutWindowLevelOnce`（`:113`）對 window level 的
既有做法。這是便宜的一半，而且不在 GtkBackend 的檔案裡。(b) 真正支援 `.compact` 需要一個
compact widget，那又回到 #12 的 `TimePicker`／`GtkSpinButton` 問題。

---

## 14. `setSizeLimits(…)` cannot honour a maximum size, and says so only in DEBUG — **wrong**, unfixable **[src]**

`Sources/GtkBackend/GtkBackend.swift:395`, the maximum branch at `:412-416`

**Asked to do** (`BackendFeatures/Windowing.swift:62-64`): *"Even if resizable, the
window shouldn't be allowed to become smaller than its minimum size, or larger than
its maximum size."*

**Actually does**: enforces the minimum (twice — on the toplevel and, since #289,
on the custom root widget), and for the maximum calls `debugLogOnce("GTK does not
support setting maximum window sizes")`. Per #6 that prints nothing in release.

**Other backends**: `AppKitBackend.swift:169` sets `window.contentMaxSize`.
`WinUIBackend.swift:343` sets `window.maximumContentSize`. Both honour it.

**Fixable in GTK 4**: **no.** The code already cites the upstream answer
(`https://discourse.gnome.org/t/how-to-build-fixed-size-windows-in-gtk-4/22807/10`)
and the comment is blunt about it: *"NB: GTK does not support setting maximum sizes
for widgets. It just doesn't."* Nothing in `gtkwindow.h` contradicts that.

**What to change**: only the reporting. This is the clearest example in the file of
a genuine platform limit that is correctly detected, correctly documented, and then
announced into a stream nobody is listening to.

---

**14. `setSizeLimits(…)` 無法遵從最大尺寸，且只在 DEBUG 中說出這件事 — 嚴重度 wrong，不可修 [src]**

`Sources/GtkBackend/GtkBackend.swift:395`，最大值分支在 `:412-416`

**被要求做的事**（`Windowing.swift:62-64`）：「即使可調整大小，視窗也不應被允許小於其最小
尺寸，或大於其最大尺寸。」

**實際做的事**：確實執行了最小值（而且執行兩次——toplevel 一次，自 #289 起在自訂 root widget
上再一次）；對最大值則呼叫 `debugLogOnce("GTK does not support setting maximum window sizes")`。
依 #6，這在 release 中不會印出任何東西。

**其他 backend**：`AppKitBackend.swift:169` 設定 `window.contentMaxSize`；
`WinUIBackend.swift:343` 設定 `window.maximumContentSize`。兩者都遵從。

**GTK 4 是否可修**：**不行。** 程式碼已引用上游答案
（`https://discourse.gnome.org/t/how-to-build-fixed-size-windows-in-gtk-4/22807/10`），
註解也說得很直白：「GTK 不支援為 widget 設定最大尺寸。就是不支援。」`gtkwindow.h` 中沒有任何
內容與此相牴觸。

**該改的是什麼**：只有回報方式。這是本檔案中最清楚的一個例子——一個真實的平台限制，被正確地
偵測、正確地記錄，然後被廣播到一條沒有人在聽的頻道上。

---

## 15. `setRootEnvironmentChangeHandler(…)` never fires on a theme change — **refinement**, expensive **[src]**

`Sources/GtkBackend/GtkBackend.swift:863`

**Asked to do**: call the handler whenever the root environment changes, which
includes the desktop switching between light and dark.

**Actually does**: stores the handler (so it is *not* an empty body), and it does
fire on window activation via `createWindow`'s `notifyIsActive` (`:255`). It never
fires for a colour-scheme change: `ambientColorScheme` is sampled once at launch
(`:814`) and never re-read.

**Other backends**: `WinUIBackend.swift:403` hooks `actualThemeChanged` on the root
widget. AppKit gets it through the same notification machinery as #8.

**Fixable in GTK 4**: the TODO at `:866-887` is unusually informative and should be
read before anyone tries — subscribing to the `GtkSettings` notification was tried
and reverted, because the notification arrives inside GTK's own property-change
machinery and re-sampling has to build a window to read a themed colour; doing that
there crashed, and deferring it to the next main-loop turn crashed too. A fix needs
either a way to read the theme without building a widget, or a safe point in the
update cycle. **Do not treat this as a small change.** It is listed low for that
reason, not because it is unimportant.

---

**15. `setRootEnvironmentChangeHandler(…)` 在主題變更時從不觸發 — 嚴重度 refinement，成本高 [src]**

`Sources/GtkBackend/GtkBackend.swift:863`

**被要求做的事**：每當根環境改變時呼叫該 handler，其中包含桌面在淺色與深色之間切換。

**實際做的事**：它有儲存 handler（所以*不是*空實作），而且會透過 `createWindow` 的
`notifyIsActive`（`:255`）在視窗被啟動時觸發。它從不因配色變更而觸發：`ambientColorScheme`
只在啟動時取樣一次（`:814`），之後再也沒有重讀。

**其他 backend**：`WinUIBackend.swift:403` 在根 widget 上掛 `actualThemeChanged`；AppKit 透過
與 #8 相同的通知機制取得。

**GTK 4 是否可修**：`:866-887` 的 TODO 資訊量異常豐富，任何人動手前都該先讀——訂閱
`GtkSettings` 通知曾經嘗試並已回退，因為該通知抵達於 GTK 自身的屬性變更流程之中，而重新取樣
必須建立一個視窗才能讀到主題顏色；在該處建立會崩潰，延到主迴圈下一回合同樣崩潰。修復需要
「不建立 widget 即可讀取主題」的方法，或是更新週期中一個安全的時點。**不要把這當成小改動。**
它排在後面是因為這個理由，而不是因為它不重要。

---

## 16. `updateScrollContainer` discards `bounceHorizontally` / `bounceVertically` — **refinement**, documented-acceptable **[src]**

`Sources/GtkBackend/GtkBackend.swift:1177`

**Asked to do** (`ScrollContainers.swift:36-39`):

> `bounceHorizontally`: Whether the scroll view should 'bounce' horizontally. **Some
> backends ignore this, as it's not a universal concept.**

**Actually does**: forwards only `hasVerticalScrollBar` / `hasHorizontalScrollBar`
to `setScrollBarPresence`. Both bounce flags and the whole `environment` parameter
are unread.

**Other backends**: `AppKitBackend.swift:937` maps them to `verticalScrollElasticity`
/ `horizontalScrollElasticity`. `WinUIBackend.swift:1030` also ignores bounce and
instead sets rails and scroll modes — so GTK is one of two that ignore it.

**Fixable in GTK 4**: partially. GTK 4 has kinetic scrolling
(`gtk_scrolled_window_set_kinetic_scrolling`, `gtkscrolledwindow.h:143`) and an
edge-overshoot effect, but no per-axis switch for the overshoot itself, so this
cannot be expressed exactly.

**Listed for completeness, not as a bug.** The protocol explicitly sanctions
ignoring it, which makes this a documented divergence rather than a silent one.
Included because "scroll" is one of the four areas the issue names and this is the
whole of what is missing there besides #11.

---

**16. `updateScrollContainer` 丟棄 `bounceHorizontally` ／ `bounceVertically` — 嚴重度 refinement，屬文件允許 [src]**

`Sources/GtkBackend/GtkBackend.swift:1177`

**被要求做的事**（`ScrollContainers.swift:36-39`）：「`bounceHorizontally`：捲動視圖是否應在
水平方向『回彈』。**部分 backend 會忽略此項，因為它並非普遍存在的概念。**」

**實際做的事**：只把 `hasVerticalScrollBar` ／ `hasHorizontalScrollBar` 轉交給
`setScrollBarPresence`。兩個回彈旗標與整個 `environment` 參數都未被讀取。

**其他 backend**：`AppKitBackend.swift:937` 把它們對映到 `verticalScrollElasticity` ／
`horizontalScrollElasticity`；`WinUIBackend.swift:1030` 同樣忽略回彈，改為設定 rail 與捲動
模式——因此 GTK 是兩個忽略者之一。

**GTK 4 是否可修**：部分可以。GTK 4 有動能捲動
（`gtk_scrolled_window_set_kinetic_scrolling`，`gtkscrolledwindow.h:143`）與邊緣過捲效果，但
沒有針對過捲本身的逐軸開關，因此無法精確表達。

**列於此僅為求完整，並非 bug。** protocol 明確許可忽略它，這使它成為有文件依據的分歧而非靜默
的分歧。收錄的原因是「捲動」是 issue 點名的四個領域之一，而除了 #11 之外，那裡缺的就只有這個。

---

## 17. `baseItemPadding(ofSelectableListView:)` returns all zeros — **refinement**, verify first **[src]**

`Sources/GtkBackend/GtkBackend.swift:1207`

**Asked to do**: report the padding the backend's list rows already have, so
SwiftCrossUI's layout can account for it.

**Actually does**: returns `SwiftCrossUI.EdgeInsets()` — zero on all four edges.

**Other backends**: `AppKitBackend.swift:977` returns `leading: 8, trailing: 8` with
a TODO admitting they are empirical figures. `WinUIBackend.swift:1070` returns
`top: 8, bottom: 8, leading: 16, trailing: 12`.

**Zero may well be honest here** — unlike the other two, this backend actively
zeroes list padding in the global CSS installed at `:172-209`:

```css
list > row { padding: 0; min-height: 0; }
.navigation-sidebar { margin: 0; padding: 0; }
.navigation-sidebar > row { margin: 0; padding: 0; }
```

So GtkBackend is the one backend entitled to answer zero. **Verify before changing
anything**: if the CSS above is complete then this entry is not a defect at all and
should be struck; if the theme adds padding through a node those selectors miss,
rows will be misaligned by a few points with no other symptom. The companion
`minimumRowSize` at `:1213` returning `.zero` matches AppKit exactly and is not
suspicious.

---

**17. `baseItemPadding(ofSelectableListView:)`回傳全零 — 嚴重度 refinement，請先驗證 [src]**

`Sources/GtkBackend/GtkBackend.swift:1207`

**被要求做的事**：回報此 backend 的清單列本身已有的內距，好讓 SwiftCrossUI 的版面計算能把它
算進去。

**實際做的事**：回傳 `SwiftCrossUI.EdgeInsets()`——四邊皆為零。

**其他 backend**：`AppKitBackend.swift:977` 回傳 `leading: 8, trailing: 8`，並以 TODO 承認那是
經驗值；`WinUIBackend.swift:1070` 回傳 `top: 8, bottom: 8, leading: 16, trailing: 12`。

**在此回答零很可能是誠實的**——與另外兩者不同，此 backend 在 `:172-209` 安裝的全域 CSS 中主動
把清單內距歸零。因此 GtkBackend 是唯一有資格回答零的 backend。**改動前請先驗證**：若上述 CSS
已完備，本條根本不是缺陷、應予刪除；若主題透過那些選擇器沒涵蓋到的節點加上了內距，列會偏移
幾個點，且沒有其他症狀。同組的 `:1213` `minimumRowSize` 回傳 `.zero`，與 AppKit 完全一致，
並不可疑。

---

## 18. `menubarHeight(ofWindow:)` hardcodes 25 points — **refinement**, small **[src]**

`Sources/GtkBackend/GtkBackend.swift:361`

```swift
if window.showMenuBar {
    // TODO: Don't hardcode this (if possible), because some Gtk
    //   themes may affect the height of the menu bar.
    25
} else {
    0
}
```

Used by `setSize(ofWindow:to:)` (`:386`) to add the menu bar's height on top of the
requested content height. Under a theme whose menu bar is not 25pt tall, every
window with an application menu is that many points too tall or too short, and the
content is offset to match. Silent.

**Other backends**: not applicable — AppKit's menu bar is not in the window, and
WinUI has no equivalent.

**Fixable in GTK 4**: yes. The menu bar is a widget; measure its natural height
rather than guessing. Small, but needs a handle on the widget from `Gtk.Window`.

---

**18. `menubarHeight(ofWindow:)` 寫死 25 點 — 嚴重度 refinement，成本小 [src]**

`Sources/GtkBackend/GtkBackend.swift:361`

由 `setSize(ofWindow:to:)`（`:386`）使用，將選單列高度加到所要求的內容高度之上。在選單列不是
25pt 高的主題下，每個帶有應用程式選單的視窗都會高出或矮上那麼多點，內容也隨之偏移。靜默無聲。

**其他 backend**：不適用——AppKit 的選單列不在視窗內，WinUI 沒有對應物。

**GTK 4 是否可修**：可以。選單列就是一個 widget，量測它的自然高度即可，不必猜。改動小，但需要
從 `Gtk.Window` 取得該 widget 的 handle。

---

## 19. Escape on an alert does nothing at all — **refinement**, needs a design decision **[src]**

`Sources/GtkBackend/GtkBackend.swift:2078-2086` (the shortcut controller) and
`:2128-2135` (the response guard)

`createAlert` installs a shortcut controller whose Escape handler returns `1`
(handled) and does nothing, and `present` additionally guards against response id
`-4` (`GTK_RESPONSE_DELETE_EVENT`) with:

> Ignore escape key for now. Once we support detecting the primary and secondary
> actions of alerts we can wire this up to whichever action is the default
> cancellation action.

So Escape on a GTK alert is inert. On every desktop convention it should pick the
cancel action.

**Other backends**: `AppKitBackend.swift:1379-1383` guards `.abort`/`.cancel`
similarly, so this is not a GTK-only divergence.

**Fixable in GTK 4**: yes mechanically, but the blocker is the one the comment
names — `updateAlert` receives only `actionLabels: [String]`
(`BackendFeatures/Alerts.swift`), with no marker for which is the cancel action, so
no backend can wire Escape correctly today. That is a protocol change, not a
backend fix, which is why this sits near the bottom.

---

**19. 對 alert 按 Escape 完全沒有反應 — 嚴重度 refinement，需要設計決策 [src]**

`Sources/GtkBackend/GtkBackend.swift:2078-2086`（快捷鍵控制器）與 `:2128-2135`（回應守衛）

`createAlert` 安裝了一個快捷鍵控制器，其 Escape 處理器回傳 `1`（表示已處理）卻什麼都不做；
`present` 另外守衛了回應 id `-4`（`GTK_RESPONSE_DELETE_EVENT`），註解寫著「目前先忽略 Escape
鍵。等到我們支援偵測 alert 的主要與次要動作之後，就能把它接到預設的取消動作上。」

因此在 GTK 的 alert 上按 Escape 毫無作用。依各桌面慣例，它應該選取取消動作。

**其他 backend**：`AppKitBackend.swift:1379-1383` 同樣守衛 `.abort`／`.cancel`，因此這並非
GTK 專屬的分歧。

**GTK 4 是否可修**：機制上可以，但阻礙就是註解所點名的那件事——`updateAlert` 只收到
`actionLabels: [String]`（`BackendFeatures/Alerts.swift`），沒有任何標記指出哪一個是取消動作，
因此今天沒有任何 backend 能正確接上 Escape。那是 protocol 的改動而非 backend 的修復，所以本條
排在接近末尾。

---

## 20. `updateWebView` / `navigateWebView` are true no-ops — **broken** by design, correctly handled **[src]**

`Sources/GtkBackend/GtkBackend+WebView.swift:66` and `:78`

Both have empty bodies. Listed so the map is complete, and **explicitly not a
defect of the kind this survey is hunting**: `createWebView` (`:45`) returns a
labelled `Gtk.Label` reading *"WebView is not available in this build (GtkBackend
has no WebKitGTK)"*, so the degradation is visible to the author on screen. The
file's own header explains the choice, and it is the pattern the rest of this
document keeps recommending:

> A labelled placeholder is preferred over a silent blank -- a blank area looks
> like a layout bug, whereas the text says which feature is missing and why.

**Other backends**: `AppKitBackend+WebView.swift` implements it for real.
WinUIBackend does not conform to `WebViews` at all.

**Fixable in GTK 4**: yes, with WebKitGTK — which means adding `webkitgtk-6.0` to
`Package.swift` as a system dependency and changing what everyone building this
project must have installed. A packaging decision, tracked upstream as issue 148
(`testapp/issues.csv`).

---

**20. `updateWebView` ／ `navigateWebView` 是真正的 no-op — 設計上 broken，但處理正確 [src]**

`Sources/GtkBackend/GtkBackend+WebView.swift:66` 與 `:78`

兩者皆為空實作。列於此是為求完整，而且**明確不屬於本次調查所要獵捕的那種缺陷**：
`createWebView`（`:45`）回傳一個帶文字的 `Gtk.Label`，內容為「WebView is not available in this
build (GtkBackend has no WebKitGTK)」，因此降級在畫面上對作者是可見的。該檔案的抬頭註解說明了
這個選擇，而那正是本文件一再推薦的模式：「有文字說明的佔位優於靜默空白——空白區域看起來像版面
bug，而文字會說出缺少的是哪一個功能、以及原因。」

**其他 backend**：`AppKitBackend+WebView.swift` 有真正的實作；WinUIBackend 則完全沒有 conform
`WebViews`。

**GTK 4 是否可修**：可以，用 WebKitGTK——那意味著要把 `webkitgtk-6.0` 加入 `Package.swift`
作為系統相依，並改變每一位建置本專案者必須安裝的東西。這是封裝決策，上游以 issue 148 追蹤
（`testapp/issues.csv`）。

---

## 21. Dead code that reads like an unimplemented feature — **refinement**, deletion only **[src]**

Two places will mislead the next person grepping this file for TODOs:

- `Sources/GtkBackend/GtkBackend.swift:1463-1532` — a 70-line commented-out table
  implementation headed `// TODO: Implement tables`. **Tables are implemented**, at
  `:2694-2723`, against a real `Gtk.Table` widget, including `setTextSelectability`
  which neither AppKitBackend nor WinUIBackend implements (they take the no-op
  default at `Tables.swift:95`). The commented block is stale and its TODO is false.
- `Sources/GtkBackend/InspectionModifiers.swift:49` — `Picker.inspect` commented out
  behind `// TODO(stackotter): Repair Picker.inspect implementations post PickerStyle
  refactor`. Real, but it affects test support only, not app behaviour. Note that
  the pickers themselves are complete: `SegmentedPicker` (`:3223`) and
  `RadioGroupPicker` (`:3332`) both handle grouping, nil selection and the
  programmatic-vs-user distinction.

Not deleted here — this survey does not edit `Sources/`. Flagged because a false
TODO costs the next reader the same time a real one does.

---

**21. 讀起來像未實作功能的死碼 — 嚴重度 refinement，只需刪除 [src]**

有兩處會誤導下一個 grep 本檔案 TODO 的人：

- `Sources/GtkBackend/GtkBackend.swift:1463-1532`——一段 70 行、被註解掉的表格實作，開頭寫著
  `// TODO: Implement tables`。**表格已經實作了**，位於 `:2694-2723`，基於真正的 `Gtk.Table`
  widget，其中甚至包含 AppKitBackend 與 WinUIBackend 都沒有實作的 `setTextSelectability`
  （它們採用 `Tables.swift:95` 的 no-op 預設）。該註解區塊已過時，其 TODO 是假的。
- `Sources/GtkBackend/InspectionModifiers.swift:49`——`Picker.inspect` 被註解掉，前面掛著
  `// TODO(stackotter): Repair Picker.inspect implementations post PickerStyle refactor`。
  這一條是真的，但它只影響測試支援，不影響 app 行為。附帶一提，picker 本身是完整的：
  `SegmentedPicker`（`:3223`）與 `RadioGroupPicker`（`:3332`）都處理了分組、nil 選取，以及
  「程式設定」與「使用者操作」的區辨。

此處不予刪除——本次調查不修改 `Sources/`。之所以標出，是因為一個假的 TODO 會耗掉下一位讀者
與真 TODO 同樣多的時間。

---

# Appendix: checked and found not to be defects / 附錄：查過、確認不是缺陷

Recorded so nobody spends the time twice. Each of these looks like a silent no-op
and is not.

記錄於此，以免有人重複花時間。以下每一項看起來都像靜默 no-op，實際上不是。

| # | Symbol | Why it is fine | 為何沒問題 |
|---|---|---|---|
| A1 | `updatePath(_:_:bounds:pointsChanged:environment:)` `:2495` — body is one line, three parameters unread | The draw function installed by `renderPath` (`:2518`) re-reads `path.path` on every frame, so storing the source is the whole job. `bounds` exists for AppKit's flipped y axis; `pointsChanged` is an optimisation hint. | `renderPath`（`:2518`）安裝的繪製函式每一幀都重讀 `path.path`，因此存下 source 就是全部工作。`bounds` 是為 AppKit 的翻轉 y 軸而存在；`pointsChanged` 只是最佳化提示。 |
| A2 | `updateAlert` `:2091` adds buttons in a loop — looks like it would duplicate them on every update | `BackendFeatures/Alerts.swift` states *"Can only be called once."* | `BackendFeatures/Alerts.swift` 明文寫著「只能被呼叫一次」。 |
| A3 | `updateSwitch` `:1589` / `updateCheckbox` `:1613` apply no font or colour from the environment | Neither widget draws text — SwiftCrossUI composes the label separately. `AppKitBackend.swift:725`/`:779` do exactly the same, setting only `isEnabled`. | 兩個 widget 都不繪製文字——標籤由 SwiftCrossUI 另行組合。`AppKitBackend.swift:725`／`:779` 做法完全相同，只設定 `isEnabled`。 |
| A4 | `updateImageView` `:1429` ignores `targetWidth` / `targetHeight` | The protocol (`Images.swift`) says *"backends that don't have to manually scale the underlying pixel data can safely ignore this parameter."* `AppKitBackend.swift:1126` ignores them too. | protocol（`Images.swift`）寫著「不需手動縮放底層像素資料的 backend 可以安全地忽略此參數」。`AppKitBackend.swift:1126` 也忽略它們。 |
| A5 | `updateSheet` `:2861` ignores `detents` and `dragIndicatorVisibility` | Both are mobile-only concepts and the code says so at `:2894-2895`. | 兩者都是行動平台專屬概念，程式碼在 `:2894-2895` 已如此說明。 |
| A6 | `updateButton` `:1546` carries `// TODO: Update button label color using environment` | Appears **stale**. `cssProperties` does append `.foregroundColor` (`:2768`), and CSS `color` inherits into the button's label node. Verify with a coloured button, then delete the TODO. | 看起來**已過時**。`cssProperties` 確實有加上 `.foregroundColor`（`:2768`），而 CSS 的 `color` 會繼承到按鈕的 label 節點。以一個上色按鈕驗證後，把 TODO 刪掉。 |
| A7 | `size(of:whenDisplayedIn:…)` `:1366` measures via the widget's Pango context, which could lag the CSS | `Text.computeLayout` (`Sources/SwiftCrossUI/Views/Text.swift:78-82`) deliberately calls `updateTextView` *before* measuring, with a comment naming GtkBackend as the reason. The ordering is already handled. **This does not cover #10**, whose label is never updated through that path. | `Text.computeLayout`（`Sources/SwiftCrossUI/Views/Text.swift:78-82`）刻意在量測*之前*呼叫 `updateTextView`，其註解點名 GtkBackend 就是原因。順序已被處理。**這並不涵蓋 #10**，該 label 從不經由這條路徑更新。 |

---

# Coverage note / 涵蓋範圍說明

GtkBackend conforms to every `BackendFeatures` protocol except `AttachedMenus`, and
that is correct rather than a gap: `Menus.swift` states *"You only need to write a
conformance to one of `AttachedMenus` or `PopoverMenus`"*, and GtkBackend implements
`PopoverMenus` (WinUIBackend picks the other one). Enumerated by cross-referencing
the conformance list at `GtkBackend.swift:23-48` against every `public protocol` in
`Sources/SwiftCrossUI/Backend/BackendFeatures/`.

GtkBackend 除了 `AttachedMenus` 之外 conform 了每一個 `BackendFeatures` protocol，而那是正確
的、不是缺口：`Menus.swift` 寫著「你只需要為 `AttachedMenus` 或 `PopoverMenus` 其中之一撰寫
conformance」，而 GtkBackend 實作的是 `PopoverMenus`（WinUIBackend 選了另一個）。此結論由
`GtkBackend.swift:23-48` 的 conformance 清單，對照 `Sources/SwiftCrossUI/Backend/BackendFeatures/`
中每一個 `public protocol` 交叉比對而得。

Regenerate the TODO census with:
以下列指令重新產生 TODO 清點：

```zsh
grep -n "TODO\|FIXME\|not supported\|no-op\|does nothing\|unimplemented" Sources/GtkBackend/*.swift
```

At the time of writing that returns 19 lines across 4 files.
撰寫當下該指令回傳 4 個檔案共 19 行。
