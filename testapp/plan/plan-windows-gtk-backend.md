# Windows: GtkBackend alongside WinUIBackend

GtkBackend is the Windows target; WinUIBackend is frozen as the baseline.
Nothing is removed by this plan.

在 Windows 上以 GtkBackend 為目標，WinUIBackend 凍結為 baseline。本計畫不移除任何
既有實作。

## Decision: WinUIBackend is frozen, GtkBackend is the target

Taken 2026-08-19. This supersedes the "evaluating" framing this document opened
with; the evaluation is over.

**Frozen means:** no new Pn apps target WinUIBackend, no further measurement
runs against it, and no build waits on it. The 20 existing `.exe` files stay as
the comparison set, which is what "keep the Windows backend as baseline" asked
for. The backend source is untouched and still builds.

**What decided it** — compile time was the original complaint; binary size is
the evidence added on the day of the decision:

| | Binary | Incremental build |
|---|---|---|
| GTK, Linux release | **51 MB** | **14s** |
| WinUI, Windows release | 167 MB (3.3x) | — |
| WinUI, Windows debug | 332 MB (6.5x) | 38s (2.7x) |

Size is the more honest of the two numbers. The 2.7x on incremental builds is
real but survivable; a binary that is 3.3x larger in release and 6.5x in debug
is WinAppSDK's static content, and no build-configuration change reaches it.

**The blocker this decision does not remove.** GtkBackend's *library* compiles
on Windows, but no `Pn.exe` has ever linked against it and the `-gtk4` work
directory has produced zero binaries. Until that link succeeds, every runnable
Windows binary is a WinUI one. So the freeze is a decision about where new work
goes, not a claim that the replacement is ready. Do not delete or break
WinUIBackend on the strength of this section.

Two causes have been found and fixed so far, both of which wasted a full build
each before announcing themselves:

1. `missing required modules: 'CGtk', 'GtkCHelpers'` — SwiftPM resolves the
   `CGtk` systemLibrary itself and needs `PKG_CONFIG_PATH` to find `gtk4.pc`.
   The `-Xcc` include flags are a separate mechanism and do not cover it. Fixed
   by exporting the variable in `compile.zsh`.
2. `-gtk4` did not change the backend at all. It added GtkBackend as a linkable
   product, but `import DefaultBackend` resolves through a hard-coded
   per-platform list in `Package.swift` (WinUIBackend on Windows). The flag
   therefore linked *both* backends, ran on WinUI, built *more* than the default
   rather than less, and died emitting `WindowsFoundation` — a target the flag
   exists to avoid. Fixed by exporting `SCUI_DEFAULT_BACKEND=GtkBackend`, the
   hook `Package.swift` already provides.

The second one is worth remembering as a shape: a flag that appears to work
because the build changes, while the thing it was meant to select never
changed.

**Result, measured on P0 the same day.** Redirecting `DefaultBackend` was not
enough on its own: the app still named `WinUIBackend`, `WinUI`, `UWP` and
`WindowsFoundation` in its own dependency list, so WinUI was pulled in
regardless. Dropping those four products, and the `swift-winui` package
dependency with them:

| | with WinUI | GTK only | |
|---|---|---|---|
| build | 788s | **115s** | 6.9x |
| binary | 342 MB | **73 MB** | 4.7x |
| WinUI compile steps | 73 | **0** | — |

For scale, the Linux release binary is 51 MB, so Windows debug at 73 MB is 1.4x
rather than the 6.5x it was.

The backend switch and the savings are separate achievements, and the first
happened a build before the second. An `-gtk4` run that reports
`backend GtkBackend` proves only the first.

**結果，同日於 P0 上實測。** 單靠改變 `DefaultBackend` 的解析並不足夠：app 在自己的依賴清單中
仍點名了 `WinUIBackend`、`WinUI`、`UWP` 與 `WindowsFoundation`，因此 WinUI 照樣被帶入。移除
這四個 product，以及連同的 `swift-winui` 套件依賴之後，結果如上表。

作為對照，Linux 的 release 執行檔為 51 MB，因此 Windows debug 的 73 MB 是 1.4 倍，而非先前的
6.5 倍。

