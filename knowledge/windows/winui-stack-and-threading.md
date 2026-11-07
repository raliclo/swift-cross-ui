# WinUIBackend: the stack, the STA start, and the main queue

Written 2026-10-24 from Package.swift, Package.resolved,
Sources/WinUIBackend/WinUIApplication+SingleThreaded.swift, Console.swift,
commits fd3378f1, e9b80e8e, f191f46c, and results.csv2 (windows, winui: P38
2026-09-17, P66 2026-10-19).

## Stack

- WinUI comes through **moreSwift/swift-winui 0.2.1** (Package.resolved). Its
  checkout pins **Microsoft.WindowsAppSDK 1.5.240205001-preview1**,
  TheBrowserCompany.SwiftWinRT 0.5.0 and Win2D 1.1.1.
- Because the WinAppSDK is a preview, Microsoft.UI.Xaml.dll prints BVI-* /
  rcBackdropLocal lines to stdout; `Console.swift` filters them ("remove once on
  a stable WindowsAppSDK", #204, open).
- WinUIBackend links d3d11 and dxgi; WinUIInterop (C++) links d2d1, dwrite,
  windowscodecs, d3d11 and dxgi.
- **Since 2026-11-06 the first two points above are out of date (kept as written).**
  swift-winui is now the submodule `Vendor/swift-winui` (fork raliclo/swift-winui,
  develop), referenced with `.package(path:)`. The bindings were regenerated with
  swift-winrt 0.6.0 for **Windows App SDK 2.6.5**
  (`Vendor/swift-winui/Support/generate-bindings.zsh`). 0.6.0 dropped
  `RoActivateInstance`; the backend's own copy is
  `Sources/WinUIBackend/WinRTActivation.swift`, and static methods now `throw`.
  The WinAppSDK is no longer a preview, but whether `Console.swift`'s filter is
  still needed on 2.6.5 has not been checked. *(Checked 2026-11-07: with the
  filter bypassed, P81-WinUI and P41-WinUI wrote 0 BVI-*/rcBackdropLocal= lines;
  see todo.md item 6.)* Running needs Windows App Runtime
  2.6; a stale `swift-winui_CWinAppSDK.resources` left in `testapp/output` is
  loaded before `.bundle`, and the app then reports that it needs Runtime 2.6.
- WebView2 on 2.6.5 needs `Microsoft.Web.WebView2.Core.dll` beside the exe:
  the 1.5 framework package carried it, 2.6.5's does not. swift-winui 08b5f91
  ships it as a CWinAppSDK resource and compile.zsh copies it out. Without it
  the page stays empty and nothing reports an error (P38, 2026-11-06).

## The application starts single-threaded (STA)

swift-winui starts the app in an MTA. Under MTA, WebView2's
`EnsureCoreWebView2Async` never completes, and the shell `IFileDialog`s need an
STA too. `WinUIApplication.runSingleThreaded()` starts it with
`WindowsAppRuntimeInitializer(threadingModel: .single)` and **a copy of
swift-winui's internal run-loop tickler** (fd3378f1, 2026-09-17).
`SCUI_WINUI_MTA=1` takes the old path as a control.

Risk: an update of swift-winui can change its tickler while the copy stays as
it was. A broken tickler silently stops `DispatchQueue.main` and main-actor
work; RENDER COMPLETE markers, not window sizes, show it.

## The main queue is drained by a wait, not only a timer (P66)

`DispatchQueue.main` was drained only by the tickler's `SetTimer`. Every window
message re-armed that timer, so during an animation it never fired: P66 took 2
samples where AppKit takes 31. The tickler now keeps an earlier timer and also
waits on libdispatch's main-queue handle (`_dispatch_get_main_queue_handle_4CF`
via `RegisterWaitForSingleObject`), draining with
`_dispatch_main_queue_callback_4CF` (e9b80e8e, 2026-10-19). P66: 27 samples
idle. Idle CPU unchanged.

## Subclassing XAML controls

- **Do not subclass WebView2.** It takes a weak reference to its outer object;
  a Swift subclass makes that the Swift wrapper, and the release frees it
  (c0000374 heap corruption, found with cdb). `WebViewWidget` is a Grid holding
  an unsubclassed WebView2.
- `Border` is `final` in the binding; targets that need a subclass use a Grid.

## Other facts

- The nested message pump that waits for `RenderTargetBitmap` swallowed
  `WM_QUIT`; it re-posts it now (f191f46c).
- The frame clock is `CompositionTarget.Rendering`; `addHandler` returns an
  `EventCleanup`, so unsubscribing is `dispose()` (P64: 131 Hz on a 144 Hz panel,
  2026-10-19). `RenderingEventArgs` is not bound in swift-winui.
- WinUI's own compositor cannot be placed on a chosen GPU: `-GPU 0` and
  `-GPU N` report `.unavailable` (WinUIBackend+GraphicsAdapters.swift). Only
  app-owned swap chains (Mesh3D, P6 video) pick an adapter.

---

# WinUIBackend:技術堆疊、STA 啟動與主佇列

