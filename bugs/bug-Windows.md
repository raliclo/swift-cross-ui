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

**Not yet verified:** a full test app (P81/P113 opening a second `Window`, P114
Back) built with the fiber on WinUIBackend and GtkBackend.

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

**尚未驗證：** 以 fiber 建置的完整測試 app(P81/P113 開第二個 `Window`、P114 Back)，
WinUIBackend 與 GtkBackend 皆未跑過。