「切換 backend」與「取得效益」是兩項各自獨立的成果，而前者比後者早了一次建置達成。一次回報
`backend GtkBackend` 的 `-gtk4` 執行，只證明了前者。

目前已找到並修正兩項成因，且兩者都各浪費了一次完整建置才顯現：

1. `missing required modules: 'CGtk', 'GtkCHelpers'`——SwiftPM 會自行解析 `CGtk` 這個
   systemLibrary，需要 `PKG_CONFIG_PATH` 才能找到 `gtk4.pc`。`-Xcc` 的 include 旗標是
   另一套機制，並不涵蓋此需求。已於 `compile.zsh` 中 export 該變數修正。
2. `-gtk4` 根本沒有切換 backend。它只是把 GtkBackend 加為可連結的 product，但
   `import DefaultBackend` 是透過 `Package.swift` 中依平台寫死的清單解析（Windows 為
   WinUIBackend）。因此該旗標同時連結了*兩個* backend、實際跑在 WinUI 上、建置的東西比
   預設*更多*而非更少，並在產生 `WindowsFoundation` 時失敗——而那正是此旗標意在避開的
   target。已透過 export `SCUI_DEFAULT_BACKEND=GtkBackend` 修正，那是 `Package.swift`
   既有的鉤子。

第二項的形態值得記住：一個旗標因為建置行為確實改變了而看似生效，但它原本要選擇的東西
從未改變。

**Why GTK4 is not a submodule.** Windows gets GTK4 from
`testapp/install_gtk4_windows.zsh`, which downloads a gvsbuild release zip and
patches its `.pc` files. gvsbuild is a build system of Python recipes, not a
binary distribution, so a submodule would pull in recipes and still require a
local multi-hour MSVC build; the release artefacts are what is actually wanted.
GTK4 upstream has the same problem. The pinning that a submodule would give is
instead the version string in that script.

2026-08-19 決定。本節取代文件開頭的「評估中」框架；評估已結束。

**凍結的意思**：不再有新的 Pn app 以 WinUIBackend 為目標、不再對其進行量測、建置流程也
不再等待它。既有的 20 支 `.exe` 保留作為對照組，這正是「保留 Windows backend 作為
baseline」所要求的。該 backend 的原始碼不動，且仍可建置。

**決定的依據**：編譯時間是最初的抱怨，而檔案大小是決定當日新增的證據（如上表）。大小是
兩者中較誠實的數字。增量建置的 2.7 倍雖屬實但尚可忍受；release 下大 3.3 倍、debug 下大
6.5 倍的執行檔則是 WinAppSDK 的靜態內容，任何建置組態的調整都碰不到它。

**本決定並未解除的阻擋點**：GtkBackend 的*函式庫*可在 Windows 編譯，但從未有任何
`Pn.exe` 成功連結它——最後一次嘗試以 `missing required modules: 'CGtk', 'GtkCHelpers'`
失敗，且 `-gtk4` 的工作目錄至今產出零個執行檔。在該連結成功之前，Windows 上每一支可執行
的二進位檔都仍是 WinUI 產物。因此本次凍結是關於「新工作往哪裡去」的決定，而非宣稱替代方案
已就緒。請勿以本節為由刪除或破壞 WinUIBackend。

**為何 GTK4 不做成 submodule**：Windows 端的 GTK4 來自
`testapp/install_gtk4_windows.zsh`，它下載 gvsbuild 的 release zip 並修補其 `.pc` 檔。
gvsbuild 是一套由 Python recipes 構成的建置系統，而非二進位發行版；做成 submodule 只會
取得那些 recipes，仍須在本機執行數小時的 MSVC 建置，而我們真正需要的是它的 release
產物。GTK4 上游也有相同問題。submodule 所能提供的版本鎖定，改由該腳本中的版本字串負責。

## Why

Compile time. The figures that started this were wrong and are corrected below,
because they were used to justify the work and would otherwise keep being cited.

**The wrong comparison.** Early in the P6 work these two numbers were put side
by side: P6 on Windows at 95-103s against P6 in WSL at 13-22s, called a 5x
difference and attributed to WinAppSDK. They confound three variables at once —
operating system, backend, and whether the build was incremental or from
scratch — so they cannot support a claim about any one of them.

**The measured comparison.** One source file changed, both trees already warm:

