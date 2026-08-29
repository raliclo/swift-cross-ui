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

## What each -GPU value actually selects

**Verified 2026-08-29 on this machine only** (integrated AMD Radeon plus a
discrete NVIDIA adapter). Re-measure with
`zsh testapp/gpu_flag_test.zsh --no-build` before quoting the renderer column
anywhere else — see the caveat below the table.

| invocation | renderer GTK realizes | what the flag did |
|---|---|---|
| *(no flag)* | `GskCairoRenderer` | nothing — the platform default |
| `-GPU 0` | `GskCairoRenderer` | asked for software explicitly |
| `-GPU 1` | `GskCairoRenderer` | asked for the system default adapter |
| `-GPU 2 -y` | `GskGLRenderer` | enabled Direct Composition, so GL can realize |

What the test actually asserts, which is narrower than the table: rows 1-3
by renderer name (row 3 *relatively*, as "equal to row 1"), and row 4 by
`GpuPreference=2` in the registry plus the relaunched process reporting the
NVIDIA adapter. The `GskGLRenderer` in row 4 is an observation from that run,
not an assertion the test would fail on.

Three of the four rows say `GskCairoRenderer`, and they say it for three
different reasons. Cairo is **this machine's** answer to `-GPU 1`, not the
definition of `-GPU 1`: without Direct Composition, GTK on Windows cannot
realize `GskGLRenderer` at all, so the default and the explicit software request
land on the same renderer here. On a machine where GL realizes unaided they
would not. See [FAQ.md](../FAQ.md) for why the pairing is DComp/renderer rather
than Cairo/DComp.

`-y` answers the restart prompt yes. `-GPU N` for N ≥ 2 writes the Windows
`UserGpuPreferences` policy, which is fixed at process creation, so the process
must relaunch to take effect; without `-y` it asks first.

## The rule is the requirement, not the renderer

**Every GtkBackend configuration must keep action files and screenshots
working.** That is the invariant. It is deliberately *not* stated as "use
Cairo" or "use Vulkan" or "never use Direct Composition" — a rule naming a
renderer would be a rule about the wrong thing, and it would have to be
rewritten on every platform where the renderers differ. A run whose result
cannot be checked is not a run; which renderer produced it is a detail.

Renderer choices then follow as consequences, and they differ per platform:

- **Windows.** Direct Composition breaks *window* capture, so it is off by
  default and reachable only through the explicit `-GPU 2` opt-in. It was
  briefly the default (the threshold read `>= 1`) and broke window capture for
  every GTK app at once; `>= 2` is the fix. Nothing in the test suite may depend
  on `-GPU 2`. Re-measured 2026-08-29 as a single-variable experiment on P40,
  both arms confirmed with `GSK_DEBUG=renderer` before capturing:

  | run | renderer | `screenshot.zsh -w` |
  |---|---|---|
  | default | `GskCairoRenderer` | **priority 1, window** |
  | `SCUI_GTK_DCOMP=1` | `GskGLRenderer` | priority 2, desktop |

  `screenshot.zsh` is not malfunctioning: window capture goes through ffmpeg's
  gdigrab, which is GDI/BitBlt, and falling back to the desktop is its designed
  response to a capture it cannot make.

  > **Refuted the same day, and worth keeping because it is the exact
  > over-generalisation the script's own header warns about.** This paragraph
  > first read "GDI cannot see D3D or DirectComposition content, this is a
  > property of Windows". **P6 is a counterexample.** It presents through
  > `IDXGIFactory2::CreateSwapChainForComposition`
  > (`D3D11VideoInterop.swift:370`) — a composition swapchain, the same category
  > as GTK's DComp path — and it captures at **priority 1**, window, measured
  > 2026-08-29. So "D3D content is uncapturable" is false, and so is "DComp
  > content is uncapturable". The header of `screenshot.zsh` already recorded
  > that the earlier form of this claim had been over-generalised into "never
  > capture a window"; the claim was then over-generalised again, in a document,
  > by someone who had read that header the same afternoon.

  **So the exclusivity is not established, and the real cause is open.** Two
  windows, both presenting a composition swapchain, and only one is capturable:

  | app | presents via | capture |
  |---|---|---|
  | P6 (WinUIBackend) | `CreateSwapChainForComposition` | **priority 1, window** |
  | P40 (GTK + DComp) | GDK's Win32 DComp path | priority 2, desktop |

  **Cause confirmed 2026-08-29 by reading `GWL_EXSTYLE` on both live windows.**
  It is the extended window style, not the swapchain:

      P6  (captures)      exstyle 0x00000100   WS_EX_WINDOWEDGE only
      P40 + DComp (fails) exstyle 0x00200000   WS_EX_NOREDIRECTIONBITMAP

  A window with `WS_EX_NOREDIRECTIONBITMAP` has no redirection surface, so
  BitBlt has nothing to copy. GDK's Win32 DComp path sets it at creation; WinUI's
  HWND does not, and DWM composes P6's swapchain into its redirection surface,
  which is why a composition swapchain is captured perfectly there.

  It cannot be cleared afterwards. `SetWindowLongPtrW` on the live window returns
  0 and sets `GetLastError` to 87, `ERROR_INVALID_PARAMETER` — it is a
  creation-time style, as documented, and now measured rather than assumed.

  **But the capture is not lost, only the method is wrong.**
  `PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT)` asks DWM to render the window
  instead of copying a surface, and it captures the DComp GTK window at full
  fidelity — 93.0% of pixels non-black, and the saved image shows the complete
  window: chrome, headings, every tile, both text samples. Measured with a
  black-pixel count built into the tool, because `PrintWindow` returns TRUE while
  producing an entirely black bitmap and that is precisely the failure this
  investigation kept meeting.

  So the Windows constraint is **a limitation of gdigrab, not of Direct
  Composition**, and giving `screenshot.zsh` a `PrintWindow` path removes it.
  That in turn makes `-GPU 2` viable as a default: hardware renderer, transforms,
  and a capturable window at the same time.
