# GtkBackend on macOS: toolchain and build

Checked 2026-10-24 on the M4 Mac: Homebrew `gtk4 4.24.1`, `libepoxy 1.5.10`.

## What

GtkBackend runs on macOS against Homebrew's GTK 4. It is intended, not a
stretch: `Package.swift` declares the CGtk system library with
`providers: [.brew(["gtk4"])]`. A GTK test run is the macOS run with
`TEST_BACKEND=gtk4`:

```sh
zsh testapp/install_tool_mac.zsh            # check, install what is missing
TEST_BACKEND=gtk4 zsh testapp/test.zsh P84 --macos
```

## Setup: install_tool_mac.zsh

- `--check` reports only; `--print-env` prints `SCUI_HOST_BACKENDS_ONLY=1` and
  `SCUI_TEST_CFLAGS=-I$(brew --prefix)/include`; `--test` sets up and runs the
  suite, exiting with the suite's status.
- **libepoxy's header exists and is not found.** `gtk4.pc` lists epoxy as a
  private requirement, so `pkg-config --cflags gtk4` never names it. On Linux
  the header is in `/usr/include`; Homebrew puts it in `$(brew --prefix)/include`,
  which clang does not search, and `gtk_nv12_gl.c` fails on `<epoxy/gl.h>`. The
  fix is a flag, not an install: `-Xcc -I$(brew --prefix)/include`.
- **`swift test` builds every target.** WinUIBackend (needs the Windows SDK) and
  UIKitBackend (no macOS slice) cannot compile on a Mac;
  `SCUI_HOST_BACKENDS_ONLY=1` drops both from the manifest. Full command:
  `env SCUI_HOST_BACKENDS_ONLY=1 swift test -Xcc -I$(brew --prefix)/include`.
- The suite is expected fully green (44 tests in 9 suites, plus 10 in
  InputEvent, per the script header). An AppKit metrics test that once asserted
  `ViewSize(92, 96)` broke on macOS 27 (NSButton 82x24 instead of 72x20); it now
  derives its numbers from the backend.

## Build: compile.zsh -gtk4 on Darwin

The Darwin branch exists since 2026-10-09; before it `-gtk4` stopped at
"GTK 4 not found at C:/gtk4". It:

- refuses with `Run: zsh testapp/install_tool_mac.zsh` when `pkg-config` cannot
  see gtk4, and adds `-Xcc -I$(brew --prefix)/include`;
- exports `SCUI_DEFAULT_BACKEND=GtkBackend`, which is what redirects
  `import DefaultBackend`;
- **drops the AppKitBackend product and deletes any AppKitBackend module left
  in the tree.** `DefaultBackend.swift` checks `#if canImport(AppKitBackend)`
  first, and `canImport` sees a stale `.swiftmodule` as readily as a fresh one.
  Measured 2026-10-09: the first `-gtk4` P84 ran on GTK only because
  DefaultBackend happened to compile first; the next build produced an AppKit
  app named `P84-gtk4`;
- builds in `testapp/.compile-work-gtk4` (the AppKit build uses
  `.compile-work-appkit`) and writes `output/Pn-gtk4`, so it does not
  overwrite the AppKit `output/Pn`. `run_macos` copies `output/Pn-gtk4` into the
  shared `.macApp/debugTarget.app` and names captures `pn-macos-gtk4-*`.

## Limits

- An app that imports the WinUI products (`UWP`, `WinUI`, `WinUIBackend`,
  `WindowsFoundation`) has no GTK build: P6. Its GTK form is P6-v2.
  `sweep_apple.zsh --macos-gtk4` skips such apps and says so; the 2026-10-16
  gtk4 sweep had reported a failure for P6's impossible build (results.csv2:
  mac, gtk4, P6, 2026-10-16).
- Homebrew has no WebKitGTK for macOS. `WebView` on GtkBackend uses WKWebView
  instead (`GtkBackend+WebViewMac.swift`); see `gtk-platform-integration.md`.