| Platform | Config | Incremental build |
|---|---|---|
| Windows | debug | **38s** |
| Linux | release | **14s** |

About 2.7x, not 15x. WinAppSDK's cost falls almost entirely on the first build,
not on day-to-day iteration.

**First builds, for contrast:**

| Platform | Config | From scratch |
|---|---|---|
| Windows | release | 20-30 min, and killed at 97% several times, producing nothing |
| Windows | debug | 848s (14 min), produced a binary |
| Linux | release | 590s for a fresh tree |

編譯時間。當初據以啟動這項工作的數字是錯的，以下更正，否則它會一再被引用。

**錯誤的比較**：P6 工作初期把「Windows 95-103 秒」與「WSL 13-22 秒」並列，稱為 5 倍差距
並歸因於 WinAppSDK。這組數字同時混淆了三個變數——作業系統、backend，以及該次是增量還是
從零建置——因此無法支持關於其中任一項的結論。

**實測的比較**（改動單一原始檔、兩邊目錄樹皆已溫熱）：如上表，約 2.7 倍而非 15 倍。
WinAppSDK 的成本幾乎全部落在首次建置，而非日常迭代。

## Build configuration decision

Windows builds default to debug; Linux stays on release. Set in
`testapp/compile.zsh`, overridable with `BUILD_CONFIG`.

**Why Windows departs from the project's release-by-default rule.** Release
means whole-module optimisation across WinAppSDK and the whole Gtk module. A
from-scratch build ran 20-30 minutes and was killed at 97% more than once, so
the practical outcome of keeping release was no binary at all. Debug produced
one in 14 minutes and rebuilds in 38s.

**Why release cannot simply be made incremental.** In release SwiftPM uses
whole-module optimisation, where the compilation unit is the entire module so
the optimiser can inline and specialise across files. File-level incrementality
does not exist there by construction: change one file and the module recompiles.
`Sources/Gtk` is roughly 180 generated files, and in release that is one unit —
which is why a single `swift-frontend` was seen holding 2.9 GB. Debug compiles
per file with dependency tracking. If optimised *and* incremental is ever wanted,
`-Xswiftc -no-whole-module-optimization` is the middle ground.

**Why Linux keeps release.** Its incremental build is already 14s, so debug
would save little, and the cost is the same on both platforms: an unoptimised
app. Windows was worth changing because the alternative there was no binary;
Linux has no such problem.

**What this costs, and it is not free.** A Windows build is no longer valid for
measuring startup or interaction latency, and the binary is larger — P19.exe is
333 MB in debug against roughly 167 MB in release. Any run whose numbers matter
must set `BUILD_CONFIG=release` explicitly, and any figure recorded from Windows
must say which configuration produced it.

建置組態決定：Windows 預設 debug，Linux 維持 release，設定於 `testapp/compile.zsh`，
可由 `BUILD_CONFIG` 覆寫。

Windows 偏離「預設 release」規則的理由：release 意味著對 WinAppSDK 與整個 Gtk 模組進行
whole-module 最佳化，從零建置需 20-30 分鐘，且曾多次在 97% 被終止而未產出任何檔案；改用
debug 後 14 分鐘完成，增量重建僅 38 秒。

release 無法直接改為增量的原因：release 使用 whole-module 最佳化，其編譯單位是整個模組，
以便最佳化器跨檔案內聯與特化。檔案層級的增量在該模式下依定義不存在——改一個檔案即重編整個
模組。`Sources/Gtk` 約有 180 個生成檔案，在 release 下屬同一個編譯單位，這正是曾觀察到單一
`swift-frontend` 佔用 2.9 GB 的原因。若日後需要「已最佳化且可增量」，
`-Xswiftc -no-whole-module-optimization` 是折衷選項。

Linux 維持 release 的理由：其增量建置已為 14 秒，改用 debug 節省有限，而代價與 Windows
相同——app 未經最佳化。Windows 值得更改，是因為那裡的替代方案是「沒有二進位檔」；Linux
不存在此問題。

代價（並非沒有）：Windows 的建置不再適用於量測啟動或互動延遲，且檔案更大——P19.exe 在
debug 下為 333 MB，release 約 167 MB。凡數字有意義的執行，必須明確設定
`BUILD_CONFIG=release`；任何來自 Windows 的數據都必須註明所用組態。