2026-10-24 依 Package.swift、Package.resolved、Sources/WinUIBackend/WinUIApplication+SingleThreaded.swift、
Console.swift、fd3378f1、e9b80e8e、f191f46c,以及 results.csv2(windows、winui:P38 2026-09-17、P66
2026-10-19)寫成。

## 技術堆疊

- WinUI 經由 **moreSwift/swift-winui 0.2.1** 引入(Package.resolved)。其 checkout 釘住
  **Microsoft.WindowsAppSDK 1.5.240205001-preview1**、TheBrowserCompany.SwiftWinRT 0.5.0 與 Win2D 1.1.1。
- 因為 WinAppSDK 是預覽版,Microsoft.UI.Xaml.dll 會在 stdout 印出 BVI-* / rcBackdropLocal;`Console.swift`
  會濾掉(「換成穩定版 WindowsAppSDK 後移除」,#204,未解決)。
- WinUIBackend 連結 d3d11 與 dxgi;WinUIInterop(C++)連結 d2d1、dwrite、windowscodecs、d3d11 與 dxgi。
- **2026-11-06 起，上面前兩點已過時(保留原文)。** swift-winui 改為 submodule `Vendor/swift-winui`
  (fork raliclo/swift-winui,develop),Package.swift 用 `.package(path:)`。bindings 以 swift-winrt 0.6.0
  針對 **Windows App SDK 2.6.5** 重新產生(`Vendor/swift-winui/Support/generate-bindings.zsh`)。
  0.6.0 移除了 `RoActivateInstance`,backend 自己的版本在 `Sources/WinUIBackend/WinRTActivation.swift`;
  static 方法都改為 `throws`。WinAppSDK 已非預覽版，但 `Console.swift` 的濾除在 2.6.5 上是否還需要尚未驗證。*(2026-11-07 已查證：繞過過濾時，
  P81-WinUI 與 P41-WinUI 印出的 BVI-*/rcBackdropLocal= 為 0 行；見 todo.md 第 6 項。)*
  執行需要 Windows App Runtime 2.6;`testapp/output` 若殘留舊的 `swift-winui_CWinAppSDK.resources`,
  它會比 `.bundle` 先被載入，app 會回報需要 Runtime 2.6。
- WebView2 在 2.6.5 上需要 exe 旁邊有 `Microsoft.Web.WebView2.Core.dll`:1.5 的 framework 套件附帶它,2.6.5 的沒有。
  swift-winui 08b5f91 把它當 CWinAppSDK 資源提供，compile.zsh 複製到 exe 旁邊。少了它，頁面空白且沒有任何錯誤(P38,2026-11-06)。

## 應用程式以單執行緒(STA)啟動

swift-winui 以 MTA 啟動 app。在 MTA 下,WebView2 的 `EnsureCoreWebView2Async` 永遠不會完成，shell 的
`IFileDialog` 也需要 STA。`WinUIApplication.runSingleThreaded()` 以
`WindowsAppRuntimeInitializer(threadingModel: .single)` 與**一份 swift-winui 內部 run-loop tickler 的複本**啟動
(fd3378f1,2026-09-17)。`SCUI_WINUI_MTA=1` 走舊路徑作為對照。

風險:swift-winui 更新後可能改了它的 tickler,而複本維持原樣。壞掉的 tickler 會靜默停止 `DispatchQueue.main` 與
main actor 的工作；要看 RENDER COMPLETE 標記，而不是視窗大小，才看得出來。

## 主佇列靠等待排空，不只靠計時器(P66)

`DispatchQueue.main` 原本只靠 tickler 的 `SetTimer` 排空。每個視窗訊息都重設那個計時器，所以動畫期間它從不觸發:
P66 只取到 2 個樣本,AppKit 有 31 個。tickler 現在保留較早的計時器，並另外等待 libdispatch 的主佇列 handle
(以 `RegisterWaitForSingleObject` 等 `_dispatch_get_main_queue_handle_4CF`),以
`_dispatch_main_queue_callback_4CF` 排空(e9b80e8e,2026-10-19)。P66 閒置時 27 個樣本。閒置 CPU 不變。

## 繼承 XAML 控制項

- **不要繼承 WebView2。** 它對自己的外層物件取弱參照；用 Swift 子類別時外層物件就是 Swift 包裝，釋放時把它釋放掉
  (c0000374 堆積損毀，以 cdb 找到)。`WebViewWidget` 是一個裝著未繼承之 WebView2 的 Grid。
- binding 中 `Border` 是 `final`;需要子類別的目標改用 Grid。

## 其他事實

- 等待 `RenderTargetBitmap` 的巢狀訊息迴圈曾吞掉 `WM_QUIT`;現在會重新送出(f191f46c)。
- frame clock 是 `CompositionTarget.Rendering`;`addHandler` 回傳 `EventCleanup`,取消訂閱就是 `dispose()`
  (P64:144 Hz 面板上 131 Hz,2026-10-19)。swift-winui 沒有 bind `RenderingEventArgs`。
- WinUI 自己的合成器無法放到指定的 GPU 上:`-GPU 0` 與 `-GPU N` 回報 `.unavailable`
  (WinUIBackend+GraphicsAdapters.swift)。只有 app 自己的 swap chain(Mesh3D、P6 影片)能選 adapter。
