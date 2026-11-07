# Windows — platform behaviour that broke this project

Measured on Windows 11 unless a line says otherwise. The subject is the platform
and its defaults, not this repository; toolchain defects go in `bug-MSVC.md`.

本檔的主詞是 Windows 平台與其預設值，不是本 repository；工具鏈的缺陷歸 `bug-MSVC.md`。

---

## 1. The main thread has a 1 MB stack, and deep layouts overflow it

**Measured 2026-11-07.** SoftPCB-UI (a downstream app, debug build, GTK 4.24.1,
Swift 6.4.2) crashed on its deepest tab with `Program crashed: Stack overflow`.
The backtrace had 626 frames, about 615 of them SwiftCrossUI layout repeating
(VStack → PaddingModifierView → TupleView → EitherView → AnyViewGraphNode →
ViewGraphNode …) down to `g_application_run`. The depth was finite: layout
recurses once per view level. The WinUI build of the same app died the same way
with `c00000fd` and no backtrace, which had been reported as WinUIBackend
overflows on nested TabView / NavigationSplitView and on `openWindow` of a second
`Window` scene. Those were very likely this, not backend defects.

The cause is the linker's default reserve. Check any executable with:

```sh
llvm-readobj --file-headers testapp/output/P41-gtk4.exe | grep SizeOfStackReserve
```

It read `1048576` on P41-gtk4.exe and P81-WinUI.exe. macOS gives the main thread
8 MB, so the same view tree fits there.

**Fix: `Sources/SwiftCrossUI/Utility/WindowsMainStack.swift`.** `App.main()` runs
the app on a fiber with an 8 MB stack. A fiber runs on the same thread, so
`Thread.isMainThread`, `MainActor` and the main dispatch queue are unchanged.
Apps need no linker flag; an executable already linked with 8 MB or more skips
the fiber. Verified 2026-11-07 with a standalone harness compiled with that file
(Swift 6.4.2, `-swift-version 6`): the stack inside read 8388608, a recursion
needing about 4.8 MB completed, and control returned to the original stack. A
standalone probe also showed a `DispatchQueue.main` block and a `@MainActor`
task both running on the fiber.

The alternative, `-Xlinker -STACK:8388608` on each executable, also works (SoftPCB-UI
used it and the user clicked through the tab that crashed), but it has to be
repeated by every app, and SwiftPM refuses `unsafeFlags` from a dependency that is
pinned by version, so swift-cross-ui cannot carry it for them. Spell it with a dash:
from Git Bash a leading `/STACK` is rewritten into a path.

`testapp/compile.zsh` deliberately passes no `-STACK` (decided 2026-11-07): the test apps
must keep the 1 MB header so they exercise the fiber, the path every downstream app takes.
If either fiber call fails, `WindowsMainStack` logs a warning with `GetLastError()` before
running on the smaller stack, so a later overflow is not silent.

**Not yet verified:** a full test app (P81/P113 opening a second `Window`, P114
Back) built with the fiber on WinUIBackend and GtkBackend.
*(Superseded the same day by the results below; kept as written.)*

**Verified 2026-11-07, the fiber alone fixes it.** The user clicked the screens in a
visible window and confirmed it to this session; two SofPCB-W11 sessions reported the
same (a third of that name did not run it). SoftPCB-UI's GTK debug build against 34ffb42b with its
`-STACK` removed (SizeOfStackReserve 1048576 on both exes, rebuilt 15:41): tab 8 (the
deepest tree), tab 9 and the field matrix were clicked, and none crashed. Before
the fiber, the same screens overflowed. P81-WinUI.exe (1 MB header) also opened its
second `Window` through `openWindow` without a crash; P81 is shallow, so that one is a
regression check only. The earlier WinUI cases (nested NavigationSplitView/TabView,
LLMTab's table) were not rerun on WinUI: SoftPCB-UI no longer builds a WinUI variant.

Seen in the same run, not yet investigated, possibly unrelated to the stack: tab 8 prints
`Gtk-CRITICAL: Allocation height too small ... GtkPassthroughFixed needs at least 1180x847`
for an 844-high allocation every ~85 ms, and the field matrix is slow.
*(The allocation warning was fixed the same day, and it was not about the stack:
the content's minimum (from SoftPCB-M4's view tree, a nested TabView whose rows
are fixed-height above a minHeight-150 ScrollView) exceeded the window, and
CustomRootWidget allocated the root only the window size. A temporary GTK repro
printed 622 warnings in 8 s before the fix and 0 after; see
Sources/GtkCHelpers/gtk_custom_root_widget.c. The field matrix is still open.)*
*(Field matrix, 2026-11-07: SoftPCB-W11 timed load() at ~35 ms against ~2.3 s from
appear to the first main-queue hop at -O, so the time is SwiftCrossUI layout. A
one-page repro (60 cells, ~170 Text) made 2354 Text.computeLayout calls, ~450 ms of
them in Pango measurement. GtkBackend now caches a label's measurement under a key
of everything it reads; the page went from ~0.91 s to ~0.63 s (ASCII) and ~0.75 s to
~0.65 s (CJK). A check that re-measured on every cache hit found 0 mismatches in
~30,000 hits across P9, P10, P22, P23, P52, P103 and the repro. CJK and symbol text
did not reproduce the Pango-CRITICAL.)*

## 1. 主執行緒只有 1 MB 堆疊，深層 layout 會用完它