## The ABI constraint

Swift on Windows targets the MSVC ABI and links the UCRT. GTK 4 has to match:

- MSYS2's GTK 4 is MinGW-built. Its import libraries do not link cleanly into
  MSVC binaries, so it is not a candidate.
- gvsbuild publishes GTK 4 built with MSVC against the UCRT. That is what
  `testapp/install_gtk4_windows.zsh` fetches (`GTK4_Gvsbuild_<version>_x64.zip`).

If linking fails despite this, the first thing to check is which CRT the GTK
DLLs were built against, not the Swift side.

Swift on Windows 以 MSVC ABI 為目標並連結 UCRT，GTK 4 必須一致。MSYS2 的 GTK 4 是
MinGW 建置，import library 無法乾淨連結進 MSVC 二進位檔，因此不列入考慮；gvsbuild
提供的是以 MSVC 針對 UCRT 建置的版本，即 `install_gtk4_windows.zsh` 取得的套件。若在
此前提下仍連結失敗，應先確認 GTK DLL 連結的是哪個 CRT，而非先懷疑 Swift 端。

## What switching costs

**Corrected 2026-08-20.** This section used to say `DefaultBackend` already
prefers Gtk over WinUI, quoting a `canImport` chain, and concluded that
installing GTK 4 on Windows switches the default with no source change — calling
the silent switch the main risk.

That is not what happens. The `canImport` chain governs which backends are
*importable*; which one `DefaultBackend` resolves to comes from
`Package.swift`, which hard-codes it per platform:

```swift
.target(name: "WinUIBackend", condition: .when(platforms: [.windows])),
.target(name: "GtkBackend",   condition: .when(platforms: [.linux])),
```

There is no preference order to inherit. Installing GTK 4 changes nothing by
itself; `compile.zsh -gtk4` does the switching, by exporting
`SCUI_DEFAULT_BACKEND=GtkBackend` and dropping the WinUI products from the
generated manifest.

The risk is therefore the opposite of what was written. Nothing switches
silently — the failure mode is a flag that appears to work while the backend
never changes, which is what happened twice before it was caught.

**2026-08-20 更正。** 本節原本寫著 `DefaultBackend` 本來就把 Gtk 排在 WinUI 之前，並引用一段
`canImport` 鏈，據此推論在 Windows 安裝 GTK 4 即可在不改動原始碼的情況下切換預設，還把
「靜默切換」列為主要風險。

實際情況並非如此。`canImport` 鏈決定的是哪些 backend「可被 import」；`DefaultBackend` 實際
解析到哪一個，取決於 `Package.swift`，而它是依平台寫死的（如上）。

並不存在可繼承的優先順序。單獨安裝 GTK 4 不會改變任何事；真正完成切換的是
`compile.zsh -gtk4`——它 export `SCUI_DEFAULT_BACKEND=GtkBackend`，並從產生的 manifest 中
移除 WinUI 的 product。

因此風險與原文所寫的正好相反。沒有任何東西會靜默切換——真正的失敗模式是「旗標看似生效，
backend 卻從未改變」，而這在被發現之前已經發生過兩次。

P6 carries 38 `#if os(Windows)` blocks that assume WinUIBackend — the D3D11
video interop, the SwapChainPanel, the NV12 presentation path. Those are
compiled on `os(Windows)`, not on which backend is active, so under `-gtk4` they
would still compile while the backend underneath them changed.

This was the part expected to produce a confusing failure, and it is now closed
rather than open. `-gtk4` removes the WinUI products, so P6 cannot link at all,
and `compile.zsh` refuses it up front with a stated reason instead of failing
thirteen minutes into a build with `no such module 'UWP'`. The exclusion is
permanent, not a gap: a SwapChainPanel and a D3D11 composition swap chain have
no GtkBackend equivalent.

P6's GTK counterpart is **P6-v2**, written fresh rather than copied. It keeps
P6's measurement vocabulary — the same 1x/2x/3x speeds, 30/45/60 frame rates,
resolutions and dropped-frame accounting — so the two produce comparable
numbers, and drops the D3D11 apparatus, the macOS Metal and CoreVideo paths and
the stream fetching, which is roughly 2700 of P6's 3990 lines.