---

# macOS 上的 GtkBackend:工具鏈與建置

2026-10-24 於 M4 Mac 確認:Homebrew `gtk4 4.24.1`、`libepoxy 1.5.10`。

## 是什麼

GtkBackend 在 macOS 上以 Homebrew 的 GTK 4 執行。這是刻意支援的:`Package.swift` 宣告 CGtk 系統函式庫時寫著
`providers: [.brew(["gtk4"])]`。GTK 測試就是帶 `TEST_BACKEND=gtk4` 的 macOS 執行(指令見上)。

## 安裝:install_tool_mac.zsh

- `--check` 只回報;`--print-env` 印出 `SCUI_HOST_BACKENDS_ONLY=1` 與 `SCUI_TEST_CFLAGS=-I$(brew --prefix)/include`;
  `--test` 安裝後執行測試套件，並以套件的結束碼結束。
- **libepoxy 的標頭檔存在卻找不到。** `gtk4.pc` 把 epoxy 列為 private requirement,`pkg-config --cflags gtk4`
  從不提到它。Linux 上標頭檔在 `/usr/include`;Homebrew 放在 clang 不會搜尋的 `$(brew --prefix)/include`,
  於是 `gtk_nv12_gl.c` 在 `<epoxy/gl.h>` 失敗。解法是一個旗標而不是安裝:`-Xcc -I$(brew --prefix)/include`。
- **`swift test` 會建置每一個 target。** WinUIBackend(需要 Windows SDK)與 UIKitBackend(沒有 macOS 版)
  在 Mac 上無法編譯;`SCUI_HOST_BACKENDS_ONLY=1` 把兩者從 manifest 拿掉。
- 套件預期全綠(依腳本檔頭：9 個 suite 共 44 項，另加 InputEvent 的 10 項)。一項曾寫死 `ViewSize(92, 96)` 的 AppKit
  尺寸測試在 macOS 27 上失敗(NSButton 變成 82x24,原本 72x20),現在改由 backend 推導數字。

## 建置:Darwin 上的 compile.zsh -gtk4

Darwin 分支自 2026-10-09 起存在；在那之前 `-gtk4` 會停在「GTK 4 not found at C:/gtk4」。它會:

- `pkg-config` 看不到 gtk4 時拒絕並提示執行 install_tool_mac.zsh,並加上 `-Xcc -I$(brew --prefix)/include`;
- export `SCUI_DEFAULT_BACKEND=GtkBackend`,這才是改變 `import DefaultBackend` 指向的關鍵;
- **移除 AppKitBackend product,並刪掉樹中殘留的 AppKitBackend 模組。** `DefaultBackend.swift` 先檢查
  `#if canImport(AppKitBackend)`,而 `canImport` 看得到過期的 `.swiftmodule`。2026-10-09 實測：第一次 `-gtk4` 的 P84
  能跑在 GTK 上，只是因為 DefaultBackend 剛好先編譯；下一次建置就產出了一支名叫 `P84-gtk4` 的 AppKit app;
- 在 `testapp/.compile-work-gtk4` 建置(AppKit 用 `.compile-work-appkit`),輸出 `output/Pn-gtk4`,不覆蓋 AppKit 的
  `output/Pn`。`run_macos` 把它複製進共用的 `.macApp/debugTarget.app`,擷圖檔名為 `pn-macos-gtk4-*`。

## 限制

- 匯入 WinUI product 的 app 沒有 GTK 建置:P6,其 GTK 版是 P6-v2。`sweep_apple.zsh --macos-gtk4` 會略過並說明;
  2026-10-16 的 gtk4 sweep 曾為這個不可能存在的建置回報失敗(results.csv2:mac、gtk4、P6、2026-10-16)。
- Homebrew 沒有 macOS 版 WebKitGTK。GtkBackend 的 `WebView` 改用 WKWebView(`GtkBackend+WebViewMac.swift`),
  見 `gtk-platform-integration.md`。
