# mac

`P28-hit-testing.csv` is verified for the macOS AppKit runner. Run it with:

```zsh
zsh testapp/test.zsh P28 --macos --actionfile
```

The `platform` column is `macos`; it must not be replayed against GTK or
WinUI. The measured result is `underlying button clicked count=1` in
`testapp/output/p28-debug-events.log`.

A file appears here only after it has been run here and seen to work. An empty
folder is an honest gap; a copy of another platform's file would be a claim
nobody checked.

`P28-hit-testing.csv` 已針對 macOS AppKit runner 驗證。請使用以下指令執行：

```zsh
zsh testapp/test.zsh P28 --macos --actionfile
```

`platform` 欄位為 `macos`，不可拿到 GTK 或 WinUI replay。量測結果是
`testapp/output/p28-debug-events.log` 中的 `underlying button clicked count=1`。

檔案唯有在此平台實際執行過並確認可運作之後才會出現於此。空資料夾是誠實的缺口；而從其他平台複製
過來的檔案，則是一項無人查證過的主張。
