# Windows: GtkBackend alongside WinUIBackend

Evaluating GtkBackend as the Windows default, with WinUIBackend kept as the
baseline. Nothing is removed by this plan.

在 Windows 上評估以 GtkBackend 作為預設，並保留 WinUIBackend 作為 baseline。本計畫
不移除任何既有實作。

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

`DefaultBackend` already prefers Gtk over WinUI:

```swift
#if canImport(AppKitBackend)      → AppKitBackend
#elseif canImport(GtkBackend)     → GtkBackend
#elseif canImport(WinUIBackend)   → WinUIBackend
```

So installing GTK 4 on Windows switches the default with no source change. That
is convenient and also the risk: it switches silently.

P6 carries 35 `#if os(Windows)` blocks that assume WinUIBackend — the D3D11
video interop, the SwapChainPanel, the NV12 presentation path. Those are
compiled on `os(Windows)`, not on which backend is active, so after the switch
they would still compile while the backend underneath them changed. This is the
part of the plan most likely to produce a confusing failure.

`DefaultBackend` 本來就把 Gtk 排在 WinUI 之前，因此在 Windows 安裝 GTK 4 即可切換預設，
無需改動原始碼。方便，同時也是風險——它是靜默切換的。P6 有 35 個 `#if os(Windows)`
區塊假設 WinUIBackend（D3D11 video interop、SwapChainPanel、NV12 呈現路徑）。這些以
`os(Windows)` 為條件，而非以「哪個 backend 生效」為條件，因此切換後它們仍會被編譯，
底下的 backend 卻已改變。這是本計畫最可能產生費解失敗的地方。

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
