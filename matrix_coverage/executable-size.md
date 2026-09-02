# Executable size per platform

`executable-size.csv2` records how large each test app builds on each platform
and backend. Read and write it with `csv2` — it has two header rows and the note
column contains commas.

`executable-size.csv2` 記錄每一支測試 app 在各平台、各 backend 下建置出來的大小。請以 `csv2`
讀寫——它有兩列表頭，且備註欄含有逗號。

## Why Windows has two columns

On Windows the same app builds against either backend, and the two differ by
about **3x**: roughly 56 MB for `-gtk4`, 178 MB for WinUI. That gap is the
measured reason `compile.zsh -gtk4` removes the WinUI products from the package
rather than only redirecting `DefaultBackend` — with the products still listed
the build compiled 73 extra WinUI steps and produced a 342 MB binary while
still running on GtkBackend, which is the switch without either saving.

The executables are named `<app>-gtk4.exe` and `<app>-WinUI.exe` for the same
reason a column is not enough: a capture matched by window title photographed
the wrong backend's window on 2026-09-02, and the two files were
indistinguishable once copied side by side.

Windows 之所以有兩欄：同一支 app 可對兩個 backend 各建一次，而兩者相差約 **3 倍**——`-gtk4` 約
56 MB，WinUI 約 178 MB。那個差距正是 `compile.zsh -gtk4` 選擇把 WinUI product 整組移出套件、而非
僅重新導向 `DefaultBackend` 的實測理由：product 仍列出時，建置多編了 73 個 WinUI 步驟、產生 342 MB
的執行檔，而 app 仍跑在 GtkBackend 上——切換達成了，兩項效益一項也沒有。

## Regenerating the numbers

Sizes are bytes, from `stat -c %s`. They change with every toolchain or library
change, so **re-measure rather than trust a row older than a week**.

```zsh
# Windows, both backends
cd testapp && SCUI_DEBUG=1 zsh compile.zsh          # -> <app>-WinUI.exe
cd testapp && SCUI_DEBUG=1 zsh compile.zsh -gtk4    # -> <app>-gtk4.exe
cd testapp/output && for f in P*-gtk4.exe P*-WinUI.exe; do
    printf '%s\t%s\n' "$f" "$(stat -c %s "$f")"
done

# Linux, in the WSL checkout
wsl.exe -d Ubuntu -- bash /tmp/lxsizes.sh
```

`lxsizes.sh` must be run as a **file**. A `find -printf '%f|%s\n'` passed on a
quoted `wsl.exe` command line comes back empty — the format string does not
survive the trip, and the failure is silent output rather than an error.

`lxsizes.sh` 必須以**檔案**形式執行。把 `find -printf '%f|%s\n'` 放在帶引號的 `wsl.exe` 命令列上
會得到空的輸出——格式字串無法通過那一段，而且失敗的形式是「沒有輸出」而不是錯誤。

## Averages

```zsh
csv2 -r -i matrix_coverage/executable-size.csv2 | awk -F, '
  {for(i=2;i<=4;i++) if($i ~ /^[0-9]+$/) {s[i]+=$i; n[i]++}}
  END{split("_ windows_gtk4 windows_winui linux_gtk4",L," ");
      for(i=2;i<=4;i++) printf "%-14s n=%-3d avg=%7.1f MB\n", L[i], n[i], s[i]/n[i]/1048576}'
```

Two things about that command, both learned by getting them wrong.

**No `-tail`.** `csv2 -r` already emits data rows only, so an earlier version
of this page piping through `-tail 45` was both unnecessary and lossy: the file
has 47 rows, so it silently dropped **P0 and P1** and reported `n = 44/44/45`.
The averages it printed were 53.9 / 169.7 / 52.7 MB — *identical to one decimal
place* with those two rows restored, because the values are so uniform. The
mistake changed the sample and not the answer, which is why nothing looked
wrong. Report `n` next to any average for exactly this reason: it is the only
column that moved.