- **WSL.** Window capture fails there *whatever* the renderer — measured
  2026-08-29 by forcing `GSK_RENDERER=cairo`, confirming with `GSK_DEBUG=renderer`
  that `GskCairoRenderer` really was in use, and getting the same
  `priority 1 failed` fallback as the default `GskVulkanRenderer` gives. So it
  is a WSLg property, not a renderer's fault, and the invariant is met by the
  desktop capture instead. Renderer choice on WSL is therefore free.

Which also settles a question that was open: desktop capture is a legitimate way
to satisfy the invariant, because it is already how every WSL run is verified.
What it cannot do is serve as the control in a *pixel-diff* comparison between
two runs — two desktop captures differ by 10-22% no matter what changed, because
the window lands in a different place and the clock has moved. Verifying an
action file and diffing two renderings are different jobs with different
requirements.

**規則定在需求上，不定在繪製器上。** 不變條件是：**每一種 GtkBackend 組態都必須讓 action
file 與截圖可用。** 刻意**不**寫成「用 Cairo」或「用 Vulkan」或「絕不使用 Direct
Composition」——指名繪製器的規則管的是錯的東西，而且在每個繪製器不同的平台上都得重寫一次。
一次無法被檢查的執行不算執行；至於是哪個繪製器畫的，那是細節。

繪製器的選擇因此是**結果**，而且每個平台不同：

- **Windows。** Direct Composition 會讓**視窗**擷取失效，因此預設關閉，只能透過明確的
  `-GPU 2` 取得。它曾短暫是預設（門檻寫成 `>= 1`），一次打斷所有 GTK app 的視窗擷取；
  `>= 2` 就是修正。測試套件中不得有任何東西依賴 `-GPU 2`。
- **WSL。** 那裡的視窗擷取**無論用哪個繪製器都會失敗**——2026-08-29 以
  `GSK_RENDERER=cairo` 強制、並用 `GSK_DEBUG=renderer` 確認確實是 `GskCairoRenderer` 在跑，
  得到與預設 `GskVulkanRenderer` 相同的 `priority 1 failed` 回退。因此那是 WSLg 的性質，
  不是繪製器的錯，而不變條件改由桌面擷取滿足。所以 WSL 上的繪製器選擇是自由的。

這順帶了結了一個懸而未決的問題：桌面擷取是滿足該不變條件的**正當**方式，因為每一次 WSL 執行
本來就是這樣驗證的。它做不到的是充當兩次執行之間**像素比對**的對照組——兩張桌面截圖無論改了
什麼都會差 10 至 22%，因為視窗落點不同、時鐘也在走。驗證一份 action file 與比對兩次繪製結果，
是兩件需求不同的工作。

