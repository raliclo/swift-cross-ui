# Parity gaps: what is actually left, measured 2026-09-08

# 平價落差盤點：實際還剩什麼，2026-09-08 實測

A re-census of the twelve todo entries that describe SwiftUI-parity gaps. Every
fraction those entries record ("4/6 done", "8 of 11", "only a Settings scene
remains") predates 2026-09-01 and is therefore older than seven days. One entry
of the original thirteen — #86, the symbol API — was already fully implemented
on all five backends before this survey started, which is why it is not in the
table below.

**Nothing was implemented for this document. It is read-only on all Swift
sources.**

本文件重新盤點十二筆描述「與 SwiftUI 落差」的 todo 條目。那些條目所記的每一個分數（「4/6 完成」、
「11 個中的 8 個」、「只剩一個 Settings scene」）都早於 2026-09-01，因此全部超過七天。原本十三筆
之中的 #86（符號 API）在本次盤點開始前就已於五個 backend 全數實作完成，故不列入下表。

**本文件未實作任何東西，對所有 Swift 原始碼皆為唯讀。**

---

## Method / 方法

Two greps, both file-counting so they cannot be truncated into looking complete.
Run from the repository root.

兩種 grep，皆以「檔案數」計數，因此不會被截斷成「看起來很完整」的樣子。於 repo 根目錄執行。

**Reference count** — does the name appear anywhere:
**引用計數**——該名稱是否出現於任何位置：

```zsh
for n in VStack onTapGesture padding onHover ZZZNotARealSymbol; do
  printf '%-24s %s\n' "$n" \
    "$(grep -rlE "\b$n\b" Sources/SwiftCrossUI --include=*.swift | wc -l)"
done
```

**Declaration count** — is the name actually declared, not merely mentioned in
a comment:
**宣告計數**——該名稱是否真的被宣告，而非只在註解中被提及：

```zsh
for n in Form Section Label Stepper LazyVStack LazyHStack LazyVGrid Grid \
         ScrollViewReader ControlGroup GroupBox Gauge ColorPicker \
         DisclosureGroup LabeledContent Link; do
  printf '%-18s %s\n' "$n" \
    "$(grep -rlE "(struct|protocol|enum) $n\b" Sources/SwiftCrossUI --include=*.swift | wc -l)"
done
```

**The controls were run first and both answered.** Reference count, measured
2026-09-08: `VStack` 19, `onTapGesture` 2, `padding` 14, `onHover` 4,
`ZZZNotARealSymbol` **0**. A wall of zeros from a broken pattern is
indistinguishable from a real gap, and this tree has been caught by exactly that
three times.

**兩組控制組都先跑過，也都給出答案。** 引用計數，2026-09-08 實測：`VStack` 19、`onTapGesture` 2、
`padding` 14、`onHover` 4、`ZZZNotARealSymbol` **0**。壞掉的樣式所產生的一整片 0，與真正的缺口
看起來一模一樣，而本倉庫已經被這件事抓到過三次。

**Backend conformance** is not visible from `grep "BackendFeatures.X" Sources/<b>/`
alone. `AppKitBackend` conforms to `FullAppBackend`
(`Sources/AppKitBackend/AppKitBackend.swift:22`), which is a composition of
every feature protocol, so a per-file grep reports zero for it while it in fact
implements everything. `AndroidBackend` declares only `BaseAppBackend`
(`Sources/AndroidBackend/AndroidBackend.swift:133`) and picks the rest up in
`extension AndroidBackend: BackendFeatures.X` files. Both routes were checked.

**backend 的 conformance 無法只靠 `grep "BackendFeatures.X" Sources/<b>/` 看出來。**
`AppKitBackend` 宣告的是 `FullAppBackend`（`Sources/AppKitBackend/AppKitBackend.swift:22`），
那是所有 feature protocol 的合成，因此逐檔 grep 會對它回報 0，而它實際上全部都實作了。
`AndroidBackend` 只宣告 `BaseAppBackend`（`Sources/AndroidBackend/AndroidBackend.swift:133`），
其餘由 `extension AndroidBackend: BackendFeatures.X` 檔案補上。兩條路徑都已檢查。

---

## Summary table / 總表

Five shipped backends: **G** = GtkBackend, **W** = WinUIBackend, **A** =
AppKitBackend, **U** = UIKitBackend, **N** = AndroidBackend.
`—` means the entry needs nothing from a backend; `n/a` means the framework type
does not exist, so no backend can conform to anything.

五個已發布 backend：**G** = GtkBackend、**W** = WinUIBackend、**A** = AppKitBackend、
**U** = UIKitBackend、**N** = AndroidBackend。`—` 表示該條目不需要 backend 做任何事；
`n/a` 表示框架端的型別根本不存在，因此沒有任何 backend 有東西可以 conform。

| # | recorded claim | reality on 2026-09-08 | what actually remains | G | W | A | U | N |
|---|---|---|---|---|---|---|---|---|
| **#85** | make LazyVStack/LazyHStack lazy, add LazyVGrid | both stacks **exist and are honestly documented as eager** — `LazyStacks.swift:38`, `:70`, and the doc comment at `:3` says so in both languages. `LazyVGrid` declaration count was **0**; **added 2026-09-08** ~~in the same file~~ — **corrected 2026-09-08: it is in its own file, `Views/LazyVGrid.swift:68`**, see the note under #85 — and it is eager for the same reason the stacks are — no lazier than its siblings | real laziness, and *only* that (needs ScrollView to report its visible rect into the layout pass). The `LazyVGrid` half is done; it is pure composition and took no backend requirement | — | — | — | — | — |
| **#88** | ColorPicker as an opt-in BackendFeatures protocol | ~~`grep -rn "ColorPicker" Sources/` → **0**, across every file type, not only `*.swift`~~ **→ 1 as of `e6165e8a` (2026-09-08 04:36), `Views/ColorPicker.swift:39`**; but `grep -rl "ColorPickers" Sources/` is still **0** | ~~everything~~ **the protocol half only**: `BackendFeatures.ColorPickers` and five conformances. The view exists and is composed from `HStack`/`Slider`/`Button`, needing no backend — see #88's detail for why the native panel was deferred rather than missed | n/a | n/a | n/a | n/a | n/a |
| **#28** | animation and transitions, "no protocol at all" | **claim holds exactly.** `withAnimation` 0, `struct Animation` 0, `AnyTransition` 0, `func transition` 0, `Transition` 0 | all five names, plus a driver in the view graph and a per-backend animator | n/a | n/a | n/a | n/a | n/a |
| **#30** | focus, accessibility, keyboard shortcuts | **claim holds.** `FocusState` 0, `func focused` 0, `keyboardShortcut` 0, `accessibilityLabel` 0, `\bFocus\b` 0. The single `accessibility` hit is prose in `HelpModifier.swift` | the whole area. Still the only area where an application cannot express the intent | n/a | n/a | n/a | n/a | n/a |
| **#32** | gestures beyond tap and hover | the new gestures are absent as claimed — `DragGesture` 0, `LongPressGesture` 0, `MagnificationGesture` 0, `RotationGesture` 0, `simultaneousGesture` 0, `\bGesture\b` 0. **But the premise is wrong: hover is not done on five backends** | the five gesture types, *and* `HoverGestures` on AndroidBackend — see the flag below | ✅ | ✅ | ✅ | ✅ | ❌ hover |
| **#34** | API shapes that do not compile from SwiftUI code | audited 2026-08-27, "all ten claims still stand". **Eight still stand. Claim 4 is now false and claim 2 is half false** | claims 1, 3, 5, 6, 7, 8, 9, 10 | — | — | — | — | — |
| **#36** | confirmationDialog and safeAreaInset done, four remain | both are real: `ConfirmationDialogModifier.swift:50`, `SafeAreaInsetModifier.swift:39`. `func popover` 0, `fullScreenCover` 0, `toolbar` 0, `refreshable` 0, and `navigationTitle` **0 as a modifier** | **Re-measured 2026-09-08: `.popover` and `.navigationTitle` landed.** ~~Left: `.fullScreenCover`, `.toolbar`, `.refreshable`.~~ **Corrected later the same day: `.fullScreenCover` landed too** (`Modifiers/FullScreenCoverModifier.swift:28`), so left: `.toolbar`, `.refreshable`. `.navigationTitle` had left the denominator without being implemented, and is counted from here on | ✅ popover, built | ✅ popover, built | ⚠️ written, UNCOMPILED | ⚠️ written, UNCOMPILED | ⚠️ written, UNCOMPILED |
| **#27** | follow desktop light/dark while running (GtkBackend) | **claim holds, and the mechanism is already built.** `Gtk.Settings.registerNotification(named:handler:)` exists at `Sources/Gtk/Utility/Settings.swift:92` and **has zero callers** across `Sources/`. The ambient scheme is sampled **once**, at `GtkBackend.swift:1029` | wire the notification up (six changes, per the task history). Windows has the same shape from the other side: `systemColorScheme` reads the registry once inside `sampleAmbientColorScheme` and `grep -rn WM_SETTINGCHANGE Sources/` → **0** | ❌ | — | — | — | — |
| **#31** | 4/6 done, only ButtonStyle and LabelStyle remain | **5 present, and the denominator shrank silently.** `ShapeStyle` is a real protocol at `Styles/ShapeStyle/ShapeStyle.swift:25` with `Color`, `LinearGradient` and `RadialGradient` conforming — the todo still says "absent — 0 declarations and 0 references". `TextFieldStyle` 0 and `ProgressViewStyle` 0 were on the 2026-09-01 list and quietly left the count | `ButtonStyle` (genuinely blocked: `isPressed` 0 across `Sources/`, `Button.label` is a `String` at `Button.swift:17`), `LabelStyle` (**blocker gone**), `TextFieldStyle`, `ProgressViewStyle` | — | — | — | — | — |
| **#33** | 8 of 11 done, ColorPicker/LazyVGrid/ScrollViewReader remain | was **10 present of a 16-name list, 6 absent** — three names the 2026-09-01 census counted absent (`Grid`, `ControlGroup`, `GroupBox`) had left the denominator without being implemented. ~~**Now 14 of 16**~~ ~~**15 of 16, re-derived 2026-09-09**~~ **16 of 16, re-derived 2026-09-09 after `ScrollViewReader` landed the same day**: those three plus `LazyVGrid` landed 2026-09-08, `ColorPicker` landed the same day in `e6165e8a` at `Views/ColorPicker.swift:39`, and `ScrollViewReader` landed in `Views/ScrollViewReader.swift` with the new requirement on all five backends. Regenerate with the shape-agnostic loop under #33's detail below; do not restate the number without running it. The recorded "8 of 11" was never true and should not be restated | ~~`ScrollViewReader` and `ColorPicker`~~ ~~`ScrollViewReader` — the only one of the sixteen that is not composition, and the expensive one: `BackendFeatures.ScrollContainers` has only `createScrollContainer` and `updateScrollContainer` and **no programmatic scroll**, so it needs a new requirement on all five~~ **none — the list is closed.** The requirement that row asked for is `scrollContainer(_:to:anchor:)`, implemented on all five backends and driven by `actions/win/P34-scroll-to-row-50.csv` and by P56; see the detail row below rather than this cell, which is the one that was left contradicting it. **一個已完成的項目留在「尚存」欄位裡，讀起來與「還沒做」完全相同。** | n/a | n/a | n/a | n/a | n/a |
| **#35** | StateObject and ObservedObject done, only a Settings scene remains | both wrappers are real — `StateObject.swift:49`, `ObservedObject.swift:40`. **"Only a Settings scene" is wrong: three more things are absent.** `EnvironmentObject` 0, `SceneStorage` 0, `struct Settings` 0, `DocumentGroup` 0 | `EnvironmentObject`, `SceneStorage`, the `Settings` scene, `DocumentGroup` | n/a | n/a | n/a | n/a | n/a |
| **#79** | `correctContentSizeIfNeeded` is a no-op | **the function no longer exists.** `grep -rn "correctContentSizeIfNeeded" Sources/ --include=*.swift` returns **two hits, both inside a doc comment**. It was renamed to `reportContentSizeShortfall` and the assignment deleted in `aca6e259` | the **defect** is live: GTK still delivers 39px less content height than requested. The *description* is stale; the *bug* is not | ❌ | — | — | — | — |

---

## Detail, entry by entry / 逐條細節

### #86 — already done before this survey, and the todo still called it a gap

`BackendFeatures.Symbols` is at
`Sources/SwiftCrossUI/Backend/BackendFeatures/PassiveViews/Symbols.swift:33`,
and it is **not** opt-in: `PassiveViews = TextViews & Images & Symbols`
(`PassiveViews/PassiveViews.swift:9`) is part of `BaseAppBackend`
(`Backend/BaseAppBackend.swift:15`), so every backend has it and the default
implementation draws `SystemSymbol.textFallback` rather than nothing.

All five override it:

| backend | file |
|---|---|
| GtkBackend | `Sources/GtkBackend/GtkBackend+Symbols.swift:33` |
| WinUIBackend | `Sources/WinUIBackend/WinUIBackend+Symbols.swift:32` |
| AppKitBackend | `Sources/AppKitBackend/AppKitBackend+Symbols.swift:21` |
| UIKitBackend | `Sources/UIKitBackend/UIKitBackend+Symbols.swift:18` |
| AndroidBackend | `Sources/AndroidBackend/AndroidBackend+Symbols.swift:43` |

Regenerate:
`for b in Gtk WinUI AppKit UIKit Android; do printf '%s %s\n' "$b" "$(grep -rln createSymbolView Sources/${b}Backend --include=*.swift | wc -l)"; done`

`#86` 早在本次盤點之前就已完成，而 todo 仍將它列為缺口。`BackendFeatures.Symbols` 並非 opt-in：
它經由 `PassiveViews` 併入 `BaseAppBackend`，因此每個 backend 都有它，預設實作會畫
`SystemSymbol.textFallback` 而不是什麼都不畫；五個 backend 全部覆寫了它。

---

### #85 — the stacks exist, and the file says louder than the todo that they are not lazy

`LazyVStack` at `Sources/SwiftCrossUI/Views/LazyStacks.swift:38`, `LazyHStack`
at `:70`. Both bodies are a plain `VStack`/`HStack`. The doc comment at `:3`
already states the gap in both languages, including the reason it was shipped
eager: *"SwiftUI source that says `LazyVStack` should compile and should look
right… An eager stack is the correct picture and the wrong performance;
refusing to compile is neither."*

`LazyVGrid` declaration count was **0**, and `GridItem` reference count **0**
(`grep -rn GridItem Sources/SwiftCrossUI --include=*.swift | wc -l`), so a grid
needed the item type too, not only the container.

**Done 2026-09-08.** ~~`LazyVGrid` now sits beside its siblings in
`Views/LazyStacks.swift`, with `GridItem` in `Views/GridItem.swift`.~~ It took no
backend requirement, as predicted.

**Correction, 2026-09-08 — the two file paths above were true when written and
are now wrong.** `LazyVGrid` is at `Sources/SwiftCrossUI/Views/LazyVGrid.swift:68`
and `GridItem` at `LazyVGrid.swift:16`; `LazyStacks.swift` holds `LazyVStack`
and `LazyHStack` and nothing else, and `Views/GridItem.swift` **no longer
exists**. The cause is worth keeping because it is not a typo: **both
`LazyVGrid` implementations existed simultaneously until the merge `dea9ccff`,
and this side's was the one removed.** A measurement can be correct on the day
and be deleted by a merge the next, without the document that records it
changing at all.

Regenerate:
`grep -rn "struct GridItem\|struct LazyVGrid\|struct LazyVStack\|struct LazyHStack" Sources/SwiftCrossUI --include=*.swift`

**更正，2026-09-08——上方那兩個檔案路徑在寫下當時為真，如今已錯。** `LazyVGrid` 位於
`Sources/SwiftCrossUI/Views/LazyVGrid.swift:68`，`GridItem` 位於 `LazyVGrid.swift:16`；
`LazyStacks.swift` 只剩 `LazyVStack` 與 `LazyHStack`，而 `Views/GridItem.swift` **已不存在**。
成因值得記下，因為它不是筆誤：**兩份 `LazyVGrid` 實作一直同時存在，直到合併 `dea9ccff`，
而被移除的是本側那一份。** 一項量測可以在當天正確，隔天就被一次合併刪掉，而記錄它的文件
卻絲毫未變。

**It is not lazier than `LazyVStack`, and the doc comment says so first.** If
anything it is the more eager of the two: it cannot decide how many rows there
are without counting every cell, so it materialises all of them by construction
rather than merely by omission. Nobody should read "we shipped LazyVGrid" as
progress on the laziness half — that half is untouched.

~~Flowing a `@ViewBuilder` block into columns needed one piece of framework
machinery that did not exist: `GridCellsProviding` in `Views/GridCells.swift`,
a value-level flattener modelled on `View/_asMenuItems` (the only other one in
the project). Without it a three-column grid renders as one column, which is the
wrong picture rather than a documented divergence. Still no backend involved.~~

**Correction, 2026-09-08 — this paragraph is stale twice over, and the second
half is the instructive one.** The file `Views/GridCells.swift` is gone with the
rest of this side's `LazyVGrid` in `dea9ccff`, *and* the type `GridCellsProviding`
no longer exists anywhere: `grep -rn GridCellsProviding Sources/` → **0**. So the
surviving `LazyVGrid` flows a `@ViewBuilder` block into columns without a
value-level flattener at all, and the conclusion this paragraph drew — that a new
piece of framework machinery was unavoidable — was never a fact about the
problem, only about the implementation that got deleted. **A file path going
stale is visible the moment someone opens it; a load-bearing claim about what the
work "needed" survives the deletion and keeps being quoted.**

Regenerate: `grep -rn GridCellsProviding Sources/ | wc -l` → 0

**更正，2026-09-08——本段有兩重過時，而第二重才是有教訓的那一重。** 檔案 `Views/GridCells.swift`
已隨本側 `LazyVGrid` 的其餘部分在 `dea9ccff` 中消失，**而且**型別 `GridCellsProviding` 已不存在於
任何位置：`grep -rn GridCellsProviding Sources/` → **0**。因此存活下來的 `LazyVGrid` 根本沒有
任何值層級攤平器就把 `@ViewBuilder` 區塊流排成欄；本段所下的結論——「一項新的框架機制無可避免」
——從來就不是關於問題本身的事實，而只是關於那份被刪掉的實作。**檔案路徑過時，只要有人打開就會
發現；但一句關於「這件工作需要什麼」的關鍵主張，會在刪除之後存活下來並持續被引用。**

**What remains under #85 is real laziness, and only that** — a change to the
layout system, with `ScrollView` reporting its visible rect into the layout
pass. Shared code, no backend.

兩個 stack 都存在（`LazyStacks.swift:38`、`:70`），且該檔案的說明比 todo 更明確地指出它們並非惰性。
`LazyVGrid` 宣告計數原為 0，`GridItem` 引用計數也是 0；**兩者皆於 2026-09-08 完成**，且如預期般
未觸及任何 backend。（更正：兩者現位於 `Views/LazyVGrid.swift:68` 與 `:16`，不在 `LazyStacks.swift`。）

`LazyVGrid` **並不比 `LazyVStack` 更惰性**，其文件註解一開頭就說明了這點；若真要比較，它還更積極
求值——不先數過每一個儲存格，它就無法決定共有幾列。切勿把「LazyVGrid 已完成」讀作惰性那一半有了
進展：那一半完全未動。

~~把 `@ViewBuilder` 區塊流排成欄，需要一項原本不存在的框架機制：`Views/GridCells.swift` 中的
`GridCellsProviding`，一個仿照 `View/_asMenuItems`（本專案中唯一另一個同類機制）的值層級攤平器。
少了它，三欄的網格會畫成一欄——那是**錯的畫面**，而非一項有記載的差異。此機制同樣不涉及任何 backend。~~
（已於 2026-09-08 更正，見上方英文更正段：該檔案與該型別皆已不存在。）

#85 尚存的部分是真正的惰性，且僅此一項——那是對版面系統的改動，需由 `ScrollView` 把可視矩形回報
進版面計算流程。屬共用程式碼，不涉及 backend。

---

### #88 — the view landed by composition; the native-panel protocol did not

~~`grep -rn "ColorPicker" Sources/` returns **0** — across every file, not only
`*.swift`. (The 23-file hit for the same string across the repository is
`testapp/gtk4-source/`, a vendored copy of GTK's own C sources, plus test-app
and doc files. None of it is SwiftCrossUI.)~~

~~What is needed is stated in the entry itself and is accurate: a `ColorPicker`
view, a `BackendFeatures.ColorPickers` protocol, and five conformances. Nothing
exists to disagree with.~~

**Half wrong as of 2026-09-09.** `grep -rl "ColorPicker" Sources/ | wc -l`
returns **1**, not 0: the view landed in `e6165e8a` (2026-09-08 04:36) at
`Views/ColorPicker.swift:39`. The *protocol* half of the claim still holds —
`grep -rl "ColorPickers" Sources/ | wc -l` returns **0**, so there is no
`BackendFeatures.ColorPickers` and no conformance anywhere. That is not an
oversight: the view is composed from `HStack`, `Slider`, `Button` and a filled
rectangle and needs nothing from any backend (`ColorPicker.swift:1-22` states
the trade). So #88 is not "untouched"; it is **the view done by composition,
the native-panel protocol deliberately deferred**, and re-scoping it should
start from that file's rationale rather than from this paragraph.

**2026-09-09 起有一半是錯的。** `grep -rl "ColorPicker" Sources/ | wc -l` 回傳 **1** 而非 0：
該 view 已於 `e6165e8a`（2026-09-08 04:36）落地，位置在 `Views/ColorPicker.swift:39`。主張中
**protocol** 的那一半仍然成立——`grep -rl "ColorPickers" Sources/ | wc -l` 回傳 **0**，因此並不存在
`BackendFeatures.ColorPickers`，任何地方也沒有 conformance。那並非疏漏：該 view 由 `HStack`、
`Slider`、`Button` 與一個填色矩形組合而成，不需要任何 backend 支援（取捨理由見
`ColorPicker.swift:1-22`）。所以 #88 並非「未被觸碰」，而是**以組合完成了 view、刻意延後了原生面板
的 protocol**；要重新界定它的範圍，起點應是該檔案的理由，而不是本段。

---

### #28 — the claim "no protocol at all" is exactly right

Reference counts, all **0**: `withAnimation`, `func animation`,
`struct Animation`, `AnyTransition`, `func transition`, `Transition`.

Regenerate:
`for n in withAnimation "func animation" "struct Animation" AnyTransition "func transition" Transition; do printf '%-20s %s\n' "$n" "$(grep -rlE "$n" Sources/SwiftCrossUI --include=*.swift | wc -l)"; done`

Note the asymmetry worth keeping in view: three backends already own animation
machinery for `GeometricEffects` (AppKit/UIKit `CATransform3D`, Android's
animation matrix), so the backend half of this is less empty than the framework
half. That does not make it cheap — the missing piece is a clock and a driver in
the view graph, which is shared code with no precedent here.

「完全沒有 protocol」的主張完全正確，六個名稱的引用計數皆為 0。值得留意的不對稱：三個 backend 為
`GeometricEffects` 已備有動畫機制，因此 backend 那一半沒有框架那一半那麼空——但這並不使它便宜，
缺的是 view graph 中的時鐘與驅動器，屬共用程式碼且此處無前例可循。

---

### #30 — still the only area with nothing in the left-hand column

`FocusState` 0, `func focused` 0, `keyboardShortcut` 0, `accessibilityLabel` 0,
`\bFocus\b` 0. The single hit for the looser pattern `accessibility` is
`Sources/SwiftCrossUI/Views/Modifiers/HelpModifier.swift`, and it is prose in a
comment, not an API.

This is the one entry of the twelve where the seven-day rule found nothing to
correct: it was absent on 2026-09-01 and it is absent now.

十二筆中唯一一筆「七天規則查不出任何需要更正之處」的條目：2026-09-01 缺席，今日仍然缺席。
`accessibility` 這個較寬鬆樣式的唯一命中位於 `HelpModifier.swift` 的註解散文中，並非 API。

---

### #32 — the gestures are absent as recorded, but the entry's *premise* is broken

The five names are absent, exactly as claimed: `DragGesture` 0,
`LongPressGesture` 0, `MagnificationGesture` 0, `RotationGesture` 0,
`simultaneousGesture` 0, and even the bare `\bGesture\b` is 0.

**"beyond tap and hover" assumes tap and hover work on all five backends. Hover
does not.** `BackendFeatures.Gestures = TapGestures & HoverGestures`
(`Gestures/Gestures.swift`), and:

| backend | conformance | file |
|---|---|---|
| GtkBackend | `BackendFeatures.Gestures` | `GtkBackend.swift:35` |
| WinUIBackend | `BackendFeatures.Gestures` | `WinUIBackend.swift:115` |
| AppKitBackend | via `FullAppBackend` | `AppKitBackend.swift:22` |
| UIKitBackend | `TapGestures` **and** `HoverGestures` | `UIKitBackend+Control.swift:567`, `:591` |
| AndroidBackend | `TapGestures` **only** | `AndroidBackend+TapGestures.swift:4` |

`onHover` goes through `@CastBackend<BackendFeatures.HoverGestures>`
(`Views/Modifiers/Handlers/OnHoverModifier.swift:33` and `:55`), and
`@CastBackend` expands to a `fatalError` when the backend does not conform
(`Sources/SwiftCrossUIMacrosPlugin/CastBackendMacro.swift:115`). So **`.onHover`
kills the process on Android.** The `onHover` hits in
`AndroidBackend+DragAndDrop.swift` are drop-target hover, which is a different
protocol and shares no code — the same confusion the 2026-09-01 inventory
already warned about for `DragGesture`.

That is a live violation of this repository's own rule, it is one file of work,
and it is not what #32 is about — so it is called out separately rather than
folded in.

Regenerate:
`for b in Gtk WinUI AppKit UIKit Android; do printf '%-8s hover=%s tap=%s both=%s full=%s\n' "$b" "$(grep -rl BackendFeatures.HoverGestures Sources/${b}Backend --include=*.swift | wc -l)" "$(grep -rl BackendFeatures.TapGestures Sources/${b}Backend --include=*.swift | wc -l)" "$(grep -rl BackendFeatures.Gestures Sources/${b}Backend --include=*.swift | wc -l)" "$(grep -rl FullAppBackend Sources/${b}Backend --include=*.swift | wc -l)"; done`

五個手勢名稱確如所記全部缺席。但「tap 與 hover 之外」這個前提預設了 tap 與 hover 在五個 backend
上都能運作，而 **hover 不能**：`AndroidBackend` 只 conform `TapGestures`，而 `.onHover` 走
`@CastBackend<BackendFeatures.HoverGestures>`，該 macro 在未 conform 時展開為 `fatalError`。
因此 `.onHover` 會在 Android 上終結整個行程。這是本倉庫自身規則的現行違反，工作量約一個檔案，
且與 #32 本身無關，故單獨列出而不併入。

---

### #34 — eight of ten claims stand, two do not

Re-checked 2026-09-08, twelve days after the audit that said "all ten still
stand".

| # | claim | 2026-08-27 | 2026-09-08 |
|---|---|---|---|
| 1 | `Picker` has only `init(of:selection:)`, selection Optional, no label, no `.tag()` | true | **still true** — `Views/Picker.swift:16` is the only `public init`; `grep "func tag" Sources/SwiftCrossUI` finds only `Widgets.swift`'s backend tag and `Cancellable`/`Publisher`, none of which is a view modifier |
| 2 | `Button` is label-String only; **no `ButtonRole` anywhere** | true | **half false.** `ButtonRole` exists at `Values/ButtonRole.swift:19`, `Button(_:role:action:)` at `Views/Button.swift:39`, and `EnvironmentValues.swift:399` carries it. The String-label half still stands (`Button.swift:17`) |
| 3 | `Text` is String only; no LocalizedStringKey, markdown, `+`, underline/strikethrough/kerning/textCase | true | **still true** — `Views/Text.swift:54` is the only `public init`, and all five modifier names return 0 |
| 4 | **`Image` has no `systemName:`** and no bundle asset init | true | **false.** `public init(systemName: String)` is at `Views/Image.swift:62`. It landed with the symbol API on 2026-09-08. The bundle-asset half still stands — `Image.swift` has exactly three `public init`s, at `:26`, `:33`, `:62` |
| 5 | all six `List` inits require `selection:` and `Data.Index == Int`; no `Section`, `.onDelete`, `.onMove`, `.swipeActions`, `.listRow*` | true | **still true for List, nuanced on Section.** All six inits in `Views/List.swift` still carry `selection:` and `Data.Index == Int`; `onDelete` 0, `onMove` 0, `swipeActions` 0, `listRow` 0. A `Section` **view** now exists (`Views/Section.swift:22`) but it is a standalone grouping built from stacks — `List`'s `rowContent` closures cannot take it, so the List half of the claim is untouched |
| 6 | `Table` has no selection, sortOrder or column width | true | **still true** — `Views/Table.swift:20` is the only `public init` and takes `(_ rows:, @TableRowBuilder columns:)` |
| 7 | `TextField` lacks `axis:`, `prompt:`, `value:format:`, `.textFieldStyle` | true | **still true** — four `public init`s at `Views/TextField.swift:18/25/42/68`, none with those labels; the only `format` hits are prose about `TextField(_:value:formatter:)` |
| 8 | `Slider` lacks label, step, onEditingChanged | true | **still true** — four `public init`s at `Views/Slider.swift:14/19/28/48`; `grep -n "step\|label\|onEditingChanged" Views/Slider.swift` returns nothing |
| 9 | `GeometryProxy` has only `size` | true | **still true** — `Values/GeometryProxy.swift:2` has exactly one field, `size`, and `CoordinateSpace` reference count is **0** |
| 10 | `padding`/`cornerRadius`/spacing/`Spacer(minLength:)` are Int while `frame` is Double | true | **still true** — `EdgeInsets` is at `Views/Modifiers/Layout/PaddingModifier.swift:34` and all four fields are `Int` |

Two of the ten changed inside the twelve days, and both changed because of work
done for a *different* entry — the symbol API closed claim 4, and a `ButtonRole`
added for its own reasons closed half of claim 2. That is the shape this rule
exists for: nobody reopens the audit that said a thing was missing.

十二天內有兩項改變，且兩者都是因為**其他條目**的工作而改變的——符號 API 了結了第 4 項，而為其他
理由加入的 `ButtonRole` 了結了第 2 項的一半。這正是七天規則存在的理由：沒有人會回頭去改那份說它
不存在的稽核。

---

### #36 — two done as recorded, and a fifth thing quietly left the list

Present: `View.confirmationDialog` at
`Views/Modifiers/ConfirmationDialogModifier.swift:50`, `View.safeAreaInset` at
`Views/Modifiers/Layout/SafeAreaInsetModifier.swift:39`.

Absent: `func popover` 0, ~~`fullScreenCover` 0~~, `toolbar` 0, `refreshable` 0.
The six `popover` reference hits are all prose — `Menus.swift`,
`MenuImplementationStyle.swift`, `DismissAction.swift`, `Menu.swift`,
`BackendDatePickerStyle.swift`, `BuiltinDatePickerStyles.swift` — describing
GTK's popover *menu*, not a `.popover` presentation modifier.

**Correction, 2026-09-08: `fullScreenCover` is no longer 0.**
`Sources/SwiftCrossUI/Views/Modifiers/FullScreenCoverModifier.swift:28` declares
`public func fullScreenCover<CoverContent: View>(isPresented:onDismiss:content:)`.
The "0" above was a real measurement that a merge outran, exactly as `.popover`
and `.navigationTitle` did in the row for this entry in the summary table. **So
#36 is 3 of 7, not 2 of 7** — left: `.toolbar` and `.refreshable`, both of which
still need a new requirement on all five backends. Note what it is built from
rather than assuming parity: it is a `sheet` with four options pinned, which is a
silent divergence recorded in **Divergences from SwiftUI** below.

Regenerate:
`for n in "func popover" "func fullScreenCover" "func toolbar" "func refreshable" "func navigationTitle"; do printf '%-24s %s\n' "$n" "$(grep -rl "$n" Sources/SwiftCrossUI --include=*.swift | wc -l)"; done`

**更正，2026-09-08：`fullScreenCover` 已不再是 0。**
`Sources/SwiftCrossUI/Views/Modifiers/FullScreenCoverModifier.swift:28` 宣告了
`public func fullScreenCover<CoverContent: View>(isPresented:onDismiss:content:)`。
上面那個「0」是一次真實的量測，只是被一次合併超前了——與本條目在總表列中的 `.popover` 及
`.navigationTitle` 完全相同。**因此 #36 是 7 分之 3，而非 7 分之 2**，剩下 `.toolbar` 與
`.refreshable`，兩者都仍需在五個 backend 上新增要求。請留意它是由什麼建成的，不要逕自假定它與
SwiftUI 一致：它是一個把四個選項釘死的 `sheet`，屬於下方**與 SwiftUI 的分歧**一節所記的無聲分歧。

**`navigationTitle` was on the 2026-09-01 list and is not on the 2026-09-04
one, and it was never implemented.** Its only two hits are comments in
`Views/NavigationStack.swift:83` and `:96`, and one of them says so outright:
*"When `View/navigationTitle(_:)` lands, this is where it reads from."* So #36
is 2 of 7, not 2 of 6.

Backend cost is uneven and worth recording before ordering the work: `.popover`
has a backend capability already (`BackendFeatures.PopoverMenus`, conformed by
GtkBackend at `GtkBackend.swift:36`), `.fullScreenCover` is close to `Sheets`
(~~four of five conform~~ **five of five conform — corrected 2026-09-09**),
while `.toolbar` and `.refreshable` need a new requirement on all five.

**Why "four" was wrong, which is more useful than the number.** Only four
backends name `BackendFeatures.Sheets` in a file of their own —
`AndroidBackend+Sheets.swift:4`, `GtkBackend.swift:32`,
`UIKitBackend.swift:20`, `WinUIBackend+Sheets.swift:10`. AppKit's conformance
arrives through the `FullAppBackend` protocol composition
(`Backend/FullAppBackend.swift:70`), which `AppKitBackend.swift:22` declares in
one word. `grep -rl "BackendFeatures.Sheets" Sources/AppKitBackend/` returns
**0**, and that zero is not the absence of a conformance — it is the absence of
the *string*. Any per-backend-file grep for a feature will undercount AppKit by
one for every feature in that composition.

**「四」錯在哪裡，比那個數字本身更值得記。** 只有四個 backend 在自己的檔案中寫出
`BackendFeatures.Sheets`——`AndroidBackend+Sheets.swift:4`、`GtkBackend.swift:32`、
`UIKitBackend.swift:20`、`WinUIBackend+Sheets.swift:10`。AppKit 的 conformance 是透過
`FullAppBackend` 這個 protocol 組合抵達的（`Backend/FullAppBackend.swift:70`），而
`AppKitBackend.swift:22` 只用一個字宣告了它。
`grep -rl "BackendFeatures.Sheets" Sources/AppKitBackend/` 回傳 **0**，而那個 0 不代表缺少
conformance——它代表缺少那個**字串**。任何逐 backend 檔案的 grep，對該組合中的每一項 feature，
都會把 AppKit 少算一個。

`navigationTitle` 曾在 2026-09-01 的清單上、不在 2026-09-04 的清單上，而它從未被實作——它僅有的
兩個命中都是 `NavigationStack.swift` 的註解，其中一句直言「待 `navigationTitle(_:)` 加入後，此處
便是它的讀取來源」。因此 #36 是 7 分之 2，而非 6 分之 2。

---

### #27 — the claim holds, and the missing piece is a call, not a binding

`GtkBackend` reads the ambient scheme **once**: `sampleAmbientColorScheme()` is
called at `Sources/GtkBackend/GtkBackend.swift:1029`, inside the main-loop
start, and the method itself is at `:2269`. The doc comment at `:2193` states
the design decision plainly — *"Sampled once at the start of the main loop
rather than on demand"* — so nothing later moves it.

**The binding it needs already exists and has no callers.**
`Gtk.Settings.registerNotification(named:handler:)` is at
`Sources/Gtk/Utility/Settings.swift:92`, its own doc comment names
`notify::gtk-theme-name` as the example, and:

```zsh
grep -rn "registerNotification" Sources/ --include=*.swift
```

returns **three lines, all inside `Settings.swift` itself** — the declaration at
`:92` and two mentions in comments at `:17` and `:21`. Zero callers.

The Windows half of the same entry has the same shape from the other direction.
`systemColorScheme` (`GtkBackend.swift:2239`) reads
`HKCU\…\Themes\Personalize\AppsUseLightTheme` with `RegGetValueW`, and it is
read exactly once, from inside `sampleAmbientColorScheme` at `:2312`.
`grep -rn WM_SETTINGCHANGE Sources/` returns **0**, so a Windows user toggling
app mode while the app runs changes nothing either.

The todo's own note that this **cannot be verified in WSL** — a `gsettings set`
produces zero notifications across all 55 `GtkSettings` properties, because WSLg
has no `xdg-desktop-portal`, no XSettings manager and no libadwaita — still
stands and is why this entry cannot be finished on the current hardware.

主張成立，而缺的是一次呼叫，不是一個 binding。`GtkBackend` 只在主迴圈啟動時取樣一次
（`GtkBackend.swift:1029`）。所需的 binding `registerNotification` 已存在於
`Sources/Gtk/Utility/Settings.swift:92`，其註解甚至以 `notify::gtk-theme-name` 為例，
但整個 `Sources/` 中**沒有任何呼叫者**。Windows 那一半形狀相同：登錄檔只讀一次，
`WM_SETTINGCHANGE` 在 `Sources/` 中命中 0 次。todo 自己記載的「在 WSL 中完全無法驗證」仍然成立，
這也是本條目在目前硬體上無法結案的原因。

---

### #31 — five present, not four, and only one of the two "remaining" is still blocked

| protocol | declared | where |
|---|---|---|
| `PickerStyle` | ✅ | `Views/Styles/PickerStyle/PickerStyle.swift` |
| `DatePickerStyle` | ✅ | `Views/Styles/DatePickerStyle/DatePickerStyle.swift` |
| `ListStyle` | ✅ | `Views/Styles/ListStyle/ListStyle.swift` |
| `ToggleStyle` | ✅ | `Views/Styles/ToggleStyle/ToggleStyle.swift` |
| `ShapeStyle` | ✅ | `Views/Styles/ShapeStyle/ShapeStyle.swift:25` |
| `ButtonStyle` | ❌ | reference count 0 |
| `LabelStyle` | ❌ → ✅ **closed 2026-09-08**, see item 3 below | was: reference count 1, and that one hit is the comment at `Views/Label.swift:28` saying it is absent. Now `Views/Styles/LabelStyle/LabelStyle.swift` |
| `TextFieldStyle` | ❌ | reference count 0 |
| `ProgressViewStyle` | ❌ | reference count 0 |

Regenerate:
`for n in PickerStyle DatePickerStyle ListStyle ToggleStyle ShapeStyle ButtonStyle LabelStyle TextFieldStyle ProgressViewStyle; do printf '%-20s %s\n' "$n" "$(grep -rlE "protocol $n\b" Sources/SwiftCrossUI --include=*.swift | wc -l)"; done`

**Three disagreements with the todo, all in the same direction — recorded as
blocked, actually unblocked:**

1. **`ShapeStyle` is done.** `todo.md:43` still lists it among
   "`ButtonStyle`, `LabelStyle`, `ShapeStyle` | absent — 0 declarations and 0
   references each". It is a protocol at `ShapeStyle.swift:25` with `Color`,
   `LinearGradient` and `RadialGradient` conforming via
   `_resolve(in:) -> ResolvedFillStyle`.
2. **The backend work `ShapeStyle` was waiting on is finished.** `todo.md:99`
   and `todo.md:106` say *"four backends done and one to go… AndroidBackend
   still takes the flattening default"*. AndroidBackend now has
   `AndroidBackend+PathGradients.swift` with its own `renderPath` taking
   `ResolvedFillStyle` at `:36`. All five carry it:
   `for b in Gtk WinUI AppKit UIKit Android; do printf '%s %s\n' "$b" "$(grep -rl ResolvedFillStyle Sources/${b}Backend --include=*.swift | wc -l)"; done`
   → 1 1 2 2 1.
3. **`LabelStyle`'s blocker is gone.** `todo.md:82` says *"`LabelStyle` has
   nothing to style. There is no `Label` view."* `Label` is at
   `Views/Label.swift:45`, and `Label(_:systemImage:)` at `:106` — the exact
   initialiser the file's own comment said would *"arrive with the symbol API,
   in the same change"*. It did, on 2026-09-08.

   **Acted on the same day.** `LabelStyle`, `LabelStyleConfiguration`,
   `View.labelStyle(_:)` and four built-in styles now live in
   `Views/Styles/LabelStyle/` and `Views/Modifiers/Style/LabelStyleModifier.swift`.
   `Label.swift`'s comment no longer says `LabelStyle` is absent, and the
   `todo.md` rows this section cites have been corrected — including the
   denominator, which now names `TextFieldStyle` and `ProgressViewStyle`
   explicitly. The two lines above are kept as the finding that produced the
   work rather than rewritten into a description of the outcome.

**`ButtonStyle` is still genuinely blocked**, and re-verified rather than
trusted: `grep -rn "isPressed" Sources/ --include=*.swift | wc -l` → **0**, and
`Button.label` is a `String` (`Views/Button.swift:17`). A `ButtonStyle` today
would hand every style an empty label and an `isPressed` that is always false.

**`TextFieldStyle` and `ProgressViewStyle` are still absent and are no longer
counted.** They were in the 2026-09-01 inventory's absent column; the "4/6"
denominator excludes them. Not implementing something is a decision; dropping it
out of the count is how it stops being one.

三處與 todo 相左，方向一致——記為受阻、實際已解除：`ShapeStyle` 已完成且五個 backend 的
`ResolvedFillStyle` 工作也已完成；`LabelStyle` 的阻礙（沒有 `Label` view）已於 2026-09-08 消失。
`ButtonStyle` 確實仍受阻（`isPressed` 全樹 0 次命中）。`TextFieldStyle` 與 `ProgressViewStyle`
仍然缺席，卻已不在計數之內。

---

### #33 — fifteen present of sixteen, and the denominator moved twice

Declaration counts. The middle column is the 2026-09-01 census, the third is the
measurement taken earlier on 2026-09-08, and the fourth is where the name stands
after the four composition views landed later the same day.

| name | on 2026-09-01 census | 2026-09-08, before | 2026-09-08, after |
|---|---|---|---|
| `Form` | absent | ✅ `Views/Form.swift:31` | ✅ unchanged |
| `Section` | absent | ✅ `Views/Section.swift:22` | ✅ unchanged |
| `Label` | absent | ✅ `Views/Label.swift:45` | ✅ unchanged |
| `Stepper` | absent | ✅ `Views/Stepper.swift:21` | ✅ unchanged |
| `LazyVStack` | absent | ✅ `Views/LazyStacks.swift:38` (eager — see #85) | ✅ unchanged, still eager |
| `LazyHStack` | absent | ✅ `Views/LazyStacks.swift:70` (eager — see #85) | ✅ unchanged, still eager |
| `Gauge` | absent | ✅ `Views/Gauge.swift:19` | ✅ unchanged |
| `LazyVGrid` | absent | ❌ 0 | ✅ ~~`Views/LazyStacks.swift:154`~~ ~~`Views/LazyVGrid.swift:68`~~ → `Views/LazyVGrid.swift:97` (file corrected 2026-09-08 after `dea9ccff`, line corrected 2026-09-09; eager, exactly like its siblings — see #85) |
| `Grid` | absent | ❌ 0 — **left the denominator, never implemented** | ✅ `Views/Grid.swift:38`, with `GridRow` at `:124` |
| `ScrollViewReader` | absent | ❌ 0 | ~~❌ 0 — still the one that is not composition~~ ✅ `Views/ScrollViewReader.swift`, with `ScrollViewProxy` in the same file. Landed 2026-09-09 with the new `BackendFeatures` requirement this row predicted, on all five backends, and **driven**: `actions/win/P34-scroll-to-row-50.csv` on Win-gtk4 (log `scrollTo row 50 requested, anchor top`, capture shows the top row going `Row 0` → `Row 50`), and P56 on AppKit, iOS and Android. Re-checked 2026-09-09 with a control (`VStack` found, `ZZZNotARealType` absent) |
| `ControlGroup` | absent | ❌ 0 — **left the denominator, never implemented** | ✅ `Views/ControlGroup.swift:40` |
| `GroupBox` | absent | ❌ 0 — **left the denominator, never implemented** | ✅ `Views/GroupBox.swift:34` |
| `DisclosureGroup` | not censused | ✅ `Views/DisclosureGroup.swift:20` | ✅ unchanged |
| `LabeledContent` | not censused | ✅ `Views/LabeledContent.swift:19` | ✅ unchanged |
| `Link` | not censused | ✅ `Views/Link.swift:39` | ✅ unchanged |
| `ColorPicker` | not censused | ❌ 0 — this is #88 | ~~❌ 0 — still #88~~ → ✅ `Views/ColorPicker.swift:39` (`e6165e8a`, 2026-09-08 04:36 — **earlier the same day than the "still 0" beside it**, so that cell was wrong when written, not stale) |

~~**Ten present and six absent became fourteen present and two absent on
2026-09-08.**~~ **Fifteen present and one absent, re-derived 2026-09-09.**
Regenerate — and note the pattern has changed shape, not just content:

```
for n in Form Section Label Stepper LazyVStack LazyHStack Gauge \
         DisclosureGroup LabeledContent Link Grid ControlGroup GroupBox \
         LazyVGrid ScrollViewReader ColorPicker VStack ZZZNotARealType; do
    printf '%-18s %s\n' "$n" \
      "$(grep -rlE "public [a-z ]*(struct|class|enum|protocol) $n\b" \
           Sources/SwiftCrossUI/ | wc -l)"
done
```

The controls are inside the loop so nobody can run it without them: `VStack`
must return 1 and `ZZZNotARealType` must return 0. The earlier recipe was
`public struct $n\b`, which is **shape-bound** — it sees only a `struct`, so a
view shipping as a `final class`, an `enum` or a `protocol` reads as absent. A
control on the *string* (`VStack`) cannot catch that, because `VStack` is a
struct too; the control has to exercise the same **shape** as whatever might be
missed.

~~**十四present、二absent**~~ **十五 present、一 absent，2026-09-09 重新推導。** 重新產生的指令
如上，並請注意**改變的是模式的形狀，不只是內容**：兩個控制項刻意寫在迴圈裡，讓人無法在不帶控制項
的情況下執行——`VStack` 必須回傳 1，`ZZZNotARealType` 必須回傳 0。先前的配方是
`public struct $n\b`，它**受限於形狀**——只看得見 `struct`，因此以 `final class`、`enum` 或
`protocol` 形式出貨的 view 會被讀成缺席。針對**字串**的控制項（`VStack`）抓不到這件事，因為
`VStack` 本身也是 struct；控制項必須演練與可能被漏掉之物**相同的形狀**。

**The denominator is still sixteen.** `GridRow` (`Views/Grid.swift:124`),
~~`GridItem` (`Views/GridItem.swift:45`) and the internal `GridCellsProviding`
(`Views/GridCells.swift:36`)~~ shipped with the four but are **not** added to the
list. Widening the denominator by the names one has just written is a flattering
version of the same error this section exists to record — the difference being
that dropping names hides work not done, and adding them inflates work done.

**Corrected 2026-09-08.** `GridItem` is now at `Views/LazyVGrid.swift:16`;
`Views/GridItem.swift` was deleted in `dea9ccff`. `GridCellsProviding` is not
merely at a different path — it is **gone entirely**
(`grep -rn GridCellsProviding Sources/` → 0), so a name this paragraph listed as
having "shipped" no longer exists. The argument about the denominator is
unaffected and still stands; only two of the three names it cites do.

**已於 2026-09-08 更正。** `GridItem` 現位於 `Views/LazyVGrid.swift:16`，`Views/GridItem.swift`
已在 `dea9ccff` 中刪除。`GridCellsProviding` 不只是換了路徑——它**完全不存在了**
（`grep -rn GridCellsProviding Sources/` → 0），因此本段列為「已隨那四項一併交付」的名稱之一
其實已不復存在。關於分母的論點不受影響、依然成立；只是它所引的三個名稱中僅有兩個仍然為真。

**`ScrollViewReader` is the one that is not composition.**
`BackendFeatures.ScrollContainers`
(`Backend/BackendFeatures/Containers/ScrollContainers.swift:6`) declares exactly
two methods — `createScrollContainer(for:)` at `:25` and
`updateScrollContainer(...)` at `:44`, whose parameters are bounce and
scroll-bar flags. **There is no way to ask a scroll container to move.** So
`ScrollViewReader` needs a new backend requirement and five implementations, not
a new view. `Grid`, `GroupBox`, `ControlGroup` and `LazyVGrid` were all
composition and needed nothing from any backend — **confirmed by building them
on 2026-09-08**, not merely predicted. That prediction is the one thing in this
section that has now been tested rather than measured, and it held.

~~One qualification, because "pure composition" turned out to be true of the views
and not quite of the job: `LazyVGrid` needed `GridCellsProviding`
(`Views/GridCells.swift:36`) to recover a `@ViewBuilder` block's children as
values before it could flow them into columns. That is new framework machinery
rather than a rearrangement of existing views. It still touches no backend, so
the claim above survives — but "composition only" and "no new types at all" are
not the same statement, and this batch needed the second one relaxed.~~

**Withdrawn 2026-09-08.** `GridCellsProviding` does not exist
(`grep -rn GridCellsProviding Sources/` → 0) and neither does the file. The
qualification was drawn from this side's `LazyVGrid`, which `dea9ccff` removed in
favour of the other one; the surviving implementation flows a `@ViewBuilder` block
into columns with no flattener. **"Composition only" therefore held without the
relaxation, and the paragraph above was wrong even about the day it described** —
it generalised one implementation's need into a property of the problem.

**於 2026-09-08 撤回。** `GridCellsProviding` 不存在（`grep -rn GridCellsProviding Sources/` → 0），
該檔案亦然。這段補充說明取自本側的 `LazyVGrid`，而 `dea9ccff` 已將其移除、改用另一份；存活下來的
實作沒有任何攤平器就把 `@ViewBuilder` 區塊流排成欄。**因此「只用組合」無須放寬即已成立，而上一段
即使就它所描述的那一天而言也是錯的**——它把單一實作的需要，推論成了問題本身的性質。

十六個名稱中原為十個存在、六個缺席；**2026-09-08 之後為十四個存在、兩個缺席**。三個名稱（`Grid`、
`ControlGroup`、`GroupBox`）曾在未被實作的情況下離開分母，如今連同 `LazyVGrid` 一併補上。
`ScrollViewReader` 是唯一不屬於「組合」的一項：`ScrollContainers` 只有建立與更新兩個方法，
**沒有任何「請捲動到某處」的途徑**，因此它需要一項新的 backend requirement 與五份實作。

~~一項補充說明，因為「純組合」對那幾個 view 成立、對整件工作卻不盡然：`LazyVGrid` 需要
`GridCellsProviding`（`Views/GridCells.swift:36`）先把 `@ViewBuilder` 區塊的子項還原為值，才能將
它們流排成欄。那是新的框架機制，而非既有 view 的重新排列。它依然不觸及任何 backend，因此上述主張
仍然成立——但「只用組合」與「完全不新增型別」並非同一句話，而本批工作需要放寬後者。~~
（已於 2026-09-08 撤回，理由見上方英文段。）

---

### #35 — two of four wrappers, and "only a Settings scene" understates it by three

| name | declared |
|---|---|
| `StateObject` | ✅ `State/StateObject.swift:49`, `@propertyWrapper` at `:48` |
| `ObservedObject` | ✅ `State/ObservedObject.swift:40`, `@propertyWrapper` at `:39` |
| `EnvironmentObject` | ~~❌ 0~~ **✅ 1, re-run 2026-09-09** with this table's own command below |
| `SceneStorage` | ❌ 0 |
| `Settings` (scene) | ❌ 0 — `struct Settings` 0; the single `\bSettings\b` hit is a symbol name in `Symbols/SystemSymbol+Table.swift` |
| `DocumentGroup` | ❌ 0 |

Regenerate:
`for n in StateObject ObservedObject EnvironmentObject SceneStorage Settings DocumentGroup; do printf '%-18s %s\n' "$n" "$(grep -rlE "(struct|enum) $n\b" Sources/SwiftCrossUI --include=*.swift | wc -l)"; done`

The 2026-09-01 inventory listed four absent wrappers. Two landed, so the wrapper
row is **2/4**, not 3/4; the "3/4" appears to have folded the scene row in. And
`ls Sources/SwiftCrossUI/Scenes/*.swift` shows `WindowGroup`, `Window`,
`AlertScene`, `CommandMenu`, `Commands` and the graph — no `Settings`, no
`DocumentGroup`.

~~So four things remain, not one. `EnvironmentObject` is the cheap one: it is a
sibling of `ObservedObject`, which already exists, and needs nothing from a
backend.~~

**THREE remain, re-run 2026-09-09 with the command above:** `SceneStorage`,
the `Settings` scene, and `DocumentGroup`. `EnvironmentObject` returns 1 and is
done — and it was correctly called "the cheap one", which is presumably why it
went first and why this paragraph then outlived it. The count above went
1 → 4 → 3 in eight days; **do not quote it, run the loop.**

~~剩下的是四項而非一項：`EnvironmentObject`、`SceneStorage`、`Settings` scene、`DocumentGroup`。
其中 `EnvironmentObject` 最便宜——它是已存在的 `ObservedObject` 的兄弟，且不需要任何 backend 支援。~~

2026-09-01 的盤點列出四個缺席的 wrapper，其中兩個已落地，因此 wrapper 那一列是 **2/4** 而非 3/4；
「3/4」似乎把 scene 那一列併了進來。

**2026-09-09 以上方那道指令重跑，剩下的是三項**：`SceneStorage`、`Settings` scene 與
`DocumentGroup`。`EnvironmentObject` 現在回傳 1，已經完成——而它當初被正確地稱為「最便宜的那一個」，
想必正因如此才最先被做掉，也正因如此這段文字才比它所描述的事實活得更久。這個數字在八天內走過
1 → 4 → 3；**不要引用它，去跑那道迴圈。**

---

### #79 — the function is gone; the defect is not

**This entry is different from the other eleven: it is a specific GtkBackend
defect, not a missing API.** Its title is now inaccurate in a way that matters.

```zsh
grep -rn "correctContentSizeIfNeeded" Sources/ --include=*.swift
```

returns **two lines, both inside a doc comment** —
`Sources/GtkBackend/GtkBackend.swift:1339` and `:1369`, the English and Chinese
halves of the paragraph explaining why the name was retired. There is no such
function. It was renamed to `reportContentSizeShortfall(of:)`
(`GtkBackend.swift:1375`) and the ineffective assignment deleted, in commit
`aca6e259 GtkBackend: delete the content-size correction that never corrected
anything`. The deleted code is quoted in a comment at `:1444` so the record
survives the deletion.

**The description's *diagnosis* still holds word for word.** The comment at
`:1325` says it: `gtk_window_set_default_size` is a launch hint once the window
is realised, and this method runs after the window is mapped **by construction**,
because the shortfall is unmeasurable before then — *"the one moment it can
measure is the one moment it can no longer act."*

**The defect is live.** GTK still delivers 39px less content height than
requested. Measured values recorded in the tree: `requested 900x600 allocated
900x561 shortfall 0x39` (`GtkBackend.swift:1316`), and 860x700 requested against
860x661 delivered, against WinUI's exact 860x700, in
`matrix_coverage/coverage-matrix.csv2:112`. `todo.md:395` already carries the
right warning: *"`correctContentSizeIfNeeded` is not evidence that it is
closed… Verify by the numbers, not by the presence of the function."* That
warning now needs its counterpart: the **absence** of the function is not
evidence either.

Three real fixes were considered and all three rejected — see `todo.md` and
`bugs/Gtk4-bugs.md` section 5. Forcing the size through `CustomRootWidget`'s
measured minimum breaks what `.defaultSize` means; owning the titlebar to
measure it costs 8px of permanent chrome on every window (GTK's own decoration
measures 39, a `GtkHeaderBar` 47, both measured 2026-09-04). So this entry is a
**decision**, not an implementation task, and belongs under "Needs a decision"
rather than in a parity list.

本條目與其餘十一筆性質不同：它是 GtkBackend 的具體缺陷，而非缺失的 API。該函式**已不存在**——
`grep` 只命中兩行，且兩行都在說明「為何這個名字被淘汰」的註解裡。它已更名為
`reportContentSizeShortfall(of:)`，無效的指派已於 `aca6e259` 刪除。**描述中的診斷逐字仍然成立**，
**而缺陷仍然存在**：GTK 交付的內容高度仍比要求少 39px。`todo.md:395` 已警告「函式存在不構成結案的
證據」；現在需要它的對偶句：**函式不存在同樣不構成證據**。三種真正的修正都已被否決，因此本條目
是一項**決策**，而非一項實作工作。

---

## Divergences from SwiftUI — APIs we HAVE, that do not match / 與 SwiftUI 的分歧——已實作、但與 SwiftUI 不一致者

Everything above this line is about what is **missing**. This section is about
what is **present and wrong**, which the rest of the document cannot see: a name
that exists satisfies every grep in **Method**, so an implemented-but-divergent
API scores identically to an implemented-and-correct one. Measured 2026-09-08.

本節之前的所有內容講的都是**缺什麼**。本節講的是**有、但不對**的東西，而那是本文件其餘部分看不見的：
一個存在的名稱能滿足**方法**一節的每一道 grep，因此「已實作但有分歧」與「已實作且正確」得到的分數
完全相同。2026-09-08 實測。

### Silent — compiles, and behaves differently / 無聲——編得過，行為卻不同

These are first because they are the expensive ones. SwiftUI source compiles
against them, the app runs, and the difference shows up as behaviour nobody
wrote. There is no warning, no `#warning`, no availability annotation and no
documentation the caller has to pass through.

這一類排在最前面，因為它們代價最高。SwiftUI 的原始碼對它們編得過、app 跑得起來，差異則以「沒有人
寫過的行為」現身。沒有警告、沒有 `#warning`、沒有 availability 標註，也沒有呼叫端非經過不可的文件。

| # | API | Ours | SwiftUI | What the caller sees |
|---|---|---|---|---|
| 1 | `sheet(onDismiss:)` on **programmatic** dismissal (`Modifiers/SheetModifier.swift:19`) | never fires, on all five backends | fires however the presentation ended | the closure they wrote simply never runs |
| 2 | `.popover`'s `onDismiss` (`Modifiers/PopoverModifier.swift:22`) | UIKit **suppresses** on programmatic dismissal (`UIKitBackend+Popover.swift:93`, set `:96`, checked `:103`); Gtk, WinUI, AppKit and Android **fire** on both paths | SwiftUI's `popover` has **no `onDismiss` parameter at all** — see the confidence note below | one callback means two different things depending on which backend the app was built for |
| 3 | `.navigationTitle` (`Modifiers/NavigationTitleModifier.swift:57`) | writes the OS **window** title, via `setTitle(ofWindow:to:)` on all five | iOS: the navigation bar. macOS: the window title | **nothing at all on UIKit and Android**, where the platform window has no visible title bar. The value is delivered and never drawn |
| 4 | ~~`@Environment(Model.self)`~~ **fixed 2026-09-08, run on Win-gtk4** | *was* a `DynamicProperty` that **read** the object and never observed it — no `didChange`, so `ViewGraphNode` had nothing to subscribe to (`Environment/Environment.swift:40` as surveyed). Now conditionally an `ObservableProperty` `where Value: ObservableObject`, with the value in a class carried across updates | observes; a change re-renders the view | matches SwiftUI. Before: rendered once correctly, then stale forever. `@EnvironmentObject` (`Environment/EnvironmentObject.swift`) is still there and still equivalent |
| 5 | `GridItem` size arithmetic (`Views/LazyVGrid.swift`) | ~~`Int` throughout, and the proposed width is truncated — `Int(proposedWidth.rounded(.down))` at `:197` — before integer division splits it~~ **FIXED, re-read 2026-09-09.** The sizes are `Double`: `.fixed(Double)` `:37`, `.flexible(minimum: Double = 10, maximum: Double = .infinity)` `:53`, `.adaptive(minimum: Double, maximum: Double = .infinity)` `:57`. **`spacing` is still `Int?` (`:61`)**, so the row is half-live rather than dead — and that half is the caller's `LazyVGrid(spacing:)`, not a `GridItem` size. The line numbers this row cited (`:16`/`:20`/`:25`/`:29`/`:197`) are all stale too; the file was restructured when `LazyVGrid` moved out of `LazyStacks.swift` | `CGFloat` throughout | ~~columns do not sum to the container on a fractional display scale~~ — no longer for the sizes. Still open for `spacing` |
| 6 | `fullScreenCover` (`Modifiers/FullScreenCoverModifier.swift:28`) | a **sheet** with four options pinned: `.presentationDetents([.fraction(1)])`, `.presentationCornerRadius(0)`, `.presentationDragIndicatorVisibility(.hidden)`, `.interactiveDismissDisabled()` (`:46`–`:50`) | a presentation that covers its parent | a sheet-shaped modal on macOS, GTK and WinUI — the platform's own sheet animation and chrome, sized to the window rather than replacing it |

Row 6 carries a correction to how it was described during this survey. It was
reported as *"a sheet with a `.large` detent"*; the detent is `.fraction(1)`, and
the pinning is four options, not one. `.large` and `.fraction(1)` are different
cases of `Values/PresentationDetent.swift` (`:7` and `:13`) and would have sent
anyone re-deriving the behaviour to the wrong one.

第 6 列附帶一項對本次盤點自身描述的更正。它先前被回報為*「一個帶 `.large` detent 的 sheet」*；實際的
detent 是 `.fraction(1)`，而被釘死的是四個選項，不是一個。`.large` 與 `.fraction(1)` 是
`Values/PresentationDetent.swift`（`:7` 與 `:13`）中的兩個不同 case，任何據此重新推導行為的人都會
走到錯的那一個。

Row 4 carried a second defect the survey did not see, found while fixing it and
recorded here because it lived in the same eight lines. The object lookup was
`environment[observable: type] as! Value`, so a type **nobody supplied** was a
force-cast of `nil`: the process died inside `update(with:previousValue:)`,
before `wrappedValue` and its message were ever reached. Measured on Win-gtk4,
2026-09-08, the whole of what a developer got was

    Could not cast value of type 'Swift.Optional<SwiftCrossUI.ObservableObject>'
    (00007FFB7DD911C0) to 'EnvRepro.NeverSuppliedModel' (00007FF67207A110).

— the target type and two addresses, with no mention of `@Environment`, of the
view, or of the `.environmentObject(_:)` that was missing. `as?` now records the
absence and `wrappedValue` reports it by name. Worth stating precisely because
"traps with no message" is *nearly* right and would send the next reader looking
for a bare `fatalError()`: there is a message, it just answers a different
question than the one being asked.

第 4 列還帶著一個本次盤點沒看見的第二個缺陷，是在修它的時候發現的，記於此處是因為它就住在同樣那
八行裡。物件查找原本是 `environment[observable: type] as! Value`，因此一個**沒有人提供**的型別
就是一次對 `nil` 的強制轉型：行程死在 `update(with:previousValue:)` 之中，`wrappedValue` 與它的
訊息根本不會被觸及。2026-09-08 於 Win-gtk4 實測，開發者拿到的全部就是上方那兩行——目標型別加兩個
位址，完全沒有提到 `@Environment`、沒有提到是哪個 view，也沒有提到缺少的
`.environmentObject(_:)`。現在改用 `as?` 記下「不存在」，由 `wrappedValue` 指名回報。這一點值得
精確描述，因為「無訊息中止」*幾乎*是對的，卻會讓下一位讀者去找一個沒有參數的 `fatalError()`：
訊息是有的，只是它回答的問題與被問的那個不同。

#### Row 1 in detail — two backends suppress with a named flag, three suppress structurally / 第 1 列細節——兩個 backend 以具名旗標壓制，三個以結構壓制

This is worth the extra table because grepping for the flag finds two of five and
looks like a two-backend bug. It is a five-backend divergence; three of them just
have nothing to grep for.

這一列值得多一張表，因為 grep 那個旗標只會找到五個中的兩個，看起來像是「兩個 backend 的 bug」。
它其實是五個 backend 的共同分歧，只是其中三個根本沒有可供 grep 的東西。

| backend | how it suppresses | where |
|---|---|---|
| WinUI | named flag `isProgrammaticDismissal` | `WinUIBackend+Sheets.swift:16`, set `:173`, checked `:139`–`:140` |
| UIKit | named flag `wasDismissedProgrammatically` | `UIKitBackend+Sheet.swift:232`, set `:248`, checked `:272` |
| AppKit | **no flag — structural.** `dismissSheet` calls `endSheet` directly; `onDismiss` lives only on `cancelOperation`, the user-cancel path | `AppKitBackend+Sheet.swift:88`–`:103`, `:113`–`:118` |
| Gtk | **no flag — structural.** `dismissSheet` calls `destroy` directly; `onDismiss` lives only on `onCloseRequest` and the escape-key handler | `GtkBackend.swift:4683`–`:4704`, handlers `:4607`–`:4629` |
| Android | **no flag — structural.** `onDismissListener` is called from `onCancel`, which Android does not invoke for a programmatic `dismiss()` | `Kotlin/CustomSheet.kt:55`–`:58` |

Regenerate:
`for b in Gtk WinUI AppKit UIKit; do printf '%-8s %s\n' "$b" "$(grep -rn 'isProgrammaticDismissal\|wasDismissedProgrammatically' Sources/${b}Backend --include=*.swift | wc -l)"; done`
→ `Gtk 0`, `WinUI 6`, `AppKit 0`, `UIKit 3`. **The two zeros are not two clean
backends.**

**And the asymmetry, which is itself silent.** The three backends that support
nested sheets — Gtk, WinUI and AppKit; UIKit and Android have no `nestedSheet` at
all (`grep -rn nestedSheet Sources/UIKitBackend Sources/AndroidBackend` → 0) — all
call the **child's** `onDismiss` when a parent is dismissed programmatically:
`AppKitBackend+Sheet.swift:98`, `GtkBackend.swift:4700`,
`WinUIBackend+Sheets.swift:170`. AppKit's comment says why in as many words.
**So a nested sheet gets its callback and the sheet actually dismissed does
not.** Anyone who reaches for a nested sheet to test this — which is the natural
way to test a sheet's dismissal callback, because it is the case with two
observable events — concludes that it works.

**還有那項不對稱，而它本身也是無聲的。** 支援巢狀 sheet 的三個 backend——Gtk、WinUI 與 AppKit；
UIKit 與 Android 根本沒有 `nestedSheet`（`grep -rn nestedSheet Sources/UIKitBackend
Sources/AndroidBackend` → 0）——在父層被程式化關閉時，全都會呼叫**子層**的 `onDismiss`：
`AppKitBackend+Sheet.swift:98`、`GtkBackend.swift:4700`、`WinUIBackend+Sheets.swift:170`。
AppKit 的註解把理由寫得一清二楚。**於是巢狀的那個 sheet 拿到了回呼，真正被關閉的那個沒有。**
任何拿巢狀 sheet 來測這件事的人——而那正是測試 sheet 關閉回呼最自然的做法，因為它是有兩個可觀察
事件的情況——都會得出「它可以運作」的結論。

#### The `.popover` correction — I called a divergence "aligning with SwiftUI" during the merge / `.popover` 的更正——合併期間我把一項分歧說成了「與 SwiftUI 一致」

**This must be stated as a correction, not as a corrected fact.** During the
merge I described the macOS side's design — *pass the anchor **widget** rather
than an edge* — as **aligning with SwiftUI**. That was wrong, and it was wrong in
the direction that does the damage: it reported a deliberate divergence as
conformance, which is precisely the failure this document exists to catch.

SwiftUI's popover takes `attachmentAnchor:` and `arrowEdge:`. **We have neither**
— `View.popover(isPresented:onDismiss:content:)` at
`Views/Modifiers/PopoverModifier.swift:22`–`:26` takes no positioning parameter,
and the anchor is hard-wired to the modifier's own widget at `:157`.
`grep -rn "arrowEdge\|attachmentAnchor" Sources/ --include=*.swift` → **0**.

Their argument still stands on its merits, and nothing here asks for it to be
reversed: a pinned edge is honoured even when it puts the popover off the edge of
the monitor, and a popover nobody can see has shown nothing. That is a good
reason to diverge. **It is not a reason to call it conformance.** The two claims
have different consequences — one closes the item, the other leaves a row in the
table above.

**這必須寫成一項更正，而不是寫成一項已更正的事實。** 合併期間，我把 macOS 那側的設計——*傳入錨點
**widget** 而非某個 edge*——描述為**與 SwiftUI 一致**。那是錯的，而且錯在會造成損害的那個方向：
它把一項刻意的分歧回報成了一致，而那正是本文件存在所要抓的失誤。

SwiftUI 的 popover 接受 `attachmentAnchor:` 與 `arrowEdge:`。**我們兩者皆無**——
`Views/Modifiers/PopoverModifier.swift:22`–`:26` 的
`View.popover(isPresented:onDismiss:content:)` 不接受任何定位參數，錨點在 `:157` 被寫死為該
modifier 自身的 widget。`grep -rn "arrowEdge\|attachmentAnchor" Sources/ --include=*.swift` → **0**。

他們的論據本身依然成立，此處也不要求推翻它：一個被釘死的 edge 即使會把 popover 推到螢幕外也照樣
生效，而一個沒人看得見的 popover 等於什麼都沒顯示。那是分歧的好理由。**但那不是把它稱作「一致」的
理由。** 這兩種說法的後果並不相同——一種讓該項目結案，另一種在上表留下一列。

### Loud — does not compile from SwiftUI source / 響亮——SwiftUI 原始碼編不過

Lower risk than everything above, because the compiler is the warning. They are
listed anyway, with `file:line`, because "it does not compile" is what parity
task #34 is measured in and because the fix for most of them is one overload.

風險低於上述所有項目，因為編譯器就是那個警告。仍然列出並附上 `file:line`，因為 parity 條目 #34
正是以「編不過」為計量單位，而且其中多數的修法就是加一個 overload。

| SwiftUI source that fails | why | where |
|---|---|---|
| `Button { … } label: { … }` | `label` is a `String`, not a view | `Views/Button.swift:4` (the property), `:17` (the only String-label init) |
| `.buttonStyle(…)` / `ButtonStyle` | **absent entirely** — `grep -rn ButtonStyle Sources/ --include=*.swift` → 0, and `isPressed` → 0 hits, so the protocol could not be given a truthful `configuration` today | — |
| `struct S: ToggleStyle { func makeBody(configuration:) }` | ours is `makeView(label:isOn:environment:)`, taking a `String` label | `Views/Styles/ToggleStyle/ToggleStyle.swift:19`, `:27` |
| `Picker("Label", selection: $x) { … }` | ours takes an **options array** and an **optional** binding, with no label and no `.tag()` | `Views/Picker.swift:16` |
| `Stepper(value: $x, in: 0.0...1.0, step: 0.1)` | `Int`-only: `Binding<Int>`, `ClosedRange<Int>`, `step: Int` | `Views/Stepper.swift:30`–`:34`, `:101` |
| `Slider(value: $x, in: 0...1, step: 0.1)` | **the `Double` part works** — see the correction below — but there is no `step:`, no label and no `onEditingChanged` | `Views/Slider.swift:28` (integer), `:48` (floating point) |
| `Text("a") + Text("b")` | `Text` declares no operators at all; its only `public init` takes a `String` | `Views/Text.swift:54` |
| `ProgressView(value: 0.3, total: 1.0)` | `value:` exists; **there is no `total:`** on any of the nine inits | `Views/ProgressView.swift:64`, `:105`, `:141` |
| `.padding(10.5)` | `Int?`, and `EdgeInsets` is four `Int` fields | `Views/Modifiers/Layout/PaddingModifier.swift:9`, `:20`, `:34` |
| `.presentationDragIndicator(.hidden)` | spelled `presentationDragIndicatorVisibility(_:)` here | `Views/Modifiers/PresentationModifiers.swift:51` |
| ~~`GridItem(.flexible(maximum: .infinity))`~~ **compiles, 2026-09-09** | ~~`maximum` is `Int?`, and `.infinity` is not an `Int`~~ — it is `Double` and `.infinity` is its DEFAULT: `case flexible(minimum: Double = 10, maximum: Double = .infinity)`. Integer literals still compile, so `GridItem(.fixed(96))` was never broken by the change | `Views/LazyVGrid.swift:53` |

**Correction inside this table.** `Slider` was described during this survey as
`Int`-only, alongside `Stepper`. It is not: `Views/Slider.swift:48` is
`init<T: BinaryFloatingPoint>(value:in:)`, so `Slider(value: $double, in: 0...1)`
compiles. `Stepper` genuinely is `Int`-only. Grouping them cost `Slider` a
divergence it does not have and would have hidden the one it does — the missing
`step:`, which is what actually fails.

**本表內部的一項更正。** 本次盤點曾把 `Slider` 與 `Stepper` 並列描述為「僅支援 `Int`」。並非如此：
`Views/Slider.swift:48` 是 `init<T: BinaryFloatingPoint>(value:in:)`，因此
`Slider(value: $double, in: 0...1)` 編得過。`Stepper` 才是真的僅支援 `Int`。把兩者歸為一類，等於
替 `Slider` 記上一項它沒有的分歧，同時遮住了它真正有的那一項——缺少 `step:`，而那才是真正編不過的
地方。

#### `.frame` is the pattern the rest should copy / `.frame` 就是其餘各項該抄的樣板

`.frame` has the same `Int`-versus-`Double` history as `padding` and `GridItem`
and does **not** have their problem, because it was solved rather than chosen.
`Views/Modifiers/Layout/FrameModifier.swift` carries **both** an `Int` overload
(`:13`) and a `Double` overload (`:25`), and — the part that matters — the `Int`
overload still types `maxWidth` and `maxHeight` as `Double?` (`:64`, `:67`), on
the reasoning that a maximum is the one place `.infinity` is idiomatic. So
`.frame(maxWidth: .infinity)` compiles from unmodified SwiftUI source while
`.padding(10.5)` and `GridItem(.flexible(maximum: .infinity))` do not.

**Two overloads and one deliberately-widened parameter is the whole fix**, it is
already written down in this repository, and it costs nothing at the call site.
`padding`, `Spacer(minLength:)`, `cornerRadius`, stack `spacing:` and `GridItem`
should copy it. That also retires #34's claim 10 — *"`padding`/`cornerRadius`/
spacing/`Spacer(minLength:)` are `Int` while `frame` is `Double`"* — as a design
question rather than a list of separate tasks.

`.frame` 與 `padding`、`GridItem` 有著相同的 `Int`／`Double` 身世，卻**沒有**它們的問題，因為它是
被解決掉的，而不是被選擇的。`Views/Modifiers/Layout/FrameModifier.swift` **同時**帶有 `Int`
overload（`:13`）與 `Double` overload（`:25`），而且——這才是關鍵——`Int` 那個 overload 仍把
`maxWidth` 與 `maxHeight` 定為 `Double?`（`:64`、`:67`），理由是「最大值」正是 `.infinity` 最合乎
慣用法的地方。因此 `.frame(maxWidth: .infinity)` 能直接由未經修改的 SwiftUI 原始碼編過，而
`.padding(10.5)` 與 `GridItem(.flexible(maximum: .infinity))` 不能。

**兩個 overload 加上一個刻意放寬的參數，就是全部的修法**，它已經寫在本倉庫裡，而且在呼叫端不花任何
代價。`padding`、`Spacer(minLength:)`、`cornerRadius`、各 stack 的 `spacing:` 與 `GridItem` 都該抄
它。這同時也把 #34 的第 10 項——*「`padding`／`cornerRadius`／spacing／`Spacer(minLength:)` 是
`Int`，而 `frame` 是 `Double`」*——從一串各自獨立的工作，收斂成一個設計問題。

### Confidence — what this section does NOT claim / 可信度——本節**未**主張什麼

Every row above cites a line in *this* tree, and every such line was opened and
read on 2026-09-08. The **SwiftUI** column is the weaker half: this environment
has no Xcode and therefore no `SwiftUI.swiftinterface` to check a signature
against. Where SwiftUI's behaviour is widely relied upon — `sheet(onDismiss:)`
firing on any dismissal, `GridItem` being `CGFloat`, `Text` having `+` — it is
stated. Where it is not, it is marked here instead of guessed.

**Unverified, and deliberately left so:**

- **`PickerStyle`, `ListStyle` and `DatePickerStyle`.** All three exist here
  (`Views/Styles/…`, see the #31 table) with this project's `makeView(…)` shape
  rather than SwiftUI's `makeBody(configuration:)`. Whether that is a divergence
  at all is **not established**: it is not known from this environment whether
  recent SwiftUI SDKs expose *any* conformable requirement on those three
  protocols — they may be closed, in which case there is no signature to diverge
  from and the shape here is free. Settling it needs a real
  `SwiftUI.swiftinterface` from an Xcode install, which is not available here.
  They are therefore **absent from both tables above**, rather than listed as
  loud divergences.
- **`.popover` having no `onDismiss:` in SwiftUI** (silent row 2). Stated from
  the documented signature `popover(isPresented:attachmentAnchor:arrowEdge:content:)`,
  not from an interface file. The half that *is* verified here is the one that
  matters: our five backends disagree with **each other**, which is a divergence
  no reading of SwiftUI can excuse.

For contrast, `LabelStyle` **is** verified to match SwiftUI's shape — it is
`makeBody(configuration:)` at `Views/Styles/LabelStyle/LabelStyle.swift:52` with
`Configuration = LabelStyleConfiguration` at `:47` — which is why it appears in
neither table. It is also evidence that the `makeView(…)` shape of the other
styles was a choice, not a constraint.

上方每一列都引用了**本樹**中的某一行，而每一行都已於 2026-09-08 打開讀過。**SwiftUI** 那一欄是較弱
的一半：本環境沒有 Xcode，因此沒有 `SwiftUI.swiftinterface` 可供核對簽名。凡 SwiftUI 的行為被廣泛
依賴者——`sheet(onDismiss:)` 在任何關閉方式下都會觸發、`GridItem` 為 `CGFloat`、`Text` 有 `+`——
此處據實寫出；其餘則在此標記，而非猜測。

**未經查證，且刻意保持未查證：**

- **`PickerStyle`、`ListStyle` 與 `DatePickerStyle`。** 三者在此處皆存在（`Views/Styles/…`，見 #31
  的表），採用本專案的 `makeView(…)` 形狀而非 SwiftUI 的 `makeBody(configuration:)`。這究竟算不算
  一項分歧，**尚未確立**：本環境無從得知近期的 SwiftUI SDK 是否在這三個 protocol 上暴露了**任何**
  可供 conform 的 requirement——它們可能是封閉的，那樣就不存在可供分歧的簽名，此處的形狀也就自由。
  要定案需要一份來自 Xcode 安裝的真實 `SwiftUI.swiftinterface`，而此處沒有。因此三者**未列入上方
  任何一張表**，而不是被當成響亮分歧列出。
- **SwiftUI 的 `.popover` 沒有 `onDismiss:`**（無聲第 2 列）。此說法出自已公開的簽名
  `popover(isPresented:attachmentAnchor:arrowEdge:content:)`，而非出自 interface 檔。此處**已經**
  查證的是更要緊的那一半：我們的五個 backend 彼此不一致——那是任何對 SwiftUI 的解讀都無法開脫的
  分歧。

作為對照，`LabelStyle` **已查證**與 SwiftUI 的形狀一致——它是
`Views/Styles/LabelStyle/LabelStyle.swift:52` 的 `makeBody(configuration:)`，`:47` 處
`Configuration = LabelStyleConfiguration`——這正是它兩張表都不出現的原因。它同時也證明了其餘各
style 採用 `makeView(…)` 形狀是一項選擇，而非一項限制。

---

## Overlaps — where two entries are the same work / 重疊之處

Counting these twice inflates the remaining work by three items.

重複計算會使剩餘工作量虛增三項。

| entries | shared work | note |
|---|---|---|
| **#33 ↔ #88** | `ColorPicker` | #33 lists it as one of its three remaining views; #88 *is* that view plus its backend protocol. **One job.** Do it under #88, where the backend half is scoped |
| **#33 ↔ #85** | `LazyVGrid` | ~~#33 lists it as remaining; #85 asks for it by name.~~ **Closed 2026-09-08**, done once as predicted rather than twice. #85's *other* half — making the existing stacks lazy — is unrelated to #33, is untouched, and is still a layout-system change |
| **#31 ↔ #65** | `ButtonStyle`, `LabelStyle` | #31 defers to #65 for why both are blocked. **#65's `LabelStyle` reason expired on 2026-09-08** when `Label` landed. #65's `ButtonStyle` reason is re-verified and stands. So the two halves of #65 should be split: one is closeable, one is not |
| **#31 ↔ #34** | arbitrary `Button` labels | `ButtonStyle` is blocked on `Button.label` being a `String`, which is #34's claim 2. Fixing #34 claim 2 properly unblocks #31's `ButtonStyle`. **Not the same job, but strictly ordered** |
| **#33 ↔ #35** | none, despite both saying "one thing remains" | worth stating: they are independent, and both understate |

---

## Recommended order / 建議順序

Cheapest-and-unblocking first. The reason is given for each position, because
"cheapest first" is exactly the judgement that gets made wrong from a list
without reading the code — this repository has already recorded that mistake for
claims 9 and 10 of #34.

由「最便宜且能解除阻塞」者優先。每一個位次都附上理由，因為「先做最便宜的」正是那種「不讀程式碼、
只看清單就會判斷錯」的判斷——本倉庫已在 #34 的第 9、10 項上記錄過這個錯誤。

| # | work | why here |
|---|---|---|
| **1** | **#79: retitle the entry and move it to "Needs a decision"** | Zero lines of Swift. The code change already happened in `aca6e259`; only the record is wrong. Doing this first stops the next person scoping an implementation task against a function that does not exist |
| **2** | **`HoverGestures` on AndroidBackend** | Not one of the twelve — found while checking #32's premise. `.onHover` currently `fatalError`s on a shipped backend, which the project rule forbids outright. One file, and it is the only *live crash* in this survey |
| **3** | **#31: `LabelStyle`** | Its only recorded blocker — "there is no `Label` view" — expired on 2026-09-08. Framework-only, no backend requirement, and `PickerStyle` is the worked example to copy. The cheapest genuine feature on the list, and it also lets #65 be half-closed |
| **4** | ~~**#33 + #85: `GroupBox`, `ControlGroup`, `Grid`, `LazyVGrid`**~~ **DONE 2026-09-08** | Four views, all pure composition, no backend requirement, closing the #33↔#85 overlap in one pass. Two corrections to the estimate, both worth keeping: `GridItem` turned out to belong to `LazyVGrid` alone — SwiftUI's `Grid` does not use it, so "which `Grid` wants anyway" was wrong — and flowing a `@ViewBuilder` block into columns needed a new value-level flattener (`GridCellsProviding`) that this row did not anticipate. Doing them together was still cheaper than separately |
| **5** | **#35: `EnvironmentObject`** | A sibling of `ObservedObject`, which already exists at `State/ObservedObject.swift:40` and can be copied. Framework-only. Closes the largest part of #35's understatement for the least work |
| **6** | ~~**#36: `.popover` and `.fullScreenCover`**~~ ~~**`.popover` and `.navigationTitle` DONE 2026-09-08; `.fullScreenCover` still open**~~ **All three DONE 2026-09-08** — corrected: `.fullScreenCover` is at `Modifiers/FullScreenCoverModifier.swift:28`. It was written between this row's measurement and the merge `dea9ccff`, so "still open" was stale by the time it was read. It landed as the cheap one this row predicted — a `sheet` with four options pinned, no new backend requirement — but pinning is not covering, and the divergence is recorded below | The estimate said these "already have a backend capability underneath — `PopoverMenus` and `Sheets` respectively — so neither adds a requirement to five backends". **The `PopoverMenus` half is false, and it was the load-bearing half.** `showPopoverMenu` takes a `Menu` (`Menus.swift:78`), which is built from a `ResolvedMenu` of labels, toggles, separators and submenus; it cannot hold a `Widget`, so it cannot show a `Slider`. It is also conformed by only **two** backends (`GtkBackend.swift:35`, `AppKitBackend+Menus.swift:4`) — the other three use `AttachedMenus`. `.popover` therefore needed a new `BackendFeatures.Popovers` and five conformances after all. The `Sheets` half looks right and inverts the order: `.fullScreenCover` is a sheet sized to its parent window rather than to its content, so it is the *cheap* one and should be done next. `.navigationTitle` needed no protocol at all — it is a `PreferenceValues` entry applied through `setTitle(ofWindow:to:)`, which is a `Core` requirement every backend already implements. But `NavigationStack.swift:83`'s "already says where it would read from" was unachievable as written: a preference travels upward and the bar is the destination's preceding sibling, so the title does not exist until after the bar is laid out. It sets the window title instead |
| **7** | **#31: `TextFieldStyle` and `ProgressViewStyle`** | Same shape as the four styles already converted, no blocker recorded or found. Placed after the free items but before anything needing five backends. Doing them also puts them back in the count |
| **8** | **#33: `ScrollViewReader`** | The first item needing a **new** `BackendFeatures` requirement across all five — `ScrollContainers` has no programmatic scroll at all. One protocol method, five implementations. Genuinely more expensive than everything above it, and cheaper than everything below |
| **9** | **#88 (= #33's `ColorPicker`)** | Self-contained: one view, one new protocol, five conformances, and every platform has a native picker to reach for. Nothing else in the list depends on it, which is why it is not higher despite being well understood |
| **10** | **#34 claim 2: arbitrary `Button` labels, then #31's `ButtonStyle`** | Strictly ordered: `ButtonStyle` needs `configuration.label` as a view and `isPressed` as a Bool, and `grep -rn isPressed Sources/` is 0. This is the only remaining hard dependency between two entries, so it is worth doing as one deliberate piece rather than discovering the order later |
| **11** | **#36: `.toolbar` and `.refreshable`** | Both need a new requirement on all five backends, and `.toolbar` additionally overlaps `ApplicationMenus`, which four of the five already conform to differently. Left until the cheaper five-backend job (#8) has established the pattern |
| **12** | **#35: `Settings` scene, `SceneStorage`, `DocumentGroup`** | Scene-level, so it touches `Scenes/` and the application-menu path on every backend. `SceneStorage` also needs a persistence story next to `AppStorage`, which exists and is the model to follow |
| **13** | **#32: `DragGesture`, `LongPressGesture`, `MagnificationGesture`, `RotationGesture`, `simultaneousGesture`** | Five new types plus five backend implementations each. Do it after item 2 has made hover honest, so the entry's premise is true before its body is built on |
| **14** | **#30: focus, accessibility, keyboard shortcuts** | The largest surface with literally nothing to start from, and the only area where an application cannot even express the intent. High value, but nothing above it depends on it, and it is five backends deep |
| **15** | **#28: animation and transitions** | The most expensive: it needs a clock and a driver inside the view graph, which is shared code with no precedent here, before any backend work begins. Three backends already own animation machinery for `GeometricEffects`, so the backend half is less empty than the framework half — but the framework half is the blocker |
| **16** | **#34: claims 1, 3, 5, 6, 7, 8, 9, 10** | Continuous rather than a single task; interleave the cheap ones (`Text` modifiers, `List.onDelete`) with the above. **Not 9 and not 10** — the todo already records why both look cheap and are not, and that reasoning was re-verified here: `CoordinateSpace` count is still 0, and `EdgeInsets` is still four `Int` fields at `PaddingModifier.swift:34` |
| **17** | **#27: follow desktop light/dark while running** | Last **not because it is expensive** — the binding exists at `Settings.swift:92` and needs a caller — but because it **cannot be verified on the current hardware**. WSLg produces zero notifications across all 55 `GtkSettings` properties. Writing it here would produce code nobody can show works, which is the exact shape this project refuses. Park it until a real GNOME desktop is available |

---

## Counts / 計數

Of the twelve entries, measured 2026-09-08:

- **Fully done: 0.**
- **Partly done: 8** — #85, #27, #31, #33, #34, #35, #36, #79.
- **Untouched: 4** — #88, #28, #30, #32.

Plus one entry that was on the list and should not have been: **#86 is fully
done on all five backends.**

十二筆之中，2026-09-08 實測：**完全完成 0 筆**；**部分完成 8 筆**（#85、#27、#31、#33、#34、#35、
#36、#79）；**完全未動 4 筆**（#88、#28、#30、#32）。此外還有一筆本不該在清單上的：**#86 在五個
backend 上全數完成**。

Every count in this document was produced by one of the two loops in
**Method**, run on 2026-09-08 with both controls answering. Re-derive rather
than quote: this document is a snapshot and will be wrong within the week.

本文件中的每一個計數都由**方法**一節的兩個迴圈之一產生，於 2026-09-08 執行，兩組控制組皆有作答。
請重新推導而非直接引用：本文件是一份快照，一週之內就會出錯。