**The `$i ~ /^[0-9]+$/` guard is load-bearing.** Without it `n/a` sums as **0**
and still counts toward `n`, dragging every average down silently.

關於那道命令的兩件事，都是做錯之後才學到的。

**不要用 `-tail`。** `csv2 -r` 本來就只輸出資料列，因此本頁較早的版本再接一段 `-tail 45`
既多餘又有損：檔案有 47 列，於是它靜默丟掉了 **P0 與 P1**，並報出 `n = 44/44/45`。它印出的
平均值是 53.9 / 169.7 / 52.7 MB——把那兩列補回去之後**到小數第一位完全相同**，因為各值太過
一致。這個錯誤改變的是樣本而非答案，所以看不出任何異狀。請在任何平均值旁邊一併報出 `n`，
理由正是如此：它是唯一會動的那一欄。

Measured 2026-09-02:

| Column | n | Average | Range | Empty | vs GTK4 |
|---|---:|---:|---|---:|---:|
| Windows GTK4 | 46 | 53.9 MB | 53.9–54.2 | 0 | 1.00x |
| Windows WinUI | 46 | 169.7 MB | 169.6–170.3 | 0 | **3.15x** |
| Linux GTK4 | 47 | 52.7 MB | 52.0–53.3 | 0 | 0.98x |

Complete as of 2026-09-02: every app that can be built on a platform has a
number there. The two `n/a` cells are the only non-numbers, and `macos_appkit`
is empty throughout because it needs a Mac.

2026-09-02 起本表已完整：每一支能在該平台建置的 app 都有數字。唯二的非數字是那兩個 `n/a`，
而 `macos_appkit` 整欄為空是因為它需要一台 Mac。

WinUI costs **115.8 MB more per app**, and the spread across all 46 is only
0.7 MB — so that is not application code, it is the statically linked WinRT/UWP
projection, paid once by every app. Windows GTK4 sits 1.2 MB (2.3%) above Linux
GTK4, which puts the whole 3.15x on the backend choice rather than the OS.

`$i ~ /^[0-9]+$/` 這個條件是關鍵：少了它，`n/a` 會以 **0** 計入總和且仍佔一個 `n`，靜默拉低每一個
平均值。WinUI 每支多付 **115.8 MB**，而 43 支的極差只有 0.3 MB——那不是應用程式碼，是靜態連結的
WinRT/UWP projection，每支各付一次。Windows GTK4 只比 Linux GTK4 多 1.2 MB（2.3%），因此那 3.15
倍完全落在 backend 選擇上，與作業系統無關。

## Empty cells and `n/a`

The two are different and the difference is the point:

- **`n/a`** — the combination does not exist by design. Nothing to build.
- **empty** — it should exist and does not. A real gap; the `note` says what is
  known.

Neither ever means zero.

兩者不同，而這個區別正是重點：**`n/a`** 表示該組合按設計就不存在，沒有東西可建；**空白**表示它應該
存在卻沒有——那是真實的缺口，`note` 欄記錄已知的部分。兩者都不代表零。

**Current status.** Only two cells are `n/a`, and no cell is empty except the
whole `macos_appkit` column:

| App | Cell | Why |
|---|---|---|
| `P6` | windows_gtk4 | `n/a` — imports the WinUI products under `#if os(Windows)`, which `-gtk4` removes; the guard stays true because the flag changes products, not the OS |
| `P6-v2` | windows_winui | `n/a` — pure GTK app, no WinUI counterpart exists |
| every app | macos_appkit | empty — needs a Mac; out of scope on this machine |

**Resolved 2026-09-02**, kept because what the gaps turned out to be is worth
more than the fact they are closed:

| App | Cell | Was | Turned out to be |
|---|---|---|---|
| `P6` | windows_winui | empty | The link had died with `LLVM ERROR: IO failure on output stream: no space on device`, which reads as a compiler crash. The disk was full at 336 MB free. Rebuilt with 7.6 GB free: 178,624,000 bytes, no errors |
| `P7` `P8` `P9` | windows_gtk4 | empty | Nothing at all — the earlier sweep had missed them. Rebuilt on a quiet machine, all three produced |
| `P28` | linux_gtk4 | empty | Same: `P28.swift` was present in the WSL checkout and byte-identical to the Windows copy; the Linux sweep had skipped it |

