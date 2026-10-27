# Swift toolchain on Windows

Written 2026-10-24 from commits 185abee1, 0836e0cf, b76c6818, testapp/compile.zsh
and matrix_coverage/results.csv2 (windows rows of 2026-10-12 to 2026-10-23).

## What

- **Swift 6.4.1** on Windows and in WSL, by rule since 2026-10-23 (0836e0cf).
  results.csv2 rows read 6.4.1 from 2026-10-19; a few rows of that day still
  read 6.4.0. Android stays on 6.4.0 with NDK r30.
- 6.3.3 was replaced by 6.4.0 on 2026-10-12 (185abee1). The 6.3.3 and 6.4
  runtimes are not interchangeable: an exe built by one dies at launch under the
  other's DLLs with **0xC0000139** (entry point not found).
- No script in the repo installs the Windows toolchain (no winget, Swiftly or
  SDKROOT logic). `compile.zsh` runs `${SWIFT_BIN:-swift}`.
- 6.4.0 reports itself as `Swift version 6.4 (swift-6.4-RELEASE)`. A version
  check must drop a trailing `.0`, or it reinstalls every time.

## What 6.4's build system changed

Swift 6.4 builds with swiftbuild. Two changes broke the Windows build once and
can come back:

1. **Platform-conditioned dependencies are compiled anyway.** A WinUI build
   compiled GtkCHelpers and failed on `gtk/gtk.h not found`. Package.swift now
   has a separate `#elseif os(Windows)` branch (Package.swift:135-150).
2. **Products moved** to `.build/out/Products/<Config>-<platform>/`. The old
   path guess copied a stale 6.3.3 exe, which then died with 0xC0000139.
   compile.zsh now asks `swift build --show-bin-path`, for the exe and for
   `swift-winui_CWinAppSDK.resources` (compile.zsh ~2066-2150).

Android still uses the `native` build system, because swiftbuild rejects
swift-java.

## Other facts

- WinUIBackend cannot be compiled on macOS or in WSL: CWinRT needs
  `wtypesbase.h`. Code written on the Mac reaches Windows uncompiled, and the
  first Windows build has repeatedly failed on Swift 6 concurrency diagnostics
  (66725261, 14b19d39) or a missing import (fece8661). No compiler crash (ICE)
  is recorded on Windows.
- WinUIBackend is in Swift 6 language mode since 5674f3ce (2026-08-27).
- On WSL, bare `swift test` fails for the same reason; use
  `SCUI_HOST_BACKENDS_ONLY=1` (Package.swift:61-111).

## How to apply

After a toolchain change, rebuild every exe in `testapp/output/` before
comparing anything: a leftover exe from the old toolchain fails to start, and
the failure looks like an app bug.

---

# Windows 上的 Swift toolchain

2026-10-24 依 185abee1、0836e0cf、b76c6818、testapp/compile.zsh 與 matrix_coverage/results.csv2
(2026-10-12 至 2026-10-23 的 windows 列)寫成。

## 內容

- Windows 與 WSL 皆用 **Swift 6.4.1**,自 2026-10-23 起為規定(0836e0cf)。results.csv2 自 2026-10-19 起記為
  6.4.1,當天仍有少數列記為 6.4.0。Android 維持 6.4.0 搭配 NDK r30。
- 2026-10-12 由 6.3.3 換成 6.4.0(185abee1)。6.3.3 與 6.4 的 runtime 不能互換：其中一版建出的 exe 在另一版的
  DLL 下啟動即以 **0xC0000139**(找不到進入點)結束。
- repo 裡沒有任何腳本安裝 Windows toolchain(沒有 winget、Swiftly 或 SDKROOT 的處理)。`compile.zsh` 執行
  `${SWIFT_BIN:-swift}`。
- 6.4.0 自稱 `Swift version 6.4 (swift-6.4-RELEASE)`。版本比對必須去掉結尾的 `.0`,否則每次都會重新安裝。

## 6.4 的建置系統改變了什麼

Swift 6.4 以 swiftbuild 建置。有兩項改變曾讓 Windows 建置壞掉，且可能再發生:

1. **帶平台條件的相依仍會被編譯。** WinUI 建置去編譯了 GtkCHelpers,因 `gtk/gtk.h not found` 失敗。
   Package.swift 現在有獨立的 `#elseif os(Windows)` 分支(Package.swift:135-150)。
2. **產物搬到** `.build/out/Products/<Config>-<platform>/`。舊的路徑推測複製到過期的 6.3.3 exe,啟動即以
   0xC0000139 結束。compile.zsh 現在改問 `swift build --show-bin-path`,exe 與
   `swift-winui_CWinAppSDK.resources` 都是(compile.zsh 約 2066–2150 行)。

Android 仍用 `native` 建置系統，因為 swiftbuild 不接受 swift-java。

## 其他事實

- WinUIBackend 無法在 macOS 或 WSL 上編譯:CWinRT 需要 `wtypesbase.h`。在 Mac 上寫的程式碼送到 Windows 時
  未經編譯，第一次 Windows 建置一再因 Swift 6 並行診斷(66725261、14b19d39)或缺少 import(fece8661)
  失敗。Windows 上沒有編譯器當機(ICE)的紀錄。
- WinUIBackend 自 5674f3ce(2026-08-27)起採 Swift 6 語言模式。
- 在 WSL 上直接 `swift test` 也因同樣原因失敗；請用 `SCUI_HOST_BACKENDS_ONLY=1`(Package.swift:61-111)。

## 如何運用

換 toolchain 之後，比較任何東西之前先重建 `testapp/output/` 裡的每個 exe:舊 toolchain 留下的 exe 會啟動失敗，
而那個失敗看起來像 app 的錯誤。
