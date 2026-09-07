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
| **#85** | make LazyVStack/LazyHStack lazy, add LazyVGrid | both stacks **exist and are honestly documented as eager** — `LazyStacks.swift:38`, `:70`, and the doc comment at `:3` says so in both languages. `LazyVGrid` declaration count **0** | real laziness (needs ScrollView to report its visible rect into the layout pass); `LazyVGrid` from scratch. Both are pure composition — no backend requirement | — | — | — | — | — |
| **#88** | ColorPicker as an opt-in BackendFeatures protocol | `grep -rn "ColorPicker" Sources/` → **0**, across every file type, not only `*.swift` | everything: the `ColorPicker` view, a `BackendFeatures.ColorPickers` protocol, and five conformances | n/a | n/a | n/a | n/a | n/a |
| **#28** | animation and transitions, "no protocol at all" | **claim holds exactly.** `withAnimation` 0, `struct Animation` 0, `AnyTransition` 0, `func transition` 0, `Transition` 0 | all five names, plus a driver in the view graph and a per-backend animator | n/a | n/a | n/a | n/a | n/a |
| **#30** | focus, accessibility, keyboard shortcuts | **claim holds.** `FocusState` 0, `func focused` 0, `keyboardShortcut` 0, `accessibilityLabel` 0, `\bFocus\b` 0. The single `accessibility` hit is prose in `HelpModifier.swift` | the whole area. Still the only area where an application cannot express the intent | n/a | n/a | n/a | n/a | n/a |
| **#32** | gestures beyond tap and hover | the new gestures are absent as claimed — `DragGesture` 0, `LongPressGesture` 0, `MagnificationGesture` 0, `RotationGesture` 0, `simultaneousGesture` 0, `\bGesture\b` 0. **But the premise is wrong: hover is not done on five backends** | the five gesture types, *and* `HoverGestures` on AndroidBackend — see the flag below | ✅ | ✅ | ✅ | ✅ | ❌ hover |
| **#34** | API shapes that do not compile from SwiftUI code | audited 2026-08-27, "all ten claims still stand". **Eight still stand. Claim 4 is now false and claim 2 is half false** | claims 1, 3, 5, 6, 7, 8, 9, 10 | — | — | — | — | — |
| **#36** | confirmationDialog and safeAreaInset done, four remain | both are real: `ConfirmationDialogModifier.swift:50`, `SafeAreaInsetModifier.swift:39`. `func popover` 0, `fullScreenCover` 0, `toolbar` 0, `refreshable` 0, and `navigationTitle` **0 as a modifier** | `.popover`, `.fullScreenCover`, `.toolbar`, `.refreshable` — **and `.navigationTitle`, which left the denominator without being implemented** | n/a | n/a | n/a | n/a | n/a |
| **#27** | follow desktop light/dark while running (GtkBackend) | **claim holds, and the mechanism is already built.** `Gtk.Settings.registerNotification(named:handler:)` exists at `Sources/Gtk/Utility/Settings.swift:92` and **has zero callers** across `Sources/`. The ambient scheme is sampled **once**, at `GtkBackend.swift:1029` | wire the notification up (six changes, per the task history). Windows has the same shape from the other side: `systemColorScheme` reads the registry once inside `sampleAmbientColorScheme` and `grep -rn WM_SETTINGCHANGE Sources/` → **0** | ❌ | — | — | — | — |
| **#31** | 4/6 done, only ButtonStyle and LabelStyle remain | **5 present, and the denominator shrank silently.** `ShapeStyle` is a real protocol at `Styles/ShapeStyle/ShapeStyle.swift:25` with `Color`, `LinearGradient` and `RadialGradient` conforming — the todo still says "absent — 0 declarations and 0 references". `TextFieldStyle` 0 and `ProgressViewStyle` 0 were on the 2026-09-01 list and quietly left the count | `ButtonStyle` (genuinely blocked: `isPressed` 0 across `Sources/`, `Button.label` is a `String` at `Button.swift:17`), `LabelStyle` (**blocker gone**), `TextFieldStyle`, `ProgressViewStyle` | — | — | — | — | — |
| **#33** | 8 of 11 done, ColorPicker/LazyVGrid/ScrollViewReader remain | **10 present of a 16-name list, 6 absent.** Three names that the 2026-09-01 census counted absent — `Grid`, `ControlGroup`, `GroupBox`, all still **0** — left the denominator without being implemented | `LazyVGrid`, `Grid`, `ScrollViewReader`, `ControlGroup`, `GroupBox`, `ColorPicker`. `ScrollViewReader` is the expensive one: `BackendFeatures.ScrollContainers` has only `createScrollContainer` and `updateScrollContainer` and **no programmatic scroll**, so it needs a new requirement on all five | n/a | n/a | n/a | n/a | n/a |
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