**WSL is the platform that draws transforms with no hotpink, and it already is
by default.** Measured 2026-08-29:

| platform | default renderer | transform nodes | hotpink in P40 |
|---|---|---|---|
| Windows, `/c/gtk4` | `GskCairoRenderer` | not drawn | 47 873 |
| Windows, `-GPU 2` | `GskGLRenderer` | drawn | 0 |
| WSL, WSLg | `GskVulkanRenderer` (llvmpipe) | drawn | **0** |

The WSL row was verified by capture, not by reasoning: all seven P40 tiles —
offset, both scales, both rotations and the shear — render correctly, and a
pixel count over the capture finds zero hotpink. Cairo is never selected there.

**Windows cannot be made to match, with this GTK build.** `GSK_RENDERER=vulkan`
looks like it should be the answer and is silently ignored: it still tries
`GskGLRenderer`, fails on Direct Composition, and lands on Cairo. Ask GTK
itself, which is the only source that settles it:

    $ GSK_RENDERER=help ./P40.exe
    Supported arguments for GSK_RENDERER environment variable:
      broadway - Disabled during GTK build
         cairo - Use the Cairo fallback renderer
        opengl - Use the OpenGL renderer
            gl - Use the OpenGL renderer
        vulkan - Disabled during GTK build
          help - Print this help

The cause is upstream of us and is a one-line build decision. `/c/gtk4` is a
[gvsbuild](https://github.com/wingtk/gvsbuild) install (MSVC, `gtk-4-1.dll`,
`.lib` import libraries), and gvsbuild's GTK 4 recipe passes **`-Dvulkan=disabled`**
with no vulkan or shaderc dependency. MSYS2's `mingw-w64-gtk4`, at the **same
4.22.4**, passes `-Dvulkan=enabled` with `vulkan-headers` and `shaderc` to build
and `vulkan-loader` to run.

Both DLLs' import tables agree with their recipes — measured 2026-08-29, each
run with `GskCairoRenderer` as the control that proves `strings` can read the
file at all:

| build | file | imports `vulkan-1.dll` | imports `OPENGL32.dll` |
|---|---|---|---|
| gvsbuild `/c/gtk4` | `gtk-4-1.dll` | no | yes |
| MSYS2 ucrt64 | `libgtk-4-1.dll` | **yes** | yes |

Both import `api-ms-win-crt-*`, so both are UCRT — take the **ucrt64** MSYS2
packages, never `mingw64`, which is msvcrt and would put two C runtimes in one
process. And nothing in this repo hardcodes a GTK DLL name: `Package.swift` uses
`pkgConfig: "gtk4"`, so the switch is a `PKG_CONFIG_PATH` and a set of MSVC
import libraries generated from the DLLs, not a source change.

> **A wrong measurement, kept because the shape of it recurs.** The first
> attempt at this concluded "the DLL contains zero `GskVulkan` symbols and does
> not import `vulkan-1.dll`" — and reached the right verdict for a reason that
> was entirely false. It ran `strings` and `objdump -p` against
> `libgtk-4-1.dll`, the MinGW name; this is an MSVC build and the file is
> `gtk-4-1.dll`. Both tools reported nothing for a file that does not exist, and
> nothing was read as zero. The real DLL does contain `GskVulkanRenderer`. The
> control that would have caught it in one line: grep for `GskCairoRenderer`
> first, which the runtime demonstrably prints, and stop if that is also zero.

So on Windows there are exactly two states — Cairo with hotpink, or DComp plus
GL with no hotpink and no window capture — and no third one to pick. A GTK 4
Windows build with `-Dvulkan=enabled` would create one, and is the only route to
"never Cairo" on Windows that does not also cost window capture.

**Refuted 2026-08-29, before any of that work was done.** The MSYS2 package was
downloaded and its own `gtk4-demo.exe` run directly — no repackaging, no import
libraries, no rebuild. GTK's Win32 backend asks Vulkan for exactly what it asks
OpenGL for:

    Failed to realize renderer 'GskVulkanRenderer' for surface 'GdkWin32Toplevel':
        Vulkan requires Direct Composition

