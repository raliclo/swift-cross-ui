# Verification follow-up / 驗證後續

## Diagnostics / 診斷

WinUI WebView informational diagnostics now require `--debug` or
`SCUI_DEBUG_WEBVIEW=1`. The COM initialization probe also runs only in diagnostic
mode; the application startup apartment selection is unchanged. Actual failures
remain visible. P38 release build succeeded. `output/p38-normal.log` is empty;
`output/p38-debug.log` includes apartment readings and browser-process completion.
Both executions exited with code 1, so these logs verify the switch, not a full
navigation or shutdown regression pass.

一般執行不再輸出 WebView 診斷；使用 `--debug` 或 `SCUI_DEBUG_WEBVIEW=1` 才開啟。
P38 release 編譯通過，正常 log 為空，debug log 有 COM 與 browser process started。
兩次結束碼皆為 1，僅確認日誌開關，不能據此聲稱完整 GUI 回歸通過。

## External Accessibility / 外部無障礙驗證

WSLg was tested first. Installed `python3-pyatspi`, built P69 release in
`/home/lowei/proj/swift-cross-ui`, and held it open for 30 seconds on a private
D-Bus session. The external AT-SPI client selects the app by process ID, not title.

```zsh
cd /home/lowei/proj/swift-cross-ui/testapp/output
dbus-run-session -- zsh ../test_support/measure/p69_atspi.zsh "$PWD/P69"
```

Evidence: `testapp/output/p69-atspi-external.log` on Windows. Results:

- The content button is named `Close` (not the window-decoration Close button).
- `Delete` has description `Removes the file permanently`.
- `Volume` exposes `valuetext:40 percent`. Buttons need not implement AT-SPI Value;
  requiring that interface alone was an incorrect first probe assertion.
- `decorative` is absent.
- **FAIL: the original child label `X` remains in the external tree.** The probe
  returns 1. Whether a particular screen reader announces that child still needs
  a screen-reader traversal, but P69's explicit absence assertion does not pass.

Windows P69-WinUI was then inspected through an external UI Automation client.
The returned tree includes `button Close / text X`, a button with description
`Removes the file permanently`, `text Volume`, and `text decorative`.
This client does not expose ItemStatus or identify its UIA tree filter, so neither
the value nor Narrator hidden-subtree behavior is established by that output.
**Narrator speech was not verified. Do not mark #123 externally complete.**

先 WSLg 再 Windows。AT-SPI 已取得外部證據：label、hint、value 與 decorative 隱藏
符合，但 `X` 子節點仍存在，探針因此失敗。Windows 外部樹也看見 `X` 與 `decorative`，
但工具未說明 UIA filter 且未輸出 ItemStatus，不能直接等同 Narrator 會朗讀。
下一步是驗證 control/content view 與 Narrator 實際走訪，再修正重複標籤或隱藏子樹行為。

## Local Commit Split / 本機提交拆分

Published develop history was NOT rewritten. Local branch `review/split-5739d453`
starts at `1a69075f` and replaces the mixed commit with:

- `c0d82a90`: source only (#117).
- `34de131a`: P57 test app, loader and action files.
- `a8ff41c8`: documentation.

Separate local branch `review/p65-from-5739d453` adds `78af6784` for P65 only.
Its final tree is byte-identical to `5739d453` (`git diff --exit-code` passed).
The #117 branch does not contain the P65 addition. These are historical split
commits, not the later P57 fixes; do not mistake this branch for current develop.
Worktree: `../swift-cross-ui-split-5739d453`.

僅整理本機分支，未建立 PR、未 push、未強推。develop 原歷史不變；P65 已獨立，
source、P57 測試、文件各自一個 commit。若日後使用，仍需選取後續修正，不能把此歷史
拆分分支當成最新 develop。
