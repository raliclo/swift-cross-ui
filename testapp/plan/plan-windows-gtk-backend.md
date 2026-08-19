# Windows: GtkBackend alongside WinUIBackend

Evaluating GtkBackend as the Windows default, with WinUIBackend kept as the
baseline. Nothing is removed by this plan.

在 Windows 上評估以 GtkBackend 作為預設，並保留 WinUIBackend 作為 baseline。本計畫
不移除任何既有實作。

## Why

Compile time, measured on this machine during the P6 work:

| Build | Backend | Time |
|---|---|---|
| P6 on Windows | WinUIBackend (+ swift-winui, WinAppSDK) | 95s, 103s |
| P6 in WSL | GtkBackend | 13s, 16s, 18s, 20s, 22s |

Roughly a 5x difference, and the cost is WinAppSDK, not the app. That is a
developer-experience problem rather than a runtime one, which is worth stating
plainly because it changes what the comparison below has to prove.

編譯時間，取自 P6 工作期間於本機的實測（如上表）。差距約 5 倍，成本來自 WinAppSDK 而
非 app 本身。這是開發體驗問題而非執行期問題，必須先講明，因為它決定了下方對照實驗要
證明什麼。

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

3. **Compile-time comparison** — build P6 three times each way from clean:
   WinUIBackend (baseline) and GtkBackend. Report each run, not just a mean;
   the WSL numbers above varied between 13s and 49s depending on how much was
   already built, and a single number would hide that.
   → verify: three runs recorded per configuration, with whether the build was
   incremental or clean stated for each.

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