So a Vulkan-enabled GTK does **not** produce a DComp-free hardware renderer on
Windows, and the whole route is dead. Worse, the two builds are missing opposite
halves — measured with `GDK_DEBUG=help`, whose output was checked to be
non-empty first (28 flags listed, including `opengl` and `vulkan`):

| build | Vulkan renderer compiled in | `dcomp` in `GDK_DEBUG` |
|---|---|---|
| gvsbuild `/c/gtk4` | no | **yes** |
| MSYS2 ucrt64 | **yes** | no |

MSYS2 has the renderer and no switch to enable the compositing it requires, so
switching to it would lose the `-GPU 2` escape hatch and gain nothing. Keep
gvsbuild.

**What this settles, and what it does not.** Settled: no choice of GTK build
gives a hardware renderer on Windows without Direct Composition. That is a
property of GDK's Win32 backend, not of a build option, and the Vulkan route is
closed.

**Not settled: whether a DComp-composited GTK window is capturable.** The
earlier claim that it is inherently not is refuted by P6 — see the table above.
Until `GWL_EXSTYLE` has been read on both windows, "transforms or capture, pick
one" is a hypothesis, not a finding, and the decisions below are provisional on
it. If the redirection-bitmap theory holds and can be changed, the whole problem
dissolves; if it does not, the remaining options are about declining well:
detect `GskCairoRenderer` at runtime and refuse `setGeometricEffect` explicitly
rather than emit hotpink, accept `-GPU 2` plus desktop capture for transform
tests specifically, or route transforms through WinUIBackend, which has its own
renderer and none of this.

Do not reach for DComp to make a transform render correctly; fix the transform,
or record the gap. `SCUI_GTK_DCOMP=1` also still forces it on, kept only as the
reproduction for the upstream GTK report in
[bugs/Gtk4-bugs.md](../../bugs/Gtk4-bugs.md).

**僅在本機驗證，2026-08-29**（AMD Radeon，透過原生 WGL 的 GL 4.6）。以
`zsh testapp/gpu_flag_test.zsh` 重新產生——該腳本斷言的是上表的**關係**，不是這些
名字；在別處引用「繪製器」那一欄之前請重新量測。

四列裡有三列寫著 `GskCairoRenderer`，而這三列的理由各不相同。Cairo 是**這台機器**對
`-GPU 1` 的答案，不是 `-GPU 1` 的定義：沒有 Direct Composition，Windows 上的 GTK 根本
無法實現 `GskGLRenderer`，於是「預設」與「明確要求軟體」在此落到同一個繪製器上；在一台
GL 能自行實現的機器上則不會。

`-y` 代表把重啟提示回答為 yes。`-GPU N`（N ≥ 2）會寫入 Windows 的 `UserGpuPreferences`
政策，該政策在行程建立時就固定，因此必須重啟行程才會生效；未給 `-y` 時會先詢問。

**2026-08-29 定案：除了明確指定 `-GPU 2` 之外，不使用 Direct Composition。** 經 DComp
合成的視窗無法以視窗方式截圖——`screenshot.zsh -w` 會退回擷取桌面——而每一份 action file
都是靠截圖驗證的。一次無法被檢查的執行，不算執行。DComp 曾短暫是預設（門檻寫成 `>= 1`），
一次打斷了所有 GTK app 的視窗截圖；`>= 2` 就是修正。

**能畫出變換且不出現 hotpink 的平台是 WSL，而且它預設就已經是了。** 2026-08-29 實測：

| 平台 | 預設繪製器 | transform node | P40 的 hotpink |
|---|---|---|---|
| Windows，`/c/gtk4` | `GskCairoRenderer` | 畫不出 | 47 873 |
| Windows，`-GPU 2` | `GskGLRenderer` | 畫得出 | 0 |
| WSL，WSLg | `GskVulkanRenderer`（llvmpipe） | 畫得出 | **0** |

WSL 那一列是以截圖驗證、而非推論得出：P40 的七個 tile——offset、兩種 scale、兩種 rotate
與 shear——全部正確繪製，對整張截圖計數 hotpink 為 0。該平台從不選用 Cairo。