`LazyVGrid` declaration count **0**. `GridItem` reference count **0**
(`grep -rn GridItem Sources/SwiftCrossUI --include=*.swift | wc -l`), so a grid
needs the item type too, not only the container.

Neither half touches a backend: a lazy grid is composition, and real laziness is
a change to the layout system (ScrollView reporting its visible rect), which is
shared code.

兩個 stack 都存在（`LazyStacks.swift:38`、`:70`），且該檔案的說明比 todo 更明確地指出它們並非惰性。
`LazyVGrid` 宣告計數為 0，`GridItem` 引用計數也是 0。兩半都不觸及任何 backend。

---

### #88 — untouched, and the cleanest of the twelve to scope

`grep -rn "ColorPicker" Sources/` returns **0** — across every file, not only
`*.swift`. (The 23-file hit for the same string across the repository is
`testapp/gtk4-source/`, a vendored copy of GTK's own C sources, plus test-app
and doc files. None of it is SwiftCrossUI.)

What is needed is stated in the entry itself and is accurate: a `ColorPicker`
view, a `BackendFeatures.ColorPickers` protocol, and five conformances. Nothing
exists to disagree with.

`grep -rn "ColorPicker" Sources/` 回傳 **0**——是所有檔案，不只 `*.swift`。整個 repo 中同一字串的
23 個命中檔案來自 `testapp/gtk4-source/`（GTK 自身 C 原始碼的內嵌副本）與測試 app／文件，與
SwiftCrossUI 無關。此條目所述內容準確，沒有任何東西可以與之相左。

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

Absent: `func popover` 0, `fullScreenCover` 0, `toolbar` 0, `refreshable` 0.
The six `popover` reference hits are all prose — `Menus.swift`,
`MenuImplementationStyle.swift`, `DismissAction.swift`, `Menu.swift`,
`BackendDatePickerStyle.swift`, `BuiltinDatePickerStyles.swift` — describing
GTK's popover *menu*, not a `.popover` presentation modifier.

**`navigationTitle` was on the 2026-09-01 list and is not on the 2026-09-04
one, and it was never implemented.** Its only two hits are comments in
`Views/NavigationStack.swift:83` and `:96`, and one of them says so outright:
*"When `View/navigationTitle(_:)` lands, this is where it reads from."* So #36
is 2 of 7, not 2 of 6.

Backend cost is uneven and worth recording before ordering the work: `.popover`
has a backend capability already (`BackendFeatures.PopoverMenus`, conformed by
GtkBackend at `GtkBackend.swift:36`), `.fullScreenCover` is close to `Sheets`
(four of five conform), while `.toolbar` and `.refreshable` need a new
requirement on all five.

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

### #33 — ten present of sixteen, and the denominator moved twice

Declaration counts, 2026-09-08:

