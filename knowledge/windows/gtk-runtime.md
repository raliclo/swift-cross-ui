# GtkBackend on Windows: the GTK runtime and -gtk4 builds

Written 2026-10-24 from testapp/install_gtk4_windows.zsh,
install_gtk4_accesskit_windows.zsh, test_support/gtk_runtime.zsh,
testapp/plan/plan-windows-gtk-backend.md and commits 4d76c330, 60a46d8d, a7a933ab.

## What

- **GTK 4.22.4 from gvsbuild**, not MSYS2 and not vcpkg.
  `install_gtk4_windows.zsh` unpacks `GTK4_Gvsbuild_2026.8.0_x64.zip` (about
  286 MB) into `C:/gtk4`. It is built with MSVC against the UCRT; the DLL is
  `gtk-4-1.dll` (MSYS2's is `libgtk-4-1.dll`).
- **Why not MSYS2:** Swift on Windows uses the MSVC ABI, and MinGW import
  libraries do not link cleanly. Also, MSYS2's GTK has Vulkan but no `dcomp`
  switch, and GTK's Win32 backend needs Direct Composition for both GL and
  Vulkan, so MSYS2 loses the hardware renderer (checked 2026-08-29 with MSYS2's
  own gtk4-demo.exe). `vcpkg.json` is upstream's and unused by the fork's tooling.
- **AccessKit build:** `install_gtk4_accesskit_windows.zsh` builds GTK 4.22.4
  with `-Daccesskit=enabled` into `C:/gtk4-accesskit` (4d76c330, 2026-09-18).
  No published binary has AccessKit (gvsbuild, MSYS2, conda-forge, vcpkg were
  checked). Build notes: clang-cl, not cl (MSVC 19.44 runs out of heap on
  `gtkresources.c`); `-D_USE_MATH_DEFINES -Df16c=disabled`; use the bundle's own
  pkgconf.
- **2026-10-29: GTK 4.24.1, and 4.22.4 removed.** The two bullets above
  describe 4.22.4 and gvsbuild 2026.8.0 as they were. Now `C:/gtk4` is
  gvsbuild 2026.10.0 (GTK 4.24.1, still no AccessKit) and `C:/gtk4-accesskit`
  is 4.24.1 built from `testapp/gtk4-source` on branch `develop` of
  https://github.com/raliclo/gtk: 4.24.1 plus f25d596, the fix for the
  touch-device use-after-free ([Input](gtk-input.md)). Two more build needs:
  a `tgmath.h` shim on `-I` (clang's tgmath.h and the MSVC CRT disagree on
  complex types; before this it was an untracked edit to `gtk/gtksvg.c`), and
  `-Dlibsass:cpp_std=c++17` for the sassc that a git checkout builds its
  theme with. `install_gtk4_windows.zsh` now moves an install of another
  release aside to `C:/gtk4-<release>`; until then it printed "already
  installed" over any version and changed nothing.
- **WebView2 for `WebView`:** WebKitGTK has no Windows port. The installer puts
  `WebView2.h` under `<prefix>/include/webview2` (NuGet 1.0.3179.45);
  `Sources/GtkCHelpers/gtk_webview2.c` parents a WebView2 into the GTK
  window's HWND and loads `WebView2Loader.dll` at run time. Without the header
  the file compiles to stubs and the view shows a labelled placeholder.

## Two installer fixes that matter

- 301 of 302 `.pc` files hard-code `C:/gtk-build/gtk/x64/release` and have CRLF
  line endings. SwiftPM parses `.pc` files itself and splits on the first
  colon, so `prefix=C:/gtk4` fails. The installer rewrites the prefix to
  `${pcfiledir}/../..` and strips the CRs (`--show-changes` audits it).
- Downloads go to `C:/gtk4-download`, never `/tmp`: scoop's zsh and scoop's
  Git map `/tmp` to different places.

## Which runtime loads

Nothing is copied next to the exe. `test_support/gtk_runtime.zsh` (60a46d8d),
sourced by `run.zsh`, `window_sizes.zsh` and `test_common.zsh`, puts
`C:/gtk4-accesskit/bin` first if it holds `gtk-4-1.dll`, then `C:/gtk4/bin`
(the AccessKit prefix holds GTK only; glib, pango and cairo come from the
bundle). `GTK4_PREFIX` picks one runtime alone; `SCUI_GTK_NO_ACCESSKIT=1` uses
the bundle alone. No rebuild is needed to switch.

Paths go on PATH in POSIX form (`cygpath -u`): `C:/gtk4/bin` is split at the
colon into two entries. All three call sites made that mistake once. A bare
`Pn-gtk4.exe` started outside these scripts dies on a missing DLL
(`api-ms-win-crt-locale`, results.csv2 windows gtk4 P62 2026-10-07).

## -gtk4 builds

`compile.zsh -gtk4` sets `SCUI_DEFAULT_BACKEND=GtkBackend` and
`PKG_CONFIG_PATH=$GTK4_PREFIX/lib/pkgconfig`, removes the WinUI products and the
swift-winui dependency from the generated manifest, and writes
`Pn-gtk4.exe`. Apps that import WinUI (P4, P6) are refused; P6-v2 is P6's GTK
counterpart. `CGtk` uses `pkgConfig: "gtk4"`; GtkCHelpers also links `epoxy`
and, on Windows, `dwmapi`.

---

# Windows 上的 GtkBackend:GTK runtime 與 -gtk4 建置

2026-10-24 依 testapp/install_gtk4_windows.zsh、install_gtk4_accesskit_windows.zsh、
test_support/gtk_runtime.zsh、testapp/plan/plan-windows-gtk-backend.md 與 4d76c330、60a46d8d、a7a933ab 寫成。

## 內容

- **GTK 4.22.4 取自 gvsbuild**,不是 MSYS2,也不是 vcpkg。`install_gtk4_windows.zsh` 把
  `GTK4_Gvsbuild_2026.8.0_x64.zip`(約 286 MB)解到 `C:/gtk4`。它以 MSVC 針對 UCRT 建置,DLL 名稱是
  `gtk-4-1.dll`(MSYS2 的是 `libgtk-4-1.dll`)。
- **為何不用 MSYS2:**Windows 上的 Swift 用 MSVC ABI,MinGW 的 import library 無法順利連結。此外 MSYS2 的 GTK
  有 Vulkan 卻沒有 `dcomp` 開關，而 GTK 的 Win32 backend 不論 GL 或 Vulkan 都需要 Direct Composition,所以
  MSYS2 會失去硬體算繪器(2026-08-29 以 MSYS2 自己的 gtk4-demo.exe 確認)。`vcpkg.json` 是上游留下的，本 fork
  的工具不使用。
- **AccessKit 建置:**`install_gtk4_accesskit_windows.zsh` 以 `-Daccesskit=enabled` 建置 GTK 4.22.4 到
  `C:/gtk4-accesskit`(4d76c330,2026-09-18)。沒有任何已發布的二進位檔帶 AccessKit(查過 gvsbuild、MSYS2、
  conda-forge、vcpkg)。建置要點：用 clang-cl 而非 cl(MSVC 19.44 編 `gtkresources.c` 時堆積空間不足);
  `-D_USE_MATH_DEFINES -Df16c=disabled`;使用套件自己的 pkgconf。
- **2026-10-29:改為 GTK 4.24.1,4.22.4 已移除。** 上面兩條描述的是當時的 4.22.4 與 gvsbuild 2026.8.0。現在
  `C:/gtk4` 是 gvsbuild 2026.10.0(GTK 4.24.1,仍沒有 AccessKit),`C:/gtk4-accesskit` 是以 `testapp/gtk4-source`
  建置的 4.24.1——位於 https://github.com/raliclo/gtk 的 `develop` 分支：4.24.1 加上 f25d596,即觸控裝置
  use-after-free 的修正([輸入](gtk-input.md))。建置另需兩項：放在 `-I` 上的 `tgmath.h` 墊片(clang 的 tgmath.h
  與 MSVC CRT 對複數型別不相容；在此之前它是對 `gtk/gtksvg.c` 的未追蹤修改),以及給 git checkout 建主題用的 sassc
  的 `-Dlibsass:cpp_std=c++17`。`install_gtk4_windows.zsh` 現在會把其他發行版的安裝移到 `C:/gtk4-<發行版>`;
  在此之前，不論版本為何它都印出「already installed」而什麼都不改。
- **`WebView` 用 WebView2:**WebKitGTK 沒有 Windows 版。安裝程式把 `WebView2.h` 放到
  `<prefix>/include/webview2`(NuGet 1.0.3179.45);`Sources/GtkCHelpers/gtk_webview2.c` 把 WebView2 掛到 GTK
  視窗的 HWND 底下，並在執行期載入 `WebView2Loader.dll`。沒有標頭檔時該檔編成空殼，畫面顯示附說明的佔位文字。

## 兩項重要的安裝修正

- 302 個 `.pc` 檔中有 301 個寫死 `C:/gtk-build/gtk/x64/release`,而且是 CRLF 行尾。SwiftPM 自己解析 `.pc`,
  並在第一個冒號處切開，所以 `prefix=C:/gtk4` 會失敗。安裝程式把 prefix 改寫為 `${pcfiledir}/../..` 並去掉 CR
  (`--show-changes` 可稽核)。
- 下載到 `C:/gtk4-download`,不放 `/tmp`:scoop 的 zsh 與 scoop 的 Git 把 `/tmp` 對應到不同位置。

## 載入哪一份 runtime

exe 旁邊不複製任何東西。`test_support/gtk_runtime.zsh`(60a46d8d)由 `run.zsh`、`window_sizes.zsh` 與
`test_common.zsh` 引入：若 `C:/gtk4-accesskit/bin` 裡有 `gtk-4-1.dll` 就排第一，其次是 `C:/gtk4/bin`
(AccessKit prefix 只有 GTK;glib、pango、cairo 來自套件)。`GTK4_PREFIX` 只用指定的那一份;
`SCUI_GTK_NO_ACCESSKIT=1` 只用套件那一份。切換不必重建。

放進 PATH 的路徑要用 POSIX 形式(`cygpath -u`):`C:/gtk4/bin` 會在冒號處被切成兩個項目。三個呼叫處都犯過一次。
在這些腳本之外直接執行 `Pn-gtk4.exe` 會因缺 DLL 而終止(`api-ms-win-crt-locale`,results.csv2 windows gtk4
P62 2026-10-07)。

## -gtk4 建置

`compile.zsh -gtk4` 設定 `SCUI_DEFAULT_BACKEND=GtkBackend` 與 `PKG_CONFIG_PATH=$GTK4_PREFIX/lib/pkgconfig`,
從產生的 manifest 移除 WinUI product 與 swift-winui 相依，輸出 `Pn-gtk4.exe`。import WinUI 的 app(P4、P6)會被
拒絕;P6-v2 是 P6 的 GTK 對應版。`CGtk` 使用 `pkgConfig: "gtk4"`;GtkCHelpers 另外連結 `epoxy`,在 Windows
上還有 `dwmapi`。