**以目前這份 GTK build，Windows 無法比照辦理。** `GSK_RENDERER=vulkan` 看起來像是解答，
實際上被無聲忽略：它仍然去嘗試 `GskGLRenderer`，在 Direct Composition 上失敗，最後落到
Cairo。去問 GTK 自己，那是唯一能了結此事的來源：

    $ GSK_RENDERER=help ./P40.exe
        vulkan - Disabled during GTK build

成因在我們的上游，而且只是一行 build 決策。`/c/gtk4` 是一份
[gvsbuild](https://github.com/wingtk/gvsbuild) 安裝（MSVC、`gtk-4-1.dll`、`.lib` 匯入
程式庫），而 gvsbuild 的 GTK 4 配方傳的是 **`-Dvulkan=disabled`**，且未列任何 vulkan 或
shaderc 相依。MSYS2 的 `mingw-w64-gtk4` 在**同樣的 4.22.4** 版本上傳的是
`-Dvulkan=enabled`，build 期需要 `vulkan-headers` 與 `shaderc`，執行期需要 `vulkan-loader`。

> **一次錯誤的量測，記錄於此是因為它的形狀會重複出現。** 第一次嘗試得出的結論是「該 DLL 內
> `GskVulkan` 符號為零，且未匯入 `vulkan-1.dll`」——結論方向正確，理由卻完全是假的。它對
> `libgtk-4-1.dll`（MinGW 的命名）執行 `strings` 與 `objdump -p`；但這是 MSVC build，檔名是
> `gtk-4-1.dll`。兩個工具對一個不存在的檔案都回報了「沒有」，而「沒有」被讀成了「零」。真正
> 的 DLL 裡確實含有 `GskVulkanRenderer`。一行就能攔下它的對照組：先 grep `GskCairoRenderer`
> ——那是執行期明確會印出來的字串——若它也是零，就該停手。

因此 Windows 上只有兩種狀態——Cairo 帶 hotpink，或 DComp 加 GL、無 hotpink 但無法視窗
截圖——沒有第三種可選。一份 `-Dvulkan=enabled` 的 GTK 4 Windows build 會造出第三種，而那是
「Windows 上永不使用 Cairo」且不必賠上視窗截圖的唯一路徑。

**2026-08-29 推翻，而且是在動手做那些工作之前。** 直接下載 MSYS2 套件並執行它自帶的
`gtk4-demo.exe`——不重新打包、不做 import library、不重新建置。GTK 的 Win32 backend 對
Vulkan 的要求，與它對 OpenGL 的要求完全相同：

    Failed to realize renderer 'GskVulkanRenderer' for surface 'GdkWin32Toplevel':
        Vulkan requires Direct Composition

因此啟用 Vulkan 的 GTK **並不會**在 Windows 上產生一個不需 DComp 的硬體繪製器，整條路線就此
斷絕。更糟的是，兩份 build 各缺一半——以 `GDK_DEBUG=help` 量測，並且先確認其輸出非空
（列出 28 個 flag，其中包含 `opengl` 與 `vulkan`）：

| build | 編入 Vulkan 繪製器 | `GDK_DEBUG` 有 `dcomp` |
|---|---|---|
| gvsbuild `/c/gtk4` | 無 | **有** |
| MSYS2 ucrt64 | **有** | 無 |

MSYS2 有那個繪製器，卻沒有能啟用其所需合成方式的開關，因此換過去會失去 `-GPU 2` 這條退路，
而且一無所得。維持 gvsbuild。

**這件事因此定案。** 在 Windows 的 GTK 4 上，「畫得出變換」與「視窗可被擷取」兩者互斥，而且
換任何 GTK build 都改變不了——那是 GDK Win32 backend 的性質，不是某個 build 選項的後果。
剩下的選項全都是關於「如何體面地拒絕」：在執行期偵測到 `GskCairoRenderer` 就明確拒絕
`setGeometricEffect`，而不是吐出 hotpink；或針對變換測試接受 `-GPU 2` 加上桌面擷取；
或把變換交給 WinUIBackend——它有自己的繪製器，完全沒有這些問題。

不要為了讓某個變換正確繪製而搬出
DComp——去修那個變換，或把落差記錄下來。`SCUI_GTK_DCOMP=1` 仍可強制開啟，保留的唯一理由是
它是 [bugs/Gtk4-bugs.md](../../bugs/Gtk4-bugs.md) 中那份上游 GTK 回報的重現方式。

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
