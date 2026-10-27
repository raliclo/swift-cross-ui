# Building test apps on Windows, and stripped exes

Written 2026-10-24 from testapp/compile.zsh, commit b76c6818 (2026-10-21),
buildtime/buildtime.csv2 and testapp/platform-costs.md.

## What compile.zsh does on Windows

- **Release by default** on every platform (`BUILD_CONFIG=debug` for an
  unoptimised build). `SCUI_DEBUG` is a separate axis and defaults to 1; it
  compiles in action-file replay. Without it, replay is compiled out and an
  action file is silently ignored. `output/build-manifest.csv2` records the
  configuration of each exe, because a debug and a release exe look alike.
- **Outputs:** `testapp/output/Pn-WinUI.exe` by default, `Pn-gtk4.exe` with
  `-gtk4`. Each backend builds in its own tree (`testapp/.compile-work-winui`,
  `.compile-work-gtk4`). A shared tree makes the next default build fail with
  `missing required modules: 'CGtk', 'GtkCHelpers'`.
- There are therefore three swift-winui checkouts (`.build/checkouts` and the
  two work trees). Edit the one the exe is built from; a 2026-09-16 result was
  wrong because the edit went to another copy.
- **Stale build plan.** llbuild's cached `.build/debug.yaml` ignores files newly
  added to a path dependency's Sources/. The new file is skipped silently, or
  the link fails with `lld-link: error: undefined symbol` (2026-09-16).
  compile.zsh hashes the list of .swift/.c/.h paths and deletes
  `debug.yaml`/`release.yaml` when it changes (~1395-1475).
- **Short scratch paths.** A deep `--scratch-path` under AppData came back as
  `\\?\C:\?\C:\Users\...` and no input file opened. Keep it short.
- The console subsystem is kept on purpose: Foundation's `Process` cannot pass
  `CREATE_NO_WINDOW`, so a GUI-subsystem exe would pop a console for every
  child process (compile.zsh ~1706-1716).

## Stripped exes

Since b76c6818, compile.zsh runs `llvm-strip --strip-debug` on every Windows
exe it copies to `testapp/output/`. `SCUI_KEEP_DEBUG_INFO=1` keeps the debug
info; a missing llvm-strip is a warning only.

- Why: 223 exes held 22.6 GB and left C: with 2.5 GB free. Stripped: 11.1 GB,
  160 s in all, slowest 2.5 s. P92-WinUI.exe went 162.5 MB -> 83.7 MB and still
  launches.
- The debug info is DWARF inside the PE (no .pdb). The symbol table stays, so a
  crash still names functions but has no file and line. Keep the debug info when
  a debugger session needs lines.

## Build times (2026-08-27, Swift 6.3, not re-measured on 6.4)

| WinUI case | time |
|---|---|
| no-op build | 8.0 s |
| one-file edit | 13.5-14.3 s |
| first build after editing Sources/SwiftCrossUI | 72-111 s |
| P6 full app | 150.9 s |

A GTK-only debug P0 built in 115 s against 788 s with WinUI (2026-08-20). A
process spawn costs about 43 ms on Windows against about 2 ms on Linux, so
per-datum external tool calls are too slow; the input synthesiser runs in the
app's own process.

---

# 在 Windows 上建置測試 app,以及去除除錯資訊的 exe

2026-10-24 依 testapp/compile.zsh、b76c6818(2026-10-21)、buildtime/buildtime.csv2 與
testapp/platform-costs.md 寫成。

## compile.zsh 在 Windows 上做什麼

- 所有平台**預設 release**(未最佳化的 build 用 `BUILD_CONFIG=debug`)。`SCUI_DEBUG` 是另一條軸線，預設為 1,
  它決定動作檔重放是否編入。沒有它，重放會被編譯掉，動作檔被靜默忽略。`output/build-manifest.csv2` 記錄每個
  exe 的組態，因為 debug 與 release 的 exe 看起來一樣。
- **產物：**預設為 `testapp/output/Pn-WinUI.exe`,加 `-gtk4` 為 `Pn-gtk4.exe`。每個 backend 在自己的樹裡建置
  (`testapp/.compile-work-winui`、`.compile-work-gtk4`)。共用同一棵樹會讓下一次預設建置以
  `missing required modules: 'CGtk', 'GtkCHelpers'` 失敗。
- 因此 swift-winui 有三份 checkout(`.build/checkouts` 與兩棵工作樹)。要改 exe 實際建置所用的那一份；2026-09-16
  有一筆結果就是因為改到另一份而錯了。
- **過期的建置計畫。** llbuild 快取的 `.build/debug.yaml` 不會注意到 path 相依的 Sources/ 新增的檔案。新檔會被
  靜默略過，或在連結時以 `lld-link: error: undefined symbol` 失敗(2026-09-16)。compile.zsh 會對 .swift/.c/.h
  路徑清單取雜湊，清單改變時刪除 `debug.yaml`/`release.yaml`(約 1395–1475 行)。
- **短的 scratch 路徑。** AppData 底下很深的 `--scratch-path` 變成 `\\?\C:\?\C:\Users\...`,所有輸入檔都打不開。
  路徑要短。
- 刻意保留 console subsystem:Foundation 的 `Process` 無法傳 `CREATE_NO_WINDOW`,GUI subsystem 的 exe 每開一個
  子行程都會跳出一個 console(compile.zsh 約 1706–1716 行)。

## 去除除錯資訊的 exe

自 b76c6818 起,compile.zsh 對每個複製到 `testapp/output/` 的 Windows exe 執行 `llvm-strip --strip-debug`。
`SCUI_KEEP_DEBUG_INFO=1` 保留除錯資訊；找不到 llvm-strip 只會警告。

- 原因:223 個 exe 佔 22.6 GB,C: 只剩 2.5 GB。去除後 11.1 GB,總共 160 秒，最慢的 2.5 秒。P92-WinUI.exe 由
  162.5 MB 降為 83.7 MB,仍可啟動。
- 除錯資訊是 PE 內的 DWARF(沒有 .pdb)。符號表保留，所以當機時仍看得到函式名稱，但沒有檔案與行號。需要行號的
  除錯工作請保留除錯資訊。

## 建置時間(2026-08-27,Swift 6.3,未在 6.4 重新量測)

| WinUI 情境 | 時間 |
|---|---|
| 無變更建置 | 8.0 秒 |
| 改一個檔案 | 13.5–14.3 秒 |
| 修改 Sources/SwiftCrossUI 後的第一次建置 | 72–111 秒 |
| P6 整個 app | 150.9 秒 |

只含 GTK 的 debug P0 建置 115 秒，含 WinUI 為 788 秒(2026-08-20)。Windows 上開一個行程約 43 ms,Linux 約 2 ms,
所以每筆資料呼叫一次外部工具太慢；輸入合成器因此在 app 自己的行程內執行。
