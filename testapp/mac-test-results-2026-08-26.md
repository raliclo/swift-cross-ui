# macOS test results — 2026-08-26

## Scope

P6 and P6-v2 were deliberately excluded. The remaining macOS targets were
built with:

```sh
BUILD_CONFIG=debug zsh testapp/compile.zsh P0 P1 P10 P11 P12 P13 P15 P16 P17 P18 P19 P2 P20 P21 P22 P23 P24 P25 P26 P27 P28 P29 P3 P37 P4 P5 P7 P8 P9
```

Result: all targets completed successfully. P8 emitted two existing
`ForEach` deprecation warnings; no target failed to compile.

P28 was then built independently and completed successfully. This is the
first compile evidence for the AppKit changes introduced by the hit-testing
implementation.

## P28 measurement

Running `./testapp/output/P28 --debug` produced:

```text
P28 2026-08-26 14:07:56 +0000 RENDER COMPLETE -- P28 ready for hit-testing checks
```

The automated click step could not be completed because macOS denied
System Events assistive access:

```text
System Events got an error: osascript is not allowed assistive access. (-1719)
```

Therefore the AppKit code is compile-verified and the P28 view is launch/log
verified, but the click-through behaviour still needs one manual click or a
machine-level Accessibility permission before it can be marked passed. The
expected successful log entry is:

```text
underlying button clicked count=1
```

## 結果

### 範圍

刻意排除 P6 與 P6-v2。其餘 macOS targets 使用上述 `compile.zsh` 指令以
`BUILD_CONFIG=debug` 建置。

結果：所有 targets 均成功完成。P8 有兩個既有的 `ForEach` deprecation
warning；沒有 target 編譯失敗。

P28 另外獨立建置並成功完成，這是本次 AppKit hit-testing 實作首次取得的
編譯證據。

### P28 量測

執行 `./testapp/output/P28 --debug` 已產生 `RENDER COMPLETE`。自動點擊步驟
因 macOS 拒絕 System Events assistive access 而無法完成，因此目前只能標記為
「編譯驗證與啟動／log 驗證成功」，不能標記 click-through 行為已通過。

取得 Accessibility 權限後，應確認 log 出現：

```text
underlying button clicked count=1
```