P6 有 38 個 `#if os(Windows)` 區塊假設 WinUIBackend（D3D11 video interop、SwapChainPanel、
NV12 呈現路徑）。這些以 `os(Windows)` 為條件，而非以「哪個 backend 生效」為條件，因此在
`-gtk4` 下它們仍會被編譯，底下的 backend 卻已改變。

這原本被列為最可能產生費解失敗之處，現在則已關閉而非仍然開放。`-gtk4` 會移除 WinUI 的
product，因此 P6 根本無法連結，而 `compile.zsh` 會在一開始就以明確理由拒絕它，而不是在建置
進行十三分鐘後才以 `no such module 'UWP'` 失敗。此項排除是永久性的，而非缺口：
SwapChainPanel 與 D3D11 composition swap chain 在 GtkBackend 中沒有對應物。

P6 的 GTK 對應版本是 **P6-v2**，採全新撰寫而非複製。它保留 P6 的量測語彙——相同的 1x/2x/3x
速度、30/45/60 幀率、解析度與掉幀計算方式——使兩者產生可比較的數字；並捨棄 D3D11 設施、
macOS 的 Metal 與 CoreVideo 路徑，以及串流取得，這些約佔 P6 3990 行中的 2700 行。

## Steps

1. **Install** — `zsh testapp/install_gtk4_windows.zsh`, then export
   `PKG_CONFIG_PATH` and `PATH` as it prints.
   → verify: `pkg-config --modversion gtk4` reports a version.

2. **Compile GtkBackend on Windows** — `swift build --target GtkBackend`.
   → verify: it builds. If it does not, the error decides whether this plan is
   viable at all; record it and stop rather than working around it.

3. **Compile-time comparison** — done for the platforms, not yet for the
   backends. The incremental figures above are Windows/WinUI against
   Linux/Gtk, which still mixes platform with backend. The comparison this plan
   actually needs is WinUI against Gtk **on Windows**, and it is blocked until
   an app can link GtkBackend there — see step 2.
   → verify: when it runs, state for each figure whether the build was clean or
   incremental, and which configuration produced it. Report each run rather than
   a mean; the numbers here have ranged from 14s to 30 minutes depending on those
   two facts alone, and a single number hides exactly the thing being measured.

4. **Runtime comparison** — run the same P6 scenario on both. What is
   comparable: window layout, controls, file dialogs, decode throughput of the
   ffmpeg pipeline. What is **not** comparable: anything measuring the D3D11
   presentation path, which only exists under WinUIBackend.
   → verify: numbers for the comparable set only, with the excluded set named.

5. **Decide the default** — if GtkBackend wins on compile time and matches on
   the comparable runtime set, make it the Windows default explicitly rather
   than by accident of `canImport`, so the choice is visible in the source.
   → verify: the choice is written down where someone reading DefaultBackend
   can see it.

## What stays

WinUIBackend remains the baseline. It is not removed, not deprecated, and stays
buildable, because:

- it is the reference the comparison is measured against;
- P6's GPU path exists only there, and the stated intent is to patch that path
  when GPU work is required rather than to replace it;
- a fork that deletes it has no way back if the Gtk path disappoints on
  Windows.

WinUIBackend 維持為 baseline：不移除、不標記淘汰、保持可建置。理由是它是對照實驗的
基準；P6 的 GPU 路徑只存在於該處，而既定意圖是在需要 GPU 時修補該路徑而非取代它；且
若 Gtk 路徑在 Windows 上表現不如預期，刪掉它就沒有退路。

## Open questions

- Does `g_file_get_path` return usable paths for the project's Chinese
  filenames on Windows? GLib encodes paths as UTF-8 and `String(cString:)`
  reads UTF-8, so it should, but this is reasoning rather than measurement.
  The test media filename makes any encoding fault obvious.
- Does the GtkFileDialog migration behave on Windows GTK? It is verified on
  Linux under XWayland only so far.
- How does GTK 4 on Windows handle DPI scaling? The measured Windows/WSL
  difference was WinUI applying a 1.25 rasterization scale where GTK rendered
  1:1; on Windows GTK, that comparison has to be made again from scratch.
