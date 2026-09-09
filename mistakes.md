# mistakes — swift-cross-ui

這棵樹自己的紀錄。格式與規則見 `~/.claude/skills/mistakes_prevention`。
權威次數在 `mistakes_counter.csv2`,一律經由 `csv2` 讀寫。

This tree's own record. The authoritative counts live in `mistakes_counter.csv2`
and are read and written with `csv2`.

---

## 1. 在一份談好的佇列走到一半停下來,並以回報代替繼續

**次數:3 次 / 2 天(2026-09-08、2026-09-09)。**

### 症狀 / What it looks like

一個工作單位做完了、報告寫好了、該回合結束 —— 而使用者原本要求「照著清單做下去」的那份清單上,
還有沒有開始的項目。**沒有任何東西失敗。** 那份報告對於「做了什麼」完全準確,對於「什麼還沒開始」
則保持沉默,而這兩者在畫面上讀起來是同一件事:一個完成的回合。

使用者是這樣發現的 —— 連問了兩次 *"Are you still working ?"*。那個問題本身就是症狀:
若佇列的推進是看得見的,就不需要問。

A unit of work completes, the report is written, and the turn ends -- with items
still on the list the user asked to be worked through. Nothing fails. The report
is accurate about what was done and silent about what was not started, and on
screen those two are the same thing. The user found it by asking "Are you still
working?" twice; needing to ask is the symptom.

### 為什麼「更努力記得」擋不住它

因為下一個項目**存在於對話裡,而不存在於檔案裡**。一份貼在訊息中的表格會隨著 context 被壓縮而
淡出,而淡出之後,「佇列已經空了」與「我不記得佇列了」在內部讀起來完全相同 —— 兩者都不會產生
任何一行輸出。

The next item lives in the conversation, not in a file. A table pasted into a
message fades with compaction, and after it fades "the queue is empty" and "I no
longer remember the queue" read identically from the inside: neither produces a
line of output.

### 矯正措施 / The corrective

`heartbeats/heartbeat.zsh` 與 `queue.md`。下一個項目由**檔案**指名,不由記憶指名:

```sh
sh heartbeats/heartbeat.zsh          # 印出下一個未完成項目,或 IDLE
zsh heartbeats/heartbeat.zsh --on    # 打開開關
zsh heartbeats/heartbeat.zsh --off   # 關掉;此後每次心跳都是一次無成本的 IDLE
```

搭配 `/loop` 使用時,關掉開關的那一輪只會執行這一支腳本、印出 `IDLE` 就結束 —— 那正是使用者
要的「沒有任務時不要浪費 token 去問同一個問題」。兩件事現在合在同一支 `heartbeats/heartbeat.zsh` 裡:
`--next` 指出下一項,不帶參數則把心跳送到各個 session。它們共用同一個開關,而共用是刻意的——
分成兩支時,「開了一個、忘了另一個」讀起來會與「兩個都開著但很安靜」完全相同。

**這一段原本寫錯了,更正留在原地。** 它原本說:「這裡不能用 cron 或 while 迴圈去問一個執行中的
session;shell 腳本沒有辦法把提示注入活著的互動式 session,`multissh` 是 ssh 設定,它到得了那台
機器、到不了那個 session。」使用者指出 `multissh` 有 `exec`,而那是對的 —— 該主張是憑推理下的,
不是量出來的,而 CLAUDE.md 恰好對這種形狀有一條規則:*「這個平台沒有對應的 API」是一項待查證的
主張,不是結論。*

2026-09-09 實測的結果:

| 量測 | 結果 |
| --- | --- |
| `multissh -F ~/.multissh/generated/config2Win winnode "echo PING_OK"` | `PING_OK` |
| `multissh winnode "echo PING_OK"`(不給 config) | 名稱解析失敗 |
| `screen -S s -p 0 -X stuff "…\r"` 打進一個活著的 session | 成功,該 session 執行了送進去的那一行 |
| `heartbeats/heartbeat.zsh` 端到端 | `sent to local 26235.claude-selftest`,而該 session 寫出了 `REACHED_THE_LIVE_SESSION` |
| 這台 Mac 上跑在 multiplexer 裡的 session | 0 個(tmux 未安裝、`screen -ls` 無 socket) |
| Windows 端的 multiplexer | 兩個都沒有(MSYS2 上 `tmux`、`screen` 皆 command not found) |

因此真正的限制窄得多,而且是**可檢查的**:那個 session 必須跑在 multiplexer 之內。在裸終端機中
啟動的 session 沒有任何人寫得進去的 socket。做法是改用 `screen -S claude-<名稱> claude` 啟動;
Windows 那端則要先裝一個 multiplexer。工具是 `heartbeats/heartbeat.zsh`。

