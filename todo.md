# todo

Work that is known, sized and not done. Written 2026-08-27 from a working
session's task list, which otherwise lives nowhere.

Each entry says what was measured rather than what was assumed, because several
items here exist only because a confident guess was checked and turned out to be
wrong. Where a number appears, the command that produced it is beside it or in
the file it points at.

已知、已估過規模、尚未完成的工作。於 2026-08-27 自某次工作階段的任務清單寫成——否則那份清單不會
留在任何地方。

每一項記錄的是「量到什麼」而非「假設什麼」，因為此處有數項之所以存在，正是因為某個看似有把握的猜測
被查證後證實是錯的。凡出現數字之處，產生它的指令就在旁邊，或在它所指向的檔案裡。

**Entries are tagged with the platform they were written on** — (Windows),
(Mac), (WSL). Not for credit: this file is the only channel between two sessions
that cannot talk to each other, and a measurement's platform is often the thing
that decides whether it applies. "Cannot be verified here" means something
different depending on where "here" was.

**每一項條目都標記了它是在哪個平台上寫下的**——(Windows)、(Mac)、(WSL)。這不是為了記功：本檔是
兩個無法互相通訊的 session 之間唯一的通道，而一項量測結果出自哪個平台，往往正是決定它適不適用的
關鍵。「此處無法驗證」的意思，會隨著「此處」是哪裡而不同。

---

## Now / 現在

### Style protocols: follow SwiftUI's shape wherever SwiftUI has one (Windows)

Audited 2026-08-27. The project is not inconsistent with SwiftUI so much as
inconsistent with itself — one style already follows SwiftUI's protocol shape
and the rest do not:

| SwiftUI has | ours | follows |
|---|---|---|
| `PickerStyle` protocol | `public protocol PickerStyle: Sendable`, with `Default`/`Inline`/`Menu`/`RadioGroup` structs and an internal `_BuiltinPickerStyle` | yes |
| `DatePickerStyle` protocol | protocol since 2026-08-27 — the enum lives on as `BackendDatePickerStyle` | yes |
| `ListStyle` protocol | protocol since 2026-08-27 — the enum lives on as `BackendListStyle`, and GtkBackend now reads it | yes |
| `ToggleStyle` protocol | protocol since 2026-08-27 — the nested `Style` enum lives on as `BackendToggleStyle` | yes |
| `ButtonStyle`, `LabelStyle`, `ShapeStyle` | absent — 0 declarations and 0 references each | no |

**A correction, kept rather than quietly fixed.** The first version of this table
said all four of `ButtonStyle`, `LabelStyle`, `ShapeStyle` and `ToggleStyle` were
absent. `ToggleStyle` is not: it has one declaration and ten references, and
`Toggle.body` switches on it. The audit that produced the row piped a `grep`
through `head -10` and read the truncated output as the whole answer. Re-derive
with counts, which cannot be truncated into looking complete:

    for n in ButtonStyle LabelStyle ShapeStyle ToggleStyle ListStyle; do
      printf '%-12s %s %s\n' "$n" \
        "$(grep -rn "\(struct\|enum\|protocol\) $n\b" Sources/ --include=*.swift | wc -l)" \
        "$(grep -rn "\b$n\b" Sources/ --include=*.swift | wc -l)"
    done

The cost is specific and easy to miss, which is why it belongs beside #34 rather
than on a feature checklist. An enum keeps the *call sites* compiling —
`.datePickerStyle(.compact)` is fine — and breaks only when someone writes their
own style. `struct MyStyle: DatePickerStyle` compiles against SwiftUI and does
not compile here, and nothing in the API surface hints at why.

Decided: follow the protocol shape everywhere, including adding the four that do
not exist. `PickerStyle` is the worked example to copy — protocol, an internal
`_Builtin` protocol for the cases a backend must recognise, and one named struct
per style.

`DatePickerStyle`, `ToggleStyle` and `ListStyle` are done (2026-08-27, Windows).
`ButtonStyle` and `LabelStyle` are blocked, below.

**`ButtonStyle` cannot be written yet, and the blocker is `Button`.** SwiftUI's
`ButtonStyle.makeBody(configuration:)` receives `configuration.label` as a
*view* and `configuration.isPressed` as a Bool. Neither exists here.
`Button.label` is a `String` — the codebase says so itself, in the comment on
`Button._buttonWidth`: "a temporary button width solution until arbitrary labels
are supported". And press state is nowhere: `grep -rn "isPressed" Sources/`
returns nothing in any backend. A `ButtonStyle` built on top of today's `Button`
would hand every style an empty label and an `isPressed` that is always false,
which is a worse outcome than not having it. Arbitrary button labels first.

**`LabelStyle` has nothing to style.** There is no `Label` view — it is one of
the missing views under SwiftUI parity below.

**`ShapeStyle` is blocked below the protocol too, on what a backend can paint.**
`BackendFeatures.Paths.renderPath` takes two resolved `Color`s —
`strokeColor:` and `fillColor:` — and `StyledShape` stores `Color?` for each.
`Shape.fill(_:)` and `Shape.stroke(_:style:)` take a concrete `Color`. The whole
point of SwiftUI's `ShapeStyle` is that `Color`, `LinearGradient` and `Material`
are interchangeable there, and nothing but a flat colour can reach a backend
from here.

A `ShapeStyle` that only `Color` conforms to would be `Color` with extra steps,
and it would pin a `resolve(in:) -> Color` signature that has to break the day a
gradient fill arrives. The real work is `renderPath` accepting something richer
than two colours, across six backends, plus a gradient fill in each — which is
its own project and not a matter of following a protocol shape.

`ToggleStyle` was the one of the three that could be done, and it was the
tidiest starting point of any style here: already a struct with `.switch`,
`.button` and `.checkbox` statics and an `@_spi(Backends)` nested enum, so the
split between application vocabulary and backend vocabulary predated the
protocol. Its label is a `String` for the same reason `Button`'s is, and that is
recorded on the protocol rather than worked around.

**`ListStyle` was inert, and converting it first would have published a no-op.**
Done 2026-08-27, both halves in one change, exactly as this section asked for.
The paragraphs below are the reasoning as it stood before the work and are kept
so the ordering argument survives; what changed is recorded after them.

Measured 2026-08-27: `grep -rn listStyle Sources/ Tests/` returns exactly two lines —
`EnvironmentValues` declaring the entry, and `SplitView` setting it to `.sidebar`
for its sidebar column. **No backend reads it.** Not GtkBackend, not
WinUIBackend, not AppKit, UIKit, Android or Dummy; the count across all six is
zero.

So the shape is not the first problem. Giving it SwiftUI's protocol shape and a
public `.listStyle(_:)` modifier would hand applications a call that provably
does nothing, which is worse than the enum: today it is at least hidden behind
`@_spi(Backends)` and promises nobody anything. That is the exact failure
`testapp/gtk-silent-noops.md` exists to catalogue.

Do the two together instead — the conversion in the same change that makes at
least one backend honour it, so the public API is real on the day it appears.
For GtkBackend the likely mechanism is the `navigation-sidebar` CSS class that
GTK 4 and libadwaita already style; check first whether `List` reaches a
`GtkListBox` at all, since `SelectableListViews` is an opt-in feature.

**What was found, and what it cost.** `navigation-sidebar` was the mechanism —
but GtkBackend was *already* adding it, in `createSelectableListView`, to every
list unconditionally. So the bug was not "the style does not reach the backend";
it was that the backend had one hard-coded appearance and it was the sidebar
one. Every `List` in every app was drawn as a sidebar, and nothing said so,
because there was no second appearance to compare against. The styling moved to
`updateSelectableListView`, which receives the environment and can switch on
`backendListStyle`.

Verified on Windows/GtkBackend by driving `actions/win/P7-list-selection.csv`,
which selects a row in each of P7's two lists. Before, both selections were the
same muted grey. After, the plain `List` fills the selected row with GTK's blue
accent across the full row width, and the `NavigationSplitView` sidebar keeps
the inset grey. Re-run with:

    SCUI_DEBUG=1 zsh testapp/compile.zsh -gtk4 P7
    ( cd testapp/output && ./P7.exe -actionfile "$(cygpath -m "$PWD/../actions/win/P7-list-selection.csv")" & )

