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

`Scripts/queue_heartbeat.zsh` 與 `queue.md`。下一個項目由**檔案**指名,不由記憶指名:

```sh
sh Scripts/queue_heartbeat.zsh          # 印出下一個未完成項目,或 IDLE
zsh Scripts/queue_heartbeat.zsh --on    # 打開開關
zsh Scripts/queue_heartbeat.zsh --off   # 關掉;此後每次心跳都是一次無成本的 IDLE
```

搭配 `/loop` 使用時,關掉開關的那一輪只會執行這一支腳本、印出 `IDLE` 就結束 —— 那正是使用者
要的「沒有任務時不要浪費 token 去問同一個問題」。

**這裡不能用 cron 或 while 迴圈去問一個執行中的 session。** 一支 shell 腳本沒有辦法把提示注入
到一個活著的互動式 session 裡;`multissh` 是 ssh 設定,它到得了那台機器,到不了那個 session。
能週期性重新進入的是 `/loop`,而它本來就跑在 session 之內。

The next item is named by a file, not by memory. Paired with `/loop`, a switched
-off beat runs this one script, prints `IDLE`, and ends -- which is the "do not
spend tokens asking when there is no task" half of the request. A cron job or a
`while` loop cannot do this: a shell script cannot inject a prompt into a live
interactive session, and `multissh` reaches the machine, not the session.
`/loop` re-enters from inside the session, which is why it is the mechanism.