對**佇列**這件事來說,`/loop` 仍然是比較好的機制,但理由不是「cron 做不到」——而是它從正在做事的
那個 session 內部重新進入,因此下一個項目是由必須採取行動的那個 session 自己讀到的。

The paragraph that used to stand here was wrong and the correction stays in
place. It claimed cron could not reach a live session and that multissh reached
the machine but not the session. multissh has an exec channel, the claim was
reasoned rather than measured, and CLAUDE.md has a rule for exactly that shape.
Measured: multissh exec works with `-F` and fails name resolution without it;
`screen -X stuff` writes into a live session's stdin; the script does both end
to end. The real constraint is that the session must run inside a multiplexer,
and today none of them do on either machine.

The next item is named by a file, not by memory. Paired with `/loop`, a switched
-off beat runs this one script, prints `IDLE`, and ends -- which is the "do not
spend tokens asking when there is no task" half of the request. `/loop` is the
mechanism for the queue because it re-enters from inside the session doing the
work, not because cron is incapable: cron reaches a live session through
`heartbeats/heartbeat.zsh`, and the table above is the measurement.

---

## 2. 新增的原始檔不會被增量建置採納

**次數:1 次 / 1 天(2026-09-10)。**

### 症狀 / What it looks like

編譯階段**完全乾淨**,然後**連結器**說:

```
lld-link: error: undefined symbol: gtk_passthrough_drawing_area_new
lld-link: error: undefined symbol: gtk_passthrough_drawing_area_set_opaque
```

那讀起來像「缺少某個函式庫」或「宣告寫錯了」——**不像「有一個檔案從來沒有被編譯」**。
宣告看得見(它在 `gtk_helpers.h` 裡,而該標頭確實被讀到了),定義存在於磁碟上,而錯誤訊息
指名的是**符號**,對「被略過的那個檔案」隻字未提。

2026-09-10 實測:新增 `Sources/GtkCHelpers/gtk_passthrough_drawing_area.c` 之後,
`GtkCHelpers` 重新編譯了 **6** 個檔案,而新的那一個不在其中;
`.build/x86_64-unknown-windows-msvc/release/GtkCHelpers.build/` 裡有 8 個 `.o`,新的那個沒有。

The compile phase is completely clean and then the LINKER reports an undefined
symbol. That reads as a missing library or a bad declaration, not as a file that
was never compiled: the declaration is visible, the definition is on disk, and
the message names the symbol while saying nothing about the file it skipped.

### 為什麼「更小心」擋不住它 / Why care does not help

**`touch Package.swift` 沒有用。** SwiftPM 對 manifest 取**內容雜湊**,所以只改 mtime 不會
讓它重新規劃。我試過,失敗了一次,而失敗的方式與第一次完全相同——同樣的連結器錯誤。

真正過期的是 **`.build/release.yaml`**(llbuild 的建置計畫)。實測時它比新檔案舊了**三小時**,
仍然列著舊的來源集合:

```
grep -c "gtk_passthrough_drawing_area" release.yaml   →  0
grep -c "gtk_passthrough_fixed"        release.yaml   →  136
```

`touch Package.swift` does NOT work, because SwiftPM hashes manifest content
rather than reading its mtime. What is actually stale is `.build/release.yaml`,
llbuild's plan -- three hours old and still listing the old source set.

### 矯正措施 / The corrective

**新增任何原始檔之後的第一次建置之前,刪掉建置計畫:**

```sh
rm -f <scratch>/.build/release.yaml
```

它會被重新產生,而物件檔會保留,所以代價只是一次重新規劃,不是一次完整重建。

**這不只是 C 檔的問題。** 同一天新增 `Sources/SwiftCrossUI/Views/Modifiers/TagModifier.swift`
(Swift 檔)時,我**預先**刪掉了 release.yaml,於是沒有撞上——但機制相同,而如果沒有預先刪,
症狀會是 Swift 端的 `cannot find type ... in scope`,一樣不會提到那個檔案。

`Sources/GtkCHelpers/include/gtk_helpers.h` 對「新增的**標頭**不會被採納」已有一段既有註記;
本條目把它擴及**原始檔**,並記下 `touch Package.swift` 這條走不通的路。

Delete `.build/release.yaml` before the first build after adding a source file.
It is regenerated and the object files survive, so the cost is one replan rather
than a full rebuild. This is not C-specific: a new Swift file has the same
mechanism, and its symptom is `cannot find type ... in scope`, which likewise
never names the file.

### 守衛 / The guard

```sh
ls -l <scratch>/.build/release.yaml
```

若它比新檔案還舊,那份計畫**不可能**知道新檔案的存在。搭配重新產生之後的
`git diff --stat` 一起看。