`SCUI_DEBUG=1` is not optional: without it `DebugFeatures` strips `-actionfile`,
the app launches and ignores the flag in silence, and the capture shows the
untouched baseline. That cost three launches here before the empty log was read
as the answer rather than as a missing feature.

The protocol half followed `PickerStyle`, with one departure recorded on the
protocol itself: `ListStyle` has no `makeView`. A list style changes how the
backend draws its own list widget rather than substituting a view for it, so
there is no custom-style-out-of-ordinary-views case to support, and every
conformer is a built-in.

One build failure worth keeping, because the error names neither file:
deleting the old `Environment/ListStyle.swift` was required, not tidiness.
Emptying it to a pointer comment left two files named `ListStyle.swift` in one
target, and SwiftPM derives object names from the basename —
`couldn't build ListStyle.swift.o because of multiple producers`. `DatePickerStyle`
and `ToggleStyle` never hit this: their old definitions lived inside
`DatePicker.swift` and `Toggle.swift`.

Still open, and not a blocker on the protocol: WinUIBackend builds and links
against it but does not read `backendListStyle`, so a WinUI `List` looks the
same either way. Same for AppKit, UIKit, Android and Dummy. `.listStyle(_:)` is
therefore honest on GtkBackend and a no-op elsewhere — which is the ordinary
state of a backend feature here, not the "public API that does nothing anywhere"
this section was written to prevent.

### Swift 6 language mode, module by module (Windows)

`Package.swift` declares `swift-tools-version:6.0`, so an older toolchain is
refused — that half is done. Every target is then pinned back to `.v5` by the
sweep at the bottom of that file. Lifting a target means adding its name to
`migratedToSwift6` and fixing what the compiler then says.

**That instruction changed on 2026-08-27, and the old one never worked.** It
used to say "delete it from `stillOnSwift5`", but `stillOnSwift5` was
`Set(package.targets.map(\.name))` — a derived set with no entries to delete. So
nobody could have followed it. The list is now the *migrated* targets rather
than the remaining ones, which also means a target added later defaults to v5
instead of silently landing on v6 and breaking the build for whoever added it. A
name in the list that matches no target now fails the manifest, because a typo
there is otherwise silent: the target stays on v5 and reads as done.

| target | errors when first measured | now |
|---|---|---|
| SwiftCrossUI | 1 site | **migrated** |
| GtkBackend | 98 | **migrated — 0, without touching the target at all** |
| WinUIBackend | 1274 | **migrated — 10 real errors after the SwiftCrossUI fix, all fixed** |
| AppKitBackend | 5 | still v5; needs a Mac |
| UIKitBackend | still unmeasured | needs an iOS-SDK build |

**The 98 and the 1274 were almost entirely one defect, in a third module.**
`Core` declares `runInMainThread` `nonisolated` inside an otherwise `@MainActor`
protocol and the default implementation in `BaseStubs` did not repeat the
keyword, so every conformance in every backend reported the mismatch. Two
`nonisolated` keywords in `SwiftCrossUI` took GtkBackend from 98 to **0** with
no change to GtkBackend whatsoever, and WinUIBackend from 1274 to 10.

That is worth remembering before sizing the two remaining backends. AppKitBackend's
five were measured on the Mac *before* this fix, and two of them are named
`runMainLoop` and `runInMainThread` — the same shape. The number to re-measure
against is not 5.

WinUIBackend's ten were four distinct problems, and the annotations are the
answer for three of them because the invariant is Win32's rather than
Swift's:

- `windowsByHWND` is read from a `WNDPROC`, a C function pointer that cannot
  carry isolation. `nonisolated(unsafe)`, because what keeps it safe is that
  Win32 delivers a window's messages only on the thread that created it.
- three drag-and-drop captures (`self`, `args`, `deferral`) cross into a
  `Task { @MainActor }` from a WinRT completion handler. `nonisolated(unsafe)`
  locals: the other thread only *captures* the references, every line that uses
  them is inside the task.
- the incoming-URL handler could not be stored in a `Mutex` at all.
  **`nonisolated(unsafe)` on a local does not help for a closure** — it works
  for a reference being passed along but does not strip isolation from a
  function value's type. That one needed an `@unchecked Sendable` box.

**Verify the mode is on before trusting a count of zero.** `swift build -v |
grep -c "swift-version 6"` counts every invocation including dependencies —
measured, a single build of this package showed 22 at v5 and 271 at v6. The
question is what flag the *named module* got:

    swift build --target <T> -v 2>&1 | grep -- "-module-name <T> " \
      | grep -oE '\-swift-version [0-9]+' | sort | uniq -c

Touch the target's sources first or the build is a no-op and prints nothing,
which reads as "not found" rather than "not rebuilt". Check it against a target
still on the pin, so a wrong answer cannot look like a right one.

AppKitBackend measured 2026-08-27 on the Mac, by lifting it alone and building
it. Five diagnostics, and they are one shape and a
half rather than five problems:

- three are the same conformance-isolation error, `AppKitBackend.swift:22:35`,
  once each for `AngularGradients`, `LinearGradients` and `RadialGradients` --
  the plain `public final class` conforming to `@MainActor` protocols, exactly
  the shape GtkBackend's 98 and WinUI's 1274 mostly are;
- two are `sendability of function types ... does not match requirement in
  protocol 'Core'`, on `runMainLoop` and `runInMainThread(action:)`.

So AppKitBackend is small, and it is small in the same way the others are large.
It is a candidate for going first: whatever fixes those three conformances is
the pattern the other two backends need hundreds of times.

UIKitBackend is still unmeasured, and not for want of a Mac. A host build cannot
resolve `import UIKit`, and `SCUI_HOST_BACKENDS_ONLY=1` -- which is what makes
this package configure on macOS at all -- deletes the target outright. Measuring
it needs an iOS-SDK build through xcodebuild with the target present, which is a
different setup rather than a longer wait.

**A second measurement trap, in the same family as the one below.** The first
attempt at the number above used `swift build --target AppKitBackend -Xswiftc
-swift-version -Xswiftc 6` and reported 8. That number was from `ImageFormats`,
a dependency: `-Xswiftc` is global, so it flipped every target and the build
failed before it reached AppKitBackend. Lifting the one target in the manifest
is the mechanism that measures that target. Counting is its own
trap -- grepping `error:` over the raw output gave 12, because the compiler's
caret rows and the build system's two summary lines match too. Five is the
count of lines naming a file in `Sources/AppKitBackend/`, and it equals the
number of distinct diagnostics.


**SwiftCrossUI is migrated — done 2026-08-27, Windows.** It was two `nonisolated`
keywords, and the paragraph below, which is kept because it was confidently
wrong, predicted something else entirely:

> The one SwiftCrossUI site is the hard one. [...] Both of the compiler's fix-its
> fail: an isolated conformance is rejected because the protocols inherit
> `SendableMetatype`, and marking the requirements `nonisolated` would be a false
> claim about the whole backend protocol. That one needs a decision about the
> protocols, not a local edit — do not read "1 error" as "1 minute".

What was actually wrong had nothing to do with `BaseStubsTest`, which is why
every fix aimed at `BaseStubsTest` failed. `Core` declares `runInMainThread`
`nonisolated` inside an otherwise `@MainActor` protocol — correctly, since the
point of that method is to be callable off the main thread — and the default
implementation in `BaseStubs` did not repeat the keyword. An extension on a
`@MainActor` protocol is main-actor isolated, so the witness was isolated where
the requirement was not, and the diagnostic surfaced at the only conformance
that exists.

`@MainActor` on `BaseStubsTest` was tried and does not work, for a reason worth
keeping: it isolates *that* witness too, so it moves the error rather than
removing it. The reading that misled the earlier estimate was of the direction
of the crossing — the type was assumed to be the un-isolated side.