| name | on 2026-09-01 census | now |
|---|---|---|
| `Form` | absent | ✅ `Views/Form.swift:31` |
| `Section` | absent | ✅ `Views/Section.swift:22` |
| `Label` | absent | ✅ `Views/Label.swift:45` |
| `Stepper` | absent | ✅ `Views/Stepper.swift:21` |
| `LazyVStack` | absent | ✅ `Views/LazyStacks.swift:38` (eager — see #85) |
| `LazyHStack` | absent | ✅ `Views/LazyStacks.swift:70` (eager — see #85) |
| `Gauge` | absent | ✅ `Views/Gauge.swift:19` |
| `LazyVGrid` | absent | ❌ 0 |
| `Grid` | absent | ❌ 0 — **left the denominator, never implemented** |
| `ScrollViewReader` | absent | ❌ 0 |
| `ControlGroup` | absent | ❌ 0 — **left the denominator, never implemented** |
| `GroupBox` | absent | ❌ 0 — **left the denominator, never implemented** |
| `DisclosureGroup` | not censused | ✅ `Views/DisclosureGroup.swift:20` |
| `LabeledContent` | not censused | ✅ `Views/LabeledContent.swift:19` |
| `Link` | not censused | ✅ `Views/Link.swift:39` |
| `ColorPicker` | not censused | ❌ 0 — this is #88 |

Ten present, six absent. Regenerate with the declaration-count loop in
**Method** above.

**`ScrollViewReader` is the one that is not composition.**
`BackendFeatures.ScrollContainers`
(`Backend/BackendFeatures/Containers/ScrollContainers.swift:6`) declares exactly
two methods — `createScrollContainer(for:)` at `:25` and
`updateScrollContainer(...)` at `:44`, whose parameters are bounce and
scroll-bar flags. **There is no way to ask a scroll container to move.** So
`ScrollViewReader` needs a new backend requirement and five implementations, not
a new view. `Grid`, `GroupBox`, `ControlGroup` and `LazyVGrid` are all
composition and need nothing from any backend.

十六個名稱中十個存在、六個缺席。三個名稱（`Grid`、`ControlGroup`、`GroupBox`）在未被實作的情況下
離開了分母。`ScrollViewReader` 是唯一不屬於「組合」的一項：`ScrollContainers` 只有建立與更新兩個
方法，**沒有任何「請捲動到某處」的途徑**，因此它需要一項新的 backend requirement 與五份實作。

---

### #35 — two of four wrappers, and "only a Settings scene" understates it by three

| name | declared |
|---|---|
| `StateObject` | ✅ `State/StateObject.swift:49`, `@propertyWrapper` at `:48` |
| `ObservedObject` | ✅ `State/ObservedObject.swift:40`, `@propertyWrapper` at `:39` |
| `EnvironmentObject` | ❌ 0 |
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

So four things remain, not one. `EnvironmentObject` is the cheap one: it is a
sibling of `ObservedObject`, which already exists, and needs nothing from a
backend.

2026-09-01 的盤點列出四個缺席的 wrapper，其中兩個已落地，因此 wrapper 那一列是 **2/4** 而非 3/4；
「3/4」似乎把 scene 那一列併了進來。剩下的是四項而非一項：`EnvironmentObject`、`SceneStorage`、
`Settings` scene、`DocumentGroup`。其中 `EnvironmentObject` 最便宜——它是已存在的 `ObservedObject`
的兄弟，且不需要任何 backend 支援。

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

## Overlaps — where two entries are the same work / 重疊之處

Counting these twice inflates the remaining work by three items.

重複計算會使剩餘工作量虛增三項。

| entries | shared work | note |
|---|---|---|
| **#33 ↔ #88** | `ColorPicker` | #33 lists it as one of its three remaining views; #88 *is* that view plus its backend protocol. **One job.** Do it under #88, where the backend half is scoped |
| **#33 ↔ #85** | `LazyVGrid` | #33 lists it as remaining; #85 asks for it by name. **One job**, and it is composition-only. #85's *other* half — making the existing stacks lazy — is unrelated to #33 and is a layout-system change |
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
| **4** | **#33 + #85: `GroupBox`, `ControlGroup`, `Grid`, `LazyVGrid`** | Four views, all pure composition, no backend requirement, and they close the #33↔#85 overlap in one pass. `LazyVGrid` needs `GridItem` too (reference count 0), which `Grid` wants anyway — so doing them together is cheaper than either alone |
| **5** | **#35: `EnvironmentObject`** | A sibling of `ObservedObject`, which already exists at `State/ObservedObject.swift:40` and can be copied. Framework-only. Closes the largest part of #35's understatement for the least work |
| **6** | **#36: `.popover` and `.fullScreenCover`** | The first two of #36's remainder that already have a backend capability underneath — `PopoverMenus` and `Sheets` respectively — so neither adds a requirement to five backends. `.navigationTitle` belongs in this batch too: `NavigationStack.swift:83` already says where it would read from |
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