**目前狀態。** 只有兩格是 `n/a`，除了整欄的 `macos_appkit` 之外沒有空格。
**2026-09-02 已解決**的部分仍保留於上表，因為那些空格「原來是什麼」比「它們已經補上」更有價值。

## What the empty cells found

The gaps were the useful part of building this table, which is the argument for
keeping it: three of them are real defects that nothing else was reporting.

`P7`, `P8` and `P9` had no `-gtk4` executable, and neither skip rule explained
it. **Resolved 2026-09-02: the earlier sweep had simply missed them.** Rebuilt
on a quiet machine, `compile.zsh -gtk4 P7 P8 P9` returned 0 and produced all
three (56.6, 56.6, 56.5 MB) with no errors. Nothing in the source or in
`compile.zsh` was at fault.

Three attempts failed before that, and none of the failures were about `P7`.
The two false readings they produced are worth more than the answer:

`P7`、`P8`、`P9` 原本沒有 `-gtk4` 執行檔，而兩條 skip 規則都無法解釋。**2026-09-02 已解決：
就是先前那趟掃描漏掉了它們。** 在淨空的機器上重建，`compile.zsh -gtk4 P7 P8 P9` 回傳 0 並產出
全部三支（56.6、56.6、56.5 MB），沒有任何錯誤。原始碼與 `compile.zsh` 都沒有問題。

在那之前失敗了三次，而沒有一次的失敗與 `P7` 有關。它們造成的兩次誤讀比答案本身更值得記下：

**Exit code 0 with nothing built.** The attempt ran
`zsh compile.zsh … > log 2>&1; printf 'rc=%d\n' $?; tail -30 log`. The harness
reports the status of the **last** command in that chain — `tail`, which
succeeds — so the run looked clean while `compile.zsh` had returned 1. Record
the status inside the log (`rc=$?` on its own line); do not trust what wraps the
command.

**Then `rc=1` was read as a build failure, and it was not.** `swift-build.exe`
outlived the shell that started it and was still compiling `P7` minutes later —
confirmed by its command line (`--product P7`, started 13:19:23) while a second
attempt failed with `unable to attach DB: database is locked`. A nonzero status
from a parent whose child is still running says nothing about the build. Check
for live `swift-build.exe` before reading any build result.

追查過程中出現兩次誤讀，兩者都比答案本身更值得記下。

**其一：退出碼 0，卻什麼都沒建出來。** 工具回報的是鏈中**最後一個**命令 `tail` 的狀態，而它成功，
於是這一輪看起來乾淨，實際上 `compile.zsh` 回傳的是 1。請把狀態記進紀錄檔本身（獨立一行的
`rc=$?`），不要相信包在命令外面的東西。

**其二：接著把 `rc=1` 讀成建置失敗，而它不是。** `swift-build.exe` 比啟動它的 shell 活得更久，
數分鐘後仍在編譯 `P7`——由其命令列（`--product P7`，13:19:23 啟動）確認，同時第二次嘗試以
`unable to attach DB: database is locked` 失敗。一個 child 仍在執行的 parent 所回傳的非零狀態，
對建置結果毫無意義。讀任何建置結果之前，先確認沒有活著的 `swift-build.exe`。

`P0-winui-baseline` and `P45-MIN` are not rows here: they are hand-made
executables with no `.swift` source, so they cannot be rebuilt and a size for
them would describe an artefact nobody can reproduce.

空白格代表**未建置**，絕不代表**零**。`note` 欄在原因已知時會說明。
`P0-winui-baseline` 與 `P45-MIN` 不列入：它們是沒有 `.swift` 原始碼的手工執行檔，無法重建，
為它們記錄一個大小，等於描述一個沒有人能重現的產物。