Two keywords: `nonisolated` on the `runInMainThread` default, and on the
`todo()` helper it calls. Verified with `swift build --target SwiftCrossUI`
under `migratedToSwift6: ["SwiftCrossUI"]`. A whole-package `swift build` is not
the check on Windows — it fails on `DefaultBackend` for the pre-existing reason
recorded under test infrastructure below.

Most of GtkBackend's 98 and probably most of WinUI's 1274 come from one shape:
the backends are plain `public final class`es with no isolation annotation
conforming to `@MainActor` protocols.

**A measurement trap, recorded so it is not repeated.** `swift build -Xswiftc
-swift-version -Xswiftc 6` is *not* the language mode. It is global, so it
recompiles dependencies too — the first probe reported 17 errors, every one of
them inside `.build/checkouts/swift-image-formats` and none in our code. Size
this job with `swiftLanguageMode`, never with `-Xswiftc`.

### Action files are tied to the display scale — done 2026-08-27

`GtkBackend` now passes `gtk_widget_get_scale_factor` to the synthesiser, so a
coordinate is scaled by what the toolkit laid out with rather than by what
`GetDpiForWindow` reports. Kept here as the record of what was and was not
verified, because one half could not be.

Verified: no change at 100% on Windows (P21's counter reads 3, GTK reports 1.0),
and the *differing* case on Linux, where `GDK_SCALE=2` makes GTK report 2.0 and
lay out 820x720 → 1640x1080, and the same one-line file lands exactly 410,400
further into the window than at scale 1.

Not verified: Windows at any scale other than 100%. `GDK_SCALE` cannot stand in
for it — measured 2026-08-27, GTK 4 on Windows **ignores it entirely**, producing
a pixel-identical window and still reporting 1.0. WinUIBackend keeps
`GetDpiForWindow` on the reasoning that a DIP framework scales fractionally;
nothing has ever been driven against it at another scale, so that is reasoning
rather than a measurement.

The Linux path needed a fix of its own to make this safe, and it was one this
change introduced. `XdotoolSynthesiser` reported a *physical* window origin
while `screenPosition` multiplies the whole sum by the scale, so passing a scale
other than 1 doubled the origin along with the point. Invisible while the scale
was hard-coded to 1. Found by solving for the origin under both models and
seeing which reproduced the reparenting inset this file already documented:
`(origin + point) * scale` gave -38,-59 at both scales, `origin + point * scale`
gave -38,-59 at one and 154,-6 at the other.

---

## GtkBackend gaps / GtkBackend 的缺口

- **WinUIBackend's WebView: diagnosed, half fixed, and the remaining half is
  characterised.** Investigated 2026-08-28 with P38.

  **Wrong premise found and corrected.** The class documentation said the control
  starts its rendering process on demand the first time it is asked to navigate,
  so nothing had to call `EnsureCoreWebView2Async`. That is false, and it is why
  the web view has drawn nothing for as long as it has existed. `updateWebView`
  now calls it, once, and **observes the completion instead of discarding it** —
  `_ = try? ensureCoreWebView2Async()` cannot fail visibly, which is how a
  never-starting browser looked exactly like an empty rectangle.

  **Still open: the async action never completes.** Measured with the element in
  the tree, visible, and correctly arranged at 760x420: `coreWebView2` stays nil
  at +2 s and +6 s, and the completion handler never fires with any status —
  neither success nor failure. It hangs rather than fails. `WebView2` got far
  enough to create `P38.exe.WebView2/EBWebView/EBWebViewMetrics` next to the
  binary, 24 KB and no browser profile, so initialisation begins and stalls.
  The Edge WebView2 runtime is installed (151.0.4129.107).

  **Two measurement traps, both worth keeping:** a WinUI app's `releaseConsole()`
  reopens stdout onto `NUL:` before anything runs, so the first version of the
  diagnostic produced an empty log and read as "`updateWebView` is never called";
  it has to write to a file. And `actualWidth` read inside `updateWebView` is 0
  for *every* widget, because that runs in commit before WinUI arranges anything
  — sampling it there nearly produced a confident wrong diagnosis of a sizing
  bug. Sampled from a delayed `@MainActor` Task it reads 760x420.

  Next: find why the action never completes. Likely candidates are the apartment
  or message pump the WinRT async machinery needs, since the same
  `promise.completed` pattern works for alerts and file dialogs elsewhere in this
  backend.

- **WinUIBackend 的 WebView：已診斷、修好一半，另一半已被刻畫清楚。** 2026-08-28 以 P38 調查。

  **找到並更正了一個錯誤前提。** 該類別的文件說：控制項會在第一次被要求導覽時按需啟動其繪製行程，
  因此無須任何人呼叫 `EnsureCoreWebView2Async`。那是錯的，而這正是這個 web view 自存在以來什麼都
  畫不出來的原因。`updateWebView` 現在會呼叫它一次，並且**觀察其完成結果而非丟棄** ——
  `_ = try? ensureCoreWebView2Async()` 不可能明顯地失敗，而那正是「永遠啟動不了的瀏覽器」看起來
  與「一個空白矩形」一模一樣的原因。

  **仍未解決：該非同步動作永遠不會完成。** 在元素已位於樹中、可見、且已正確排版為 760x420 的情況下
  實測：`coreWebView2` 在 +2 秒與 +6 秒時皆為 nil，而完成處理器從未以任何狀態觸發——既非成功也非
  失敗。它是卡住，而不是失敗。`WebView2` 進展到足以在執行檔旁建立
  `P38.exe.WebView2/EBWebView/EBWebViewMetrics`（24 KB，且無瀏覽器設定檔），因此初始化確實開始了，
  然後停滯。Edge WebView2 runtime 已安裝（151.0.4129.107）。

  **兩個值得保留的量測陷阱：** WinUI app 的 `releaseConsole()` 會在任何程式碼執行前把 stdout 重新
  導向到 `NUL:`，因此本診斷的第一版得到空白 log，讀起來像是「`updateWebView` 從未被呼叫」——它必須
  寫入檔案。以及，在 `updateWebView` 內讀取的 `actualWidth` 對**每一個** widget 都是 0，因為該處在
  commit 中執行、早於 WinUI 進行 arrange——在那裡取樣，差一點就給出一個自信而錯誤的「尺寸 bug」
  診斷。改由延遲的 `@MainActor` Task 取樣，讀到的是 760x420。

  下一步：找出該動作為何永不完成。可能的方向是 WinRT 非同步機制所需的 apartment 或訊息幫浦，因為
  同樣的 `promise.completed` 模式在本 backend 的警示框與檔案對話框中都能正常運作。

- **Follow the desktop's light/dark change while running.** The binding defects
  are fixed (`addNotificationSignal`, and `Settings.default` caching its
  wrapper). What remains is six changes in `GtkBackend.swift`, listed in the
  task history. **Cannot be verified in WSL at all**: measured, a
  `gsettings set` produces zero notifications across all 55 `GtkSettings`
  properties, because WSLg has no `xdg-desktop-portal`, no XSettings manager and
  no libadwaita. Needs a real GNOME desktop.
- **Done 2026-08-27: returning to the ambient colour scheme left Gtk in the
  overridden one.** `updateWindow` compared `preferredColorScheme` against
  `ambientColorScheme`, so a request that *matched* ambient wrote nothing — and
  after an earlier request had already moved Gtk away, nothing moved it back.
  Reproduced on Windows with the desktop in dark mode by driving
  `actions/win/P15-colour-scheme.csv`, which presses Light then Dark: P15 ended
  up reporting `Requested: dark  Resolved: dark` over a light window with
  dark-scheme (light) text, almost entirely illegible. Now compared against what
  the backend last told Gtk to draw, so the round trip writes. An app that never
  overrides still writes nothing after the startup sample, which is the property
  the old comparison was there for. Pressing Dark alone on a dark desktop passes
  either way — the round trip is the test.
- **`windowScaleFactor` never propagates**, and `WinUIBackend` has the identical
  gap. `computeWindowEnvironment` never computes it and the Gtk module has no
  binding for it. Window *activation* already propagates correctly — the issue's
  original "window environment changes never propagate" was too broad.
- **DatePicker `.wheel`: done 2026-08-27, and the reason it was skipped was
  wrong.** The old comment said GTK "has no wheel widget of any kind, and faking
  one out of a scrolled list would be a worse lie than the fallback". But
  SwiftUI's own documentation describes `.wheel` as showing "each component as
  columns in a scrollable wheel", and on iOS it is a `UIPickerView` — N columns
  of scrollable text. A scrolled list per component is not a fake of the wheel,
  it *is* the wheel; neither AppKit nor UIKit has a single "wheel widget"
  either. `DateWheel` is three scrollable single-selection columns, and it
  scrolls the selection to the middle, without which a hundred years of rows
  opened showing 1925 while the date was 2025.

  What GTK genuinely lacks is momentum and snapping: there is no scroll-snap in
  GTK 4, so a column settles where it is left rather than clicking to the
  nearest row. Cosmetic difference in the same widget, recorded rather than
  hidden.

  P41 is the app, and it did not exist before: **nothing on this side used
  `DatePicker` at all** — only P11, which is macOS-scoped — so no date picker
  question had a picture anywhere.

- **WinUIBackend `.graphical`: fixed, and the fix exposed a second defect.**
  Found 2026-08-27 with P41 on WinUI: `.graphical` was a blank sliver while the
  other three styles drew. The cause was the guess in the earlier note — a
  `CalendarView` reports 0x0 before its template has rendered, and SwiftCrossUI
  committed that. `WinUIBackend.swift` now substitutes a default month-view size
  in that case. Verified: the month grid draws.

  **Still open, and only visible now that it draws: the calendar ignores its
  binding.** It opens on August 2026 with the 27th selected — today — while the
  bound date is 2025-08-24, which `.automatic`, `.compact` and `.wheel` all show
  correctly in the same window. So the view renders and does not follow the
  state it was given. Not diagnosed.

- **WinUIBackend `.graphical`：已修復，而該修復暴露了第二個缺陷。** 2026-08-27 以 P41 於 WinUI
  發現：`.graphical` 只是一條空白細條，而其餘三種樣式都能繪製。原因正如先前註記的猜測——
  `CalendarView` 在其樣板尚未繪製前會回報 0x0，而 SwiftCrossUI 直接採信了。`WinUIBackend.swift`
  現在會在該情況下代入預設的月曆尺寸。已驗證：月份格線可正常繪製。

  **仍未解決，且唯有在它能繪製之後才看得見：該日曆忽略它的綁定值。** 它開在 2026 年 8 月並選取
  27 日——也就是今天——而綁定的日期是 2025-08-24，同一個視窗中的 `.automatic`、`.compact` 與
  `.wheel` 都正確顯示了該日期。也就是說，這個 view 畫得出來，卻不跟隨它被賦予的狀態。未診斷。

- **WinUIBackend `.automatic` and `.wheel` are the same control**, both
  `CustomDatePicker.DateViewType.datePicker`. Arguably correct rather than a
  defect: WinUI's `DatePicker` fields open looping selectors, so it *is* the
  wheel, and it is also what a Windows app shows by default. Worth knowing when
  comparing screenshots, since two styles being identical is elsewhere the
  signature of a silent fallback.
- **21 catalogued silent no-ops**, ranked by severity × cheapness in
  `testapp/gtk-silent-noops.md`, with a seven-entry appendix of things that look
  like no-ops and are not. Findings 1, 3, 4, 6 and 9 are fixed; each keeps its
  original text behind a `<details>` so the ranking argument stays readable.
  Re-derive the remaining count rather than trusting this sentence:
  `grep -c '^## [0-9]' testapp/gtk-silent-noops.md` counts every heading, and
  the fixed ones are the `~~struck~~` half of each pair.
- **Diagnostics are compiled out of the builds this project tests.**
  `debugLogOnce` is `#if DEBUG` while `compile.zsh` builds release by default,
  so both of GtkBackend's diagnostic call sites print nothing in the one
  configuration everything is actually run in. `DatePickerStyleModifier`'s
  `assertionFailure` has the same shape. The project already has `SCUI_DEBUG`
  and `DebugFeatures` for exactly this. Check first whether any diagnostic is
  deliberately DEBUG-only before moving it.

---

## Test infrastructure / 測試基礎設施

- **`SetForegroundWindow` is now requested on the mouse path but never
  verified.** (Windows) In `Win32Synthesiser.prepareForReplay` the call was
  moved above the keyboard guard, while the read-back loop that confirms it
  stayed below:

      SetForegroundWindow(window); BringWindowToTop(window)
      guard actions.contains(where: \.needsKeyboardFocus) else { return }
      ... 500 ms loop comparing GetForegroundWindow() == window ...

  So a mouse-only action file asks for the foreground and returns without ever
  learning whether it got it. **Request and verification were a pair**, and #46
  is the record of what the unpaired form costs: the synthesiser drove the wrong
  application because `SetForegroundWindow` was unchecked.

  Not yet observed failing, and the reason is worth stating so nobody upgrades
  this by accident: `SetWindowPos(HWND_TOPMOST)` still runs first, so clicks
  land on the intended window whether or not the foreground switch took. That
  makes this a latent hazard rather than a live bug — the failure would appear
  only where focus matters, and would look like the application ignoring input.

  **Decide between two shapes, do not leave the third.** Either move the
  read-back above the guard and let a mouse file *warn* while a keyboard file
  throws — focus is required for one and merely nice for the other — or drop the
  request from the mouse path and let TOPMOST do the work alone. What should not
  survive is asking for something and not looking.

  While there, two comments went stale in the same move: the `AttachThreadInput`
  note says "attaching to the foreground thread **before this call**" while the
  call it means is now above the guard and separated from it by the whole
  comment; and the deleted `SM_XVIRTUALSCREEN` block took with it the measured
  reason it existed — using the primary monitor instead of the virtual desktop
  put every click on the wrong screen. `SetCursorPos` takes physical coordinates
  so multi-monitor still works, but that lesson is now recorded nowhere.

  **`SetForegroundWindow` 現在會在滑鼠路徑上被請求，卻從不驗證。**（Windows）在
  `Win32Synthesiser.prepareForReplay` 中，該呼叫被移到鍵盤 guard 之上，而確認它是否生效的
  讀回迴圈仍留在下方（見上方程式碼）。因此純滑鼠的動作檔會要求前景，然後直接返回，從未得知
  自己是否取得。**請求與驗證原本是成對的**，而 #46 正是「拆開之後的代價」的紀錄：合成器驅動了
  錯誤的應用程式，原因就是 `SetForegroundWindow` 未經檢查。

  目前尚未觀察到它失敗，而理由值得寫明，以免有人誤把它當成已修好：`SetWindowPos(HWND_TOPMOST)`
  仍在其之前執行，因此無論前景切換是否成功，點擊都會落在預期的視窗上。這使它成為潛在風險而非
  現行缺陷——失敗只會出現在「焦點真正重要」之處，而且看起來會像是應用程式忽略了輸入。

  **在兩種形狀之間選一個，不要留下第三種。** 要嘛把讀回迴圈移到 guard 之上，讓滑鼠檔**警告**、
  鍵盤檔拋出——焦點對後者是必要條件，對前者只是加分；要嘛把該請求從滑鼠路徑移除，單靠 TOPMOST
  完成工作。唯一不該存活的，是「要求了某件事，卻不去看它有沒有發生」。

  順帶，同一次移動讓兩段註解過時：`AttachThreadInput` 那段寫著「在**此呼叫**之前附加至前景
  執行緒」，而它所指的呼叫如今在 guard 之上、且被整段註解隔開；另外被刪除的 `SM_XVIRTUALSCREEN`
  區塊，也一併帶走了它存在的實測理由——使用主螢幕而非虛擬桌面，會讓視窗不在其上時每一次點擊都
  落在錯誤的螢幕。`SetCursorPos` 採實體座標，多螢幕仍然正確，但那個教訓現在沒有任何地方記著。

- **Make GTK 4 render with hardware on WSL. It does not today, and the fallback
  is silent.** (WSL) GTK reports `GskVulkanRenderer`, which reads like hardware,
  while lavapipe draws every frame on the CPU. Measured 2026-08-29:

      libEGL warning: MESA-LOADER: failed to retrieve device information
      MESA: error: ZINK: failed to choose pdev
      Not using GL: renderer is llvmpipe
      Using renderer 'GskVulkanRenderer' for surface 'GdkWaylandToplevel'

  **Two absences, not a misconfiguration.** Eight Vulkan ICD manifests are
  installed and every one is for hardware that is not present, leaving `lvp`
  (lavapipe, software) as the only one that can answer. `dzn` — Mesa's
  Vulkan-on-D3D12 driver, the only one that could reach a GPU through
  `/dev/dxg` — is not built into Ubuntu's `mesa-vulkan-drivers` at all, so
  `libvulkan_dzn.so` does not exist. Separately, `/usr/lib/wsl/lib` holds CUDA,
  NVENC/NVDEC and OptiX and **no GL or Vulkan userspace whatsoever**. Full entry
  in `bugs/Gtk4-bugs.md` §2; detect with `zsh testapp/diagnose_wsl_gpu.zsh`.

  Everything reachable without installing anything was tried and none of it
  helped: `GALLIUM_DRIVER=d3d12`, `MESA_LOADER_DRIVER_OVERRIDE=d3d12`, explicit
  `LD_LIBRARY_PATH=/usr/lib/wsl/lib`. `/dev/dxg` exists, `/dev/dri` does not.
  The rest of the plumbing is intact — `libdxcore.so` and `libd3d12core.so` are
  in the loader cache, `d3d12_dri.so` is installed — so this is a missing
  userspace driver, not missing hardware.

  **Two routes, neither a code change**: a Windows NVIDIA driver that publishes
  GL/Vulkan userspace into WSL, or a Mesa built with `dzn`. Try the driver
  first; it is the cheaper of the two and the more likely to be maintained.

  **What it costs while unfixed.** UI tests stay valid — the pixels are correct,
  they were simply drawn by the CPU. Anything measuring GPU presentation, frame
  time or renderer performance on WSL is measuring lavapipe. In particular
  **"Vulkan is the hardware path, so it must be faster than Cairo" is false
  here**: both run on the CPU, and lavapipe additionally emulates a whole GPU
  pipeline on top. Any Cairo-versus-Vulkan comparison run on WSL today measures
  two software rasterisers, one of which is carrying an emulated GPU.

  **讓 GTK 4 在 WSL 上以硬體繪製。目前並非如此，而且退回是無聲的。**（WSL）GTK 回報
  `GskVulkanRenderer`，讀起來像硬體，實際上每一格都由 CPU 上的 lavapipe 繪製。

  **這是兩項「缺席」，不是設定錯誤。** 已安裝八個 Vulkan ICD manifest，而每一個都對應到不存在
  的硬體，只剩 `lvp`（lavapipe，軟體）能回應。`dzn`——Mesa 的 Vulkan-on-D3D12 驅動，也是唯一
  能透過 `/dev/dxg` 觸及 GPU 的那個——根本未被 Ubuntu 的 `mesa-vulkan-drivers` 編入，因此
  `libvulkan_dzn.so` 並不存在。另一方面，`/usr/lib/wsl/lib` 內有 CUDA、NVENC/NVDEC 與 OptiX，
  **完全沒有任何 GL 或 Vulkan userspace**。完整條目見 `bugs/Gtk4-bugs.md` §2；偵測方式為
  `zsh testapp/diagnose_wsl_gpu.zsh`。

  所有「不必安裝任何東西」的途徑都試過且全部無效：`GALLIUM_DRIVER=d3d12`、
  `MESA_LOADER_DRIVER_OVERRIDE=d3d12`、顯式 `LD_LIBRARY_PATH=/usr/lib/wsl/lib`。`/dev/dxg`
  存在，`/dev/dri` 不存在。其餘管線都是完整的——`libdxcore.so` 與 `libd3d12core.so` 位於
  loader cache，`d3d12_dri.so` 也已安裝——因此這是**缺少 userspace 驅動，而非缺少硬體**。

  **兩條路，皆非程式碼變更**：換一份會把 GL/Vulkan userspace 發布進 WSL 的 Windows NVIDIA
  驅動，或換一份編入 `dzn` 的 Mesa。先試驅動——那是兩者中較便宜、也較可能持續被維護的一條。

  **未修好期間的代價。** UI 測試仍然有效——像素是正確的，只是由 CPU 畫的。但任何在 WSL 上量測
  GPU 呈現、frame time 或繪製器效能的工作，量到的都是 lavapipe。尤其**「Vulkan 是硬體路徑，
  所以一定比 Cairo 快」在此為假**：兩者都跑在 CPU 上，而 lavapipe 還額外在其上模擬了一整條
  GPU pipeline。今天在 WSL 上做的任何 Cairo 對 Vulkan 比較，量的都是兩個軟體光柵化器，
  其中一個還背著一顆模擬的 GPU。

- ~~**Keyboard action files cannot run on Windows at all.** `prepareForReplay`
  refuses any file containing `key`/`keydown`/`keyup` [...] Options, in order:
  `PostMessage`; retry `AttachThreadInput` now that the window is pinned
  topmost; or make `run.zsh` say so up front.~~ **Already working — the
  description was stale in two ways.**

  `prepareForReplay` does not refuse such a file. It attempts the foreground
  and throws only if the window has not become foreground within 500 ms, and
  here it does become foreground. What fixed it is the
  `SetWindowPos(HWND_TOPMOST)` pin, which landed *after* this was written.

  Measured 2026-08-27, with the control run rather than by reading the code.
  `AttachThreadInput` was implemented as the task suggested and made no
  difference: P10 driven by a new `P10-ctrl-q.csv` quit with it and quit
  without it, so it was taken back out and the finding recorded in
  `Win32Synthesiser` beside the call.

  The real gap was that **no Windows keyboard action file existed** — the
  capability was there and untested, and believed broken. `P10-ctrl-q.csv` now
  exercises it, and the instrument is the process rather than a screenshot:
  P10 quits on Ctrl-Q, so success is the process being gone. P21's tab
  traversal and the text-entry checks are still unwritten.
- **`ui-lock.zsh`'s locked-desktop gate reads `LogonUI.exe`**, which does not
  track lock state — it has been seen running while input was being delivered.
  The direct signal is `SendInput` failing with `ERROR_ACCESS_DENIED` (5), which
  is the capability actually being gated. That would also be cheaper: `tasklist`
  costs ~195 ms and the gate runs it on every acquire. Seen again 2026-08-27:
  the workstation locked itself mid-session and a replay reported
  `SendInput exited with status 5`, with a desktop capture showing the PIN
  screen — so the proposed signal does fire, and it named the cause where a
  window capture did not. `screenshot.zsh -w` went on returning a correct
  picture of the window throughout, because BitBlt reads a window that is not
  on screen; only the desktop capture showed the lock.
- **P10 launches on Windows, registers a title, and shows no window.** Not
  diagnosed. Rule out a leftover GTK process and a locked workstation before
  forming any hypothesis — both produce exactly this appearance.
- **Refuted: `allowsHitTesting(false)` works on GtkBackend.** The task list
  carried "P10 expects `Hidden clicks: 0` and gets `1`". That has the direction
  backwards, and 1 is the working state.

  P10 puts an opaque `Color.orange.allowsHitTesting(false)` over a Button in a
  `ZStack`. The modifier means the orange layer does not take hits, so the click
  passes through to the button and the counter rises — which is what SwiftUI
  does, and what P10's own comment describes: "if the counter rises, the click
  reached a button nobody could see, which is the whole claim". If the modifier
  were ignored, the opaque layer on top would absorb the click and the counter
  would stay at 0.

  Measured 2026-08-27 with a control rather than by argument. `setHitTesting`
  was temporarily replaced with a no-op, P10 rebuilt and driven, and the counter
  read **0**; restored, it reads **1** again. So the modifier is causally
  responsible and the working value is 1. `gtk_widget_set_can_target` needs no
  change.
- **The same diagnostics defect is still in UIKitBackend and WinUIBackend.**
  `Sources/SwiftCrossUI/` and `Sources/GtkBackend/` were done 2026-08-27;
  UIKitBackend still has three `debugLogOnce` call sites and two bare
  `assertionFailure`s, and WinUIBackend has a `debugLogOnce`. Same fix, same two
  mechanisms: an unconditional `logger.warning` where the message is for the
  author, `DebugFeatures.isEnabled` where the check costs something per event.
- **`logger.warnOnce(...)` already exists** in `Sources/SwiftCrossUI/Logging.swift`
  — release-visible, keyed by source location, Mutex-guarded. Prefer it to a
  hand-rolled `Set` of already-warned values. The two style modifiers cannot use
  it as-is because they must key by *style* rather than by call site (one call
  site can be reached with several styles), which is worth fixing in the helper
  rather than working around twice.
- **A WinUI build cannot be tested through its own output, by construction.**
  `WinUIBackend.Console.attachToParentConsole()` calls `releaseConsole()` first,
  and that does `freopen_s(&fp, "NUL:", "w", stdout)` and the same for `stderr`
  before `FreeConsole()`; `redirectConsoleIO()` only runs if the following
  `AttachConsole(-1)` succeeds. So `./Pn.exe > log 2>&1` is **guaranteed** empty
  however much the app prints. Verified 2026-08-27 by driving all 25 apps: every
  WinUI build reported "no line" for its `-actionfile:` result while launching
  and running perfectly.

  What this costs is the class of tests where the app's own *words* are the
  instrument — the `-actionfile:` result line, P21's click counter, every `[Pn]`
  diagnostic.

  It does **not** cost the visual evidence, and the first reading of this run
  said it did. The desktop fallback capture turns out to photograph the WinUI
  window perfectly, because a freshly launched window is in front: P8's capture
  shows the rendered app *and* shows the outer list at rows 5-8 rather than 0,
  which is the scroll its action file performs. So the replay ran and had its
  effect while reporting "no line". On WinUI the picture is the instrument and
  the log is not.

  The caveat that remains is that a desktop capture photographs whatever is in
  front, so it is evidence only while nothing covers the window — which is why
  the sweep drives one app at a time.

  Worth fixing rather than working around, because it makes one of the two
  Windows backends untestable. The narrow version is to keep the caller's
  redirection when there is one: check whether stdout is already a file or pipe
  before reopening it on `NUL:`.
- **Not every Pn builds on every backend, and a sweep that assumes so reports a
  false regression.** P4 fails a `-gtk4` build with `missing required module
  'CWinRT'`, and that is by design: it is the WinUI escape-hatch app (#156,
  #204, #470) and imports `WinUI` behind `#if canImport(WinUIBackend)`. That
  condition is **true even in a `-gtk4` build** — the flag forces the default
  backend, it does not remove the target — so the import happens and the gtk4
  build tree has no swift-winui C module. Its WinUI build is fine. Measured
  2026-08-27, found by a sweep that built all 25 apps both ways. A sweep needs a
  per-app backend policy, not one flag for everything.
- **`BackendFeatures.Tables` exists in GtkBackend alone, and two apps abort on
  WinUI because of it.** Not WinUI, not AppKit, not UIKit. `@CastBackend`
  expands to a `fatalError`, so P23 and P26 — both of which use `Table` — die on
  launch under WinUIBackend. Measured 2026-08-27 across all 25 apps: 25 build,
  23 launch and stay up, those two exit inside 14 seconds. Running them *without*
  an action file is what ruled out the replay as the cause; they die either way.
  Implementing Tables in WinUIBackend would make two more apps testable there,
  and is the concrete price of the backend lag noted below.
- **`swift test` does not run on Windows at all.** `SCUI_HOST_BACKENDS_ONLY=1
  swift test` fails with `missing required modules: 'CGtk', 'GtkCHelpers'` while
  emitting `DefaultBackend` — so the flag that deletes the unbuildable targets
  does not stop `DefaultBackend` from importing GtkBackend. Measured
  2026-08-27, with and without `PKG_CONFIG_PATH=/c/gtk4/lib/pkgconfig`, and
  **verified pre-existing**: the same failure appears on a stashed, unmodified
  tree, so it is not a consequence of any change made that day. The suite does
  run on WSL, which is presumably why this went unnoticed — "55 tests in 10
  suites pass" was true there and untested here.
- **`testapp/run.zsh` documents an action-file path that does not work.** Its
  own example says `actions/win/...`; the app resolves against the repo root, so
  it must be `testapp/actions/win/...`. Consider making the script resolve the
  short form rather than only correcting the comment.

---

## SwiftUI parity / 與 SwiftUI 的落差

Nine areas from a protocol-and-platform audit. Each is a category, not a task:
animation and transitions (no protocol at all); visual effects and transforms;
focus, accessibility and keyboard shortcuts; style protocols (`ButtonStyle`,
`LabelStyle`, `ShapeStyle`); gestures beyond tap and hover; missing common views
(`Form`, `Section`, `Label`, `Stepper`, lazy containers); API shapes that do not
compile from SwiftUI code; state wrappers and scene composition; presentation
and container modifiers.

The API-shape one is worth doing first and is the least visible: the types exist
and only the initialisers differ, so the gap never shows on a feature checklist.

### API shapes: audited 2026-08-27, all ten claims still stand

Re-checked against the code rather than trusted, because several claims of this
kind in this project have gone stale (`.wheel` was skipped for a reason that was
wrong; `ToggleStyle` was reported absent when it had ten references). These did
not: every one is still true.

| # | claim | state |
|---|---|---|
| 1 | `Picker` has only `init(of:selection:)`, selection must be Optional, no label, no `.tag()` | still true |
| 2 | `Button` is label-String only; no `ButtonRole` anywhere | still true |
| 3 | `Text` is String only; no LocalizedStringKey, markdown, `+`, underline/strikethrough/kerning/textCase | still true |
| 4 | `Image` has no `systemName:` and no bundle asset init | still true |
| 5 | all six `List` inits require `selection:` and `Data.Index == Int`; no `Section`, `.onDelete`, `.onMove`, `.swipeActions`, `.listRow*` | still true |
| 6 | `Table` has no selection, sortOrder or column width | still true |
| 7 | `TextField` lacks `axis:`, `prompt:`, `value:format:`, `.textFieldStyle` | still true |
| 8 | `Slider` lacks label, step, onEditingChanged | still true |
| 9 | `GeometryProxy` has only `size` | still true |
| 10 | `padding`/`cornerRadius`/stack `spacing`/`Spacer(minLength:)` are Int while `frame` is Double | still true |

**Order to take them in.** 2 first — a `Button(action:label:)` plus a role that
backends may ignore. Not 9, and not 10; both look cheap and are not, which is
recorded below because "cheapest first" is exactly the judgement that gets made
from a list without reading the code.

**9 is not fields on a struct.** `frame(in:)` needs three things that do not
exist. There is no `CoordinateSpace` type anywhere — 0 hits across `Sources/`.
The proxy is built in `GeometryReader.computeLayout` from the **proposed size**,
before the view has been placed, so no position is available to make `.global`
mean anything; `.local` would be the only honest answer and a `frame(in:)` that
silently gives local coordinates for a global request is worse than not having
it. And `safeAreaInsets` has no route to the view layer: safe area exists only
inside AndroidBackend and UIKitBackend, which apply it to the window themselves
and never surface it. Doing 9 properly means a coordinate-space registry
resolved after placement, which is a design, not an addition.

**9 並非只是在 struct 上補欄位。** `frame(in:)` 需要三樣並不存在的東西。整個 `Sources/` 裡沒有任何
`CoordinateSpace` 型別——0 次命中。該 proxy 是在 `GeometryReader.computeLayout` 中，由**被提議的
尺寸**建立的，此時 view 尚未被放置，因此沒有任何位置資訊能讓 `.global` 具有意義；`.local` 會是唯一
誠實的答案，而一個「對 global 請求默默回傳 local 座標」的 `frame(in:)`，比沒有它更糟。至於
`safeAreaInsets`，它沒有通往 view 層的路徑：安全區域只存在於 AndroidBackend 與 UIKitBackend 之內，
由它們自行套用到視窗上，從未向外揭露。要把第 9 項做對，意味著一套「在放置之後才解析」的座標空間
註冊機制——那是一項設計，而非一項增補。

**10 is NOT the mechanical one it looks like, and that is worth stating before
someone starts it.** `frame` migrated cleanly because layout sizes are already
`Double` end to end and only round at the widget boundary through
`LayoutSystem.roundSize`. Padding does not have that property: `EdgeInsets` is a
**public struct whose four fields are `Int`**, and `padding` feeds them into the
layout as `Double(insets.leading + insets.trailing)`. So adding a `Double`
overload that rounds immediately would accept fractional padding and silently
discard it — the API would claim something it does not do, which is the exact
failure this project keeps cataloguing.

Real fractional padding means changing `EdgeInsets` to `Double`, which is a
source-breaking change to a public type, and letting the fraction survive until
`setPosition`/`setSize`, which take `SIMD2<Int>`. Feasible, and a different size
of job from adding an overload. The pattern to copy either way is
`FrameModifier`'s: `@available(*, deprecated, renamed:)` plus
`@_disfavoredOverload` on the Int version, forwarding to the Double one, which
also keeps a bare `.padding()` unambiguous.

### API 形狀：2026-08-27 稽核，十項主張全部仍然成立

此處是對照程式碼重新查證，而非直接採信——因為本專案這一類主張已經有數次過時（`.wheel` 當初被略過
的理由是錯的；`ToggleStyle` 曾被回報為不存在，實際上有十處引用）。這一批則沒有：每一項都仍然成立
（明細見上表）。

**處理順序。** 先做第 9 項：`GeometryProxy` 只需從 `GeometryReader` 補上欄位，完全不需要動 backend。
其次是第 2 項，需要 `Button(action:label:)` 與一個 backend 可忽略的 role。

**第 10 項並不是它看起來的那種機械式工作，這一點必須在有人動手之前講明。** `frame` 能乾淨遷移，是
因為版面尺寸本來就全程是 `Double`，只在 widget 邊界透過 `LayoutSystem.roundSize` 取整。padding 沒有
這個性質：`EdgeInsets` 是一個**四個欄位皆為 `Int` 的公開 struct**，而 `padding` 是以
`Double(insets.leading + insets.trailing)` 餵進版面。因此若加上一個「立即取整」的 `Double` 多載，
等於接受了小數 padding 再默默丟棄它——API 宣稱了它做不到的事，而那正是本專案一再編錄的失敗樣態。

真正的小數 padding 意味著把 `EdgeInsets` 改為 `Double`，那是對公開型別的破壞性變更，並讓小數一路
存活到接受 `SIMD2<Int>` 的 `setPosition`／`setSize` 為止。可行，但與「加一個多載」是不同量級的工作。
無論走哪條路，要照抄的樣板都是 `FrameModifier`：在 Int 版本加上
`@available(*, deprecated, renamed:)` 與 `@_disfavoredOverload` 並轉呼叫 Double 版本——這同時也讓
不帶引數的 `.padding()` 不致產生歧義。

Working order agreed 2026-08-27: protocol level first, then GtkBackend for
WSL/Windows here; AppKit, UIKit and Android are done on the Mac side. So each
item lands as a `BackendFeatures` protocol plus one implementation, and the
other backends follow separately.

### Compositing effects: done 2026-08-27 (opacity, blur, colour adjustment)

`BackendFeatures.VisualEffects` plus `VisualEffect`, and the seven modifiers
SwiftUI names: `.opacity`, `.blur(radius:)`, `.saturation`, `.brightness`,
`.contrast`, `.grayscale`, `.hueRotation`. P39 is the app.

**One value, not one method per effect.** Every backend has to turn the
combination into a single thing -- GTK into one CSS `filter`, AppKit into one
`CIFilter` chain -- so recombining them per backend would be the same work done
six times. Composition comes from nesting containers, which is why
`.opacity(0.5).opacity(0.5)` is 0.25 without anything multiplying it.

**GtkBackend does all seven**, verified against an identity control in the same
window. Opacity goes through `gtk_widget_set_opacity` rather than CSS `opacity`,
because the widget property composites the subtree as a group the way SwiftUI
does, while the CSS property is inherited per child and lets two overlapping
half-transparent children show through each other.

**WinUIBackend does opacity only, and says so**, via `logger.warning` naming the
fields it dropped. Conforming with a partial implementation was deliberate:
`@CastBackend` turns a *missing* conformance into `fatalError`, so declining
would abort every app calling `.opacity(_:)` on the default Windows backend
rather than render it un-blurred. The rest needs a `Microsoft.UI.Composition`
effect graph.

`.border(_:width:)` and `.hidden()` are done too, 2026-08-27, and needed **no
backend protocol at all**. A border is an overlaid stroked `Rectangle`, inset by
half the stroke width so the line falls inside the bounds rather than half
outside where a clipping ancestor would eat it; `.hidden()` is
`.opacity(0).allowsHitTesting(false)`, the second half being the one that is
easy to forget — an invisible view that still swallows clicks is worse than
either a visible or an absent one. Adding a protocol for either would have given
six backends a method to implement for something they can all already express.

Still open in this area, all still with no protocol: `.shadow` (needs a `Shadow`
value type), `.blendMode`, `.position` and `.zIndex`. Also absent:
`.clipShape`, `.mask`, `.compositingGroup`, `.drawingGroup`.

### Geometric effects: done 2026-08-27, and GTK cannot render them

`BackendFeatures.GeometricEffects` plus `GeometricEffect`, and `.offset(x:y:)`,
`.rotationEffect(_:anchor:)`, `.scaleEffect(_:anchor:)` and
`.transformEffect(_:)`. P40 is the app. Separate from `VisualEffects` because
these change *where* pixels land rather than what they look like, which also
means they affect hit testing; a backend can support one family and not the
other, and GTK is exactly that case.

The anchor is resolved into an `AffineTransform` at commit time, where the
view's size is known, so a backend receives one matrix about the widget's origin
and never has to reproduce SwiftUI's anchor arithmetic.

**WinUIBackend renders them correctly** -- rotation, scale and offset all
verified in P40.

**GtkBackend conforms and deliberately declines.** GTK 4 renders a transformed
widget as a flat rectangle of hotpink, `rgb(255, 105, 180)`, losing its content
completely; that is GSK's documented indicator for a render node it cannot
handle. Four things were ruled out before blaming the platform: the mechanism
(CSS `transform` and `gtk_fixed_set_child_transform` fail identically despite
being unrelated paths), the renderer (`GSK_RENDERER=cairo` and the GL renderer
agree), this backend's own code (a no-op control that built the container and
skipped only the transform call rendered every tile perfectly), and the content
(a bare `Text` goes hotpink too). Upgrading is not available: this is 4.22.4,
the current stable, and Windows and WSL are on the same version.

Declining beats applying it here. An untransformed view is legible and
clickable; a hotpink rectangle has lost everything. This is the one case so far
where "apply what you can and say so" loses to "apply nothing and say so".

Untested: whether Linux GTK behaves the same. Same version, so probably, but
nobody has run it -- the WSL box has no screenshot tool installed and the WSLg
window was not reachable from the Windows capture path.

---

## Needs another machine / 需要另一台機器

- **AppKitBackend and UIKitBackend conformances written but never compiled.**
  Clipping, DragAndDrop, WindowLevels and HitTesting were added against
  documented APIs on a Windows host. Review-ready, not verified.
  HitTesting has now been run on a Mac and does not work -- see below.
- **GtkBackend's font weight table collapses nine weights into about five.**
  Instrumented here and deliberately left unfixed, 2026-08-27. P22 gained a
  nine-row weight ladder and `actions/win/P22-weights.csv`; measured on
  Windows/GtkBackend, `light`/`regular` render byte-identically and so do
  `semibold`/`bold`/`heavy`. Numbers and the full argument are in finding 5 of
  `testapp/gtk-silent-noops.md`.

  It needs a Mac because every available fix moves a weight the source comment
  says was set by measuring against AppKit, and that measurement cannot be
  redone here. The ladder runs 200...900 -- eight hundred-steps for nine weights
  -- so some pair must collide unless the range extends to 1000 or the
  deliberate +100 shift is dropped. Note the catalogue's own suggested one-line
  fix, `case .semibold: 600`, is wrong: `.medium` is already 600, so it moves
  the collision rather than removing it.

### AppKit hit testing: still not working on the Mac as of 2026-09-01

**The 2026-08-27 entry below records this as fixed. It is not, on this machine.**
Re-measured 2026-09-01 with `e25b3a65` confirmed in the tree by
`git merge-base --is-ancestor` and with binaries built the same morning:

- P21, a plain button with no overlay: an action file clicking `59,206` with
  `origin=frame` -- the button's own centre, read off a window capture where the
  button spans x 26-90, y 196-216 -- replays cleanly and leaves
  `Button — clicks: 0`. Every toggle on that window is also unchanged.
- P28: same result, `p28-debug-events.log` has "clicked" zero times. Its shipped
  action file additionally has stale coordinates -- it clicks `168,151` which is
  above the blue overlay in a 680x448 window -- but correcting them to the
  overlay's centre `250,239` still leaves the counter at 0, so the coordinates
  were not what was stopping it.
- P26's tab click is the exception and still works: one artifact in a cache that
  an unclicked tab leaves empty.

Tab strip reachable, ordinary controls not -- the same split the probe table
below found. Whatever `e25b3a65` fixed, this path is not it.

**2026-08-27：以下記錄此問題已修復。在這台機器上並非如此。** 於 2026-09-01 重新量測，`e25b3a65`
已由 `git merge-base --is-ancestor` 確認在樹中，執行檔亦為當日上午建置：

- P21（純按鈕、無 overlay）：動作檔以 `origin=frame` 點擊 `59,206`——即該按鈕自身的中心，取自視窗
  擷取（按鈕範圍 x 26-90、y 196-216）——重放完整結束，而 `Button — clicks: 0`。該視窗上所有 toggle
  亦未改變。
- P28：結果相同，`p28-debug-events.log` 中「clicked」出現 0 次。其既有動作檔另有座標過期的問題
  ——它點的是 `168,151`，在 680x448 的視窗中位於藍色 overlay 上方——但改為 overlay 中心 `250,239`
  後計數器仍為 0，可見阻擋它的並非座標。
- P26 的分頁點擊是例外，且仍然有效：未被點擊的分頁會使快取為空，而該處抓到了 1 個 artifact。

分頁列可觸及、一般控制項不可——與下方探測表所發現的分界相同。無論 `e25b3a65` 修好了什麼，都不是
這條路徑。

### AppKit hit testing: ~~nothing but text fields can be clicked~~ — reported FIXED on 2026-08-27

**Fixed 2026-08-27 by `e25b3a65 Fix AppKit hit testing and Swift 6 replay
build`, on the Mac.** Not verified here and not verifiable here -- there is no
macOS in this checkout's reach -- so this is recorded as reported by that side,
not as something this session measured.

The cause was two frame-of-reference errors at once, which is why fixing either
alone made it fail differently rather than work: `point` arrives already in the
container's own coordinate space, and each child needs it in the child's space,
so exactly one conversion is needed and it belongs inside the child loop. The
old code converted from the superview and then handed every child a
container-space point.

The investigation below is kept because it is what made the fix findable: the
per-control probe table is the thing that separated "the container is wrong"
from "the coordinates are wrong", and the arithmetic worked through for the
button is what identified the second error rather than only the first.

Measured on macOS 2026-08-27, after `882b43f8 Implement AppKit hit testing and
add P28 coverage`. Handed over rather than fixed; the Mac side stopped here.

`AppKitHitTestingContainer.hitTest` returns nil for almost everything. Probed
directly on a live window, points at the exact centre of each control:

| window point | control there | hitTest |
|---|---|---|
| (140, 225) | NSButton "TOP" (114, 212, 52, 27) | nil |
| (140, 195) | NSButton "BOTTOM" (99, 182, 82, 27) | nil |
| (140, 165) | text field (40, 155, 200, 21) | NSTextView |
| (140, 105) | NSScrollView (117, 65, 46, 80) | nil |

Confirmed with the project's own test, not only a scratch app:
`test.zsh P28 --macos --actionfile` replays
`testapp/actions/mac/P28-hit-testing.csv`, whose single click is the one P28
exists to check, and `p28-debug-events.log` contains "clicked" zero times.

The coordinates are not the problem, which was checked before blaming the
container. The full chain measured on the same window: screen 1920x1080 at
backing 2.0, geometry frameOrigin (820, 193) and clientOrigin (820, 221) at
scale 1, client (140, 105) resolving to screenPosition (960, 326) -- 820+140 and
221+105 -- and then to windowPoint (140.0, 195.0), which is exactly right. The
click lands where the file says and there is nothing there to receive it.

Text still arrives, and that is the trap: key events go to the first responder
without a hit test, so a file that clicks a field and types reports a partial
success and looks like a coordinate problem.

One fix was tried and is not the answer. `child.hitTest(childPoint)` looks wrong
against Apple's contract -- `hitTest(_:)` takes a point in the receiver's
*superview* coordinates, and childPoint has been converted into the child's own
space -- but passing `point` instead makes it worse: the text field stops
hit-testing too. So the container is self-consistent with a non-standard
convention and breaks where it meets real AppKit views. The reverted experiment
is recorded so nobody spends the same hour on it.

**A fix is written and needs one command on a Mac to confirm or kill it.**
`9623ad6` on the Windows side. There were two frame-of-reference errors at once,
which is why the reverted experiment failed differently rather than worked:
`hitTest(_:)` takes its point in the receiver's *superview* space, so
`convert(point, to: child)` started from the wrong space, and
`child.hitTest(childPoint)` then passed a point in the child's own space where
the child's superview space was wanted. Passing `point` corrects the second and
leaves the first, so it is right only while the container sits at its
superview's origin.

The numbers in the table above are what make it a diagnosis. Button frame
(114, 212, 52, 27), point (140, 225): `childPoint` is (26, 13), genuinely inside
the button's bounds — so the containment check passed and hid the problem —
and then `button.hitTest((26, 13))` compared (26, 13) against x 114...166,
y 212...239 and correctly said nil.

Unverified from here: this is a Windows host and AppKitBackend does not compile
on it. The prediction is specific — `test.zsh P28 --macos --actionfile` should
put "clicked" into `p28-debug-events.log`, where it currently appears zero
times. If it does not, the remaining suspect is the flippedness of the
container relative to its children, which the measurements above cannot rule
out.

- **Benchmark Metal's feature set on macOS**, then implement the useful subset
  on GtkBackend through GSK render nodes and GLSL rather than Metal shaders.
  Two things to settle first: which parts are reachable from GSK's public API at
  all, and whether the numbers justify a GPU path at UI sizes.
- **`#27` above needs a real GNOME desktop**, for the reason given there.

---

## Needs a decision / 需要決定

- **WebKitGTK as a system dependency.** A real `WebView` on Linux and Windows
  needs `webkitgtk-6.0` in `Package.swift`, which changes the build requirements
  for everyone. The placeholder is in place until this is answered.
Only one open decision, then. The AppKit `HitTesting` item that was here has
already been answered: it was implemented on the Mac side, in
`AppKitBackend+HitTesting.swift`, with a container subclass and a weak
`NSHashTable` registry — and it corrects the design that was recorded here, which
had the container return `nil` after `super.hitTest`. That stops AppKit
searching, so a disabled overlay would swallow the click rather than pass it
through; the shipped version walks its own subviews front to back instead.

只剩一項待決。原本列於此處的 AppKit `HitTesting` 已有答案：它已在 Mac 端以
`AppKitBackend+HitTesting.swift` 實作完成，採用 container 子類別搭配弱引用的 `NSHashTable` 登錄表
——而且它修正了先前記錄於此的設計，該設計讓 container 在 `super.hitTest` 之後回傳 `nil`。那會使
AppKit 停止搜尋，於是被停用的 overlay 會吞掉點擊而非讓它穿透；實際落地的版本改為自行由前到後
走訪自己的 subviews。