**2026-11-07 實測。** 下游 app SoftPCB-UI(debug 建置、GTK 4.24.1、Swift 6.4.2)在最深的分頁
以 `Program crashed: Stack overflow` 終止。backtrace 共 626 個 frame，約 615 個是 SwiftCrossUI
layout 的重複遞迴，一路到 `g_application_run`。深度是有限的：layout 每一層 view 遞迴一次。同一個
app 的 WinUI 版以 `c00000fd` 同樣終止且沒有 backtrace，先前被回報為 WinUIBackend 在巢狀
TabView／NavigationSplitView、以及 `openWindow` 開第二個 `Window` 場景時溢位。那些很可能都是
這個原因，不是 backend 的缺陷。

原因是連結器預設的保留大小。P41-gtk4.exe 與 P81-WinUI.exe 都讀到 `1048576`；macOS 的主執行緒
有 8 MB，所以同一棵 view 樹在那裡放得下。

**修正：`Sources/SwiftCrossUI/Utility/WindowsMainStack.swift`。** `App.main()` 讓 app 在一個
8 MB 堆疊的 fiber 上執行。fiber 跑在同一條執行緒上，`Thread.isMainThread`、`MainActor` 與 main
dispatch queue 都不變。app 不需要任何連結旗標；已用 8 MB 以上連結的執行檔會略過 fiber。
2026-11-07 以獨立測試程式驗證(Swift 6.4.2、`-swift-version 6`)：內部堆疊讀到 8388608，需要約
4.8 MB 的遞迴順利完成，並回到原本的堆疊；另一支探測程式顯示 `DispatchQueue.main` 與
`@MainActor` task 都在 fiber 上執行。

替代做法是每個執行檔加 `-Xlinker -STACK:8388608`(SoftPCB-UI 用了它，使用者點過原本會崩潰的
分頁)，但每個 app 都得自己加，而 SwiftPM 不允許以版本釘住的依賴帶 `unsafeFlags`，所以
swift-cross-ui 無法替它們帶上。要寫成 `-STACK`：從 Git Bash 執行時，開頭的 `/STACK` 會被改寫成路徑。

`testapp/compile.zsh` 刻意不加 `-STACK`(2026-11-07 決定)：測試 app 必須保留 1 MB 的標頭，才會走到
fiber 這條路徑，也就是每個下游 app 走的路徑。任一個 fiber 呼叫失敗時，`WindowsMainStack` 會先連同
`GetLastError()` 記錄警告，再在較小的堆疊上執行，所以之後的溢位不會是無聲的。

**尚未驗證：** 以 fiber 建置的完整測試 app(P81/P113 開第二個 `Window`、P114 Back)，
WinUIBackend 與 GtkBackend 皆未跑過。
*(當天即被下方結果取代；原文保留。)*

**2026-11-07 驗證：單靠 fiber 就修好了。** 使用者在看得見的視窗中親手點過這些畫面，並向本 session
確認；兩個 SofPCB-W11 session 也回報了同樣結果(第三個同名 session 沒有執行它)。SoftPCB-UI 的 GTK debug
建置(對 34ffb42b，移除 `-STACK`，兩個執行檔的 SizeOfStackReserve 都是 1048576，15:41 重建)：
tab 8(最深的樹)、tab 9 與場矩陣都點過，都沒有崩潰；在 fiber 之前，這些畫面會溢位。P81-WinUI.exe(1 MB 標頭)也透過 `openWindow`
開出第二個 `Window` 而沒有崩潰；P81 很淺，所以那只算回歸檢查。先前 WinUI 的案例(巢狀
NavigationSplitView／TabView、LLMTab 的表格)沒有在 WinUI 上重跑：SoftPCB-UI 已不再建置 WinUI 版。

同一次執行中看到、尚未調查、可能與堆疊無關：tab 8 開著時每約 85 ms 印出
`Gtk-CRITICAL: Allocation height too small ... GtkPassthroughFixed needs at least 1180x847`
(配置的高度是 844)，而場矩陣很慢。
*(配置警告當天已修正，而且與堆疊無關：內容的最小高度(依 SoftPCB-M4 提供的 view 樹：巢狀 TabView,上方各列固定
高度，最下方是 minHeight 150 的 ScrollView)超過視窗，而 CustomRootWidget 只把視窗大小配置給根容器。暫時的 GTK 重現
程式在修正前 8 秒印出 622 則警告，修正後為 0;見 Sources/GtkCHelpers/gtk_custom_root_widget.c。場矩陣仍待查。)*
*(場矩陣,2026-11-07:SoftPCB-W11 在 -O 下量到 load() 約 35 毫秒，而從出現到第一次主佇列 hop 約 2.3 秒，所以時間花在
SwiftCrossUI 的排版。一頁的重現程式(60 格、約 170 個 Text)呼叫了 2354 次 Text.computeLayout,其中約 450 毫秒在 Pango
量測。GtkBackend 現在以「量測所讀取的一切」為鍵快取 label 的量測結果；該頁從約 0.91 秒降到約 0.63 秒(英文)、約 0.75 秒降
到約 0.65 秒(中文)。在每次命中都重新量測比對的檢查中,P9、P10、P22、P23、P52、P103 與重現程式共約 30,000 次命中，
不一致為 0。中文與符號文字沒有重現那個 Pango-CRITICAL。)*
