# mistakes — swift-cross-ui

這棵樹自己的紀錄。格式與規則見 `~/.claude/skills/mistakes_prevention`。
權威次數在 `mistakes_counter.csv2`,一律經由 `csv2` 讀寫。

This tree's own record. The authoritative counts live in `mistakes_counter.csv2`
and are read and written with `csv2`.

---

## 撞號時怎麼辦:兩條都留,重新編號,絕不覆蓋

兩台機器同一天各寫一條,拿到同一個編號,是**常態**而不是意外——編號取自「目前最大值 +1」,而兩邊
在合併之前都看不到對方。2026-09-16 一天之內就發生了兩次(第 8 條與第 13 條)。

**規則:**

1. **兩條都活下來。** 一條 mistake 記的是一次**真實發生過、而且沒有任何工具會報錯**的事。讓一邊
   蓋掉另一邊,等於宣稱那一次沒有發生過——而它發生過。
2. **依日期重新編號**,不是依誰先推上來。較早發生的拿較小的號。
3. **兩個檔案都要改:** `mistakes_counter.csv2` 的 `id` 欄,以及 `mistakes.md` 的 `## N.` 標題——
   中英兩個標題都算。
4. **不要合併兩條看起來相似的。** 2026-09-16 的第 13 與第 14 條都是「只讀了證據的一半」,但一個是
   把過期文件當現況、另一個是把過渡狀態當判決。分開放,兩條都比合成一條有用。

**檢查:**

```sh
csv2 -r -i mistakes_counter.csv2 | awk -F, '{print $1}' | sort | uniq -d   # 應該沒有輸出
grep -o "^## [0-9]*\." mistakes.md | sort | uniq -c                        # 每個編號的標題數
sh Scripts/check_mistakes_numbering.sh                                     # 上面兩者,會失敗
```

**哪一種合併會自動過、哪一種不會,已經各發生過一次:** 兩邊都**追加在檔尾**時,git 會把兩段都留下,
不需要人介入——那是第 13/14 條。兩邊改到**同一行**時就會衝突——那是第 8 條,`mistakes_counter.csv2`
的最後一列。**兩種情況的正確解法相同**,只是前一種不會提醒你去做。

---

## When two machines pick the same number: keep both, renumber, never overwrite

Two machines writing on the same day land on the same number routinely rather
than exceptionally -- the number is "highest so far, plus one", and neither side
sees the other until the merge. It happened twice on 2026-09-16 alone, at entries
8 and 13.

1. **Both survive.** An entry records something that HAPPENED and that no tool
   reported. Letting one overwrite the other claims it did not happen.
2. **Renumber by date**, not by who pushed first.
3. **Both files**: the `id` column in `mistakes_counter.csv2` and the `## N.`
   headings in `mistakes.md` -- both the Chinese and the English one.
4. **Do not fold two similar-looking entries into one.** 13 and 14 are both
   "read half the evidence", and one is a stale document taken for the present
   while the other is a transition taken for a verdict. Apart, each is usable.

The two merge shapes have each occurred once: appending at the END of the file
merges clean and never asks (13 and 14), while touching the SAME LINE conflicts
and does (8, the last row of the counter). The correct resolution is identical;
only the first one fails to prompt you for it.

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

---

## 3. 加了「改變目標視窗」的動作,卻沒做 identity 那一半

**次數:3 次 / 2 天(2026-09-09、2026-09-10)。三個平台、三種不同的寫法、同一個靜默失敗。**

### 症狀 / What it looks like

`focus` **成功**。重放回報**每一個動作都完成**。其後每一個座標**都算得出一個數字**——只是那個
數字相對於**重放開始之前**所量測的那個視窗。

沒有任何東西失敗:`focus` 那一列是對的、座標換算是對的、`SendInput`/`xdotool` 也確實把事件送出去了。
唯一錯的是**參考座標系**,而參考座標系不會出現在任何一行輸出裡。

`focus` succeeds, the replay reports every action completed, and every later
coordinate still resolves against the window measured before the replay began.
Nothing errors -- each coordinate is a real number, just relative to the wrong
window.

### 三次,三種寫法 / Three occurrences, three spellings

| 平台 | 它錯在哪 | 修於 |
| --- | --- | --- |
| AppKit | `currentWindowIdentity()` **沒有覆寫**,回傳協定預設 `0` | `a8627210`(Mac 端) |
| Win32 | **有**覆寫,但以 `ownWindow()`(面積最大)作答——而第二個視窗通常**比較小** | `c4e421fb` |
| xdotool | **沒有覆寫** | `14f1dd13` |

**`0` 不是一個中性值。** `Synthesiser.replay` 把 `0` 讀作「無法判斷」,也就是「沒有改變」——所以
一個沒有覆寫的 synthesiser,在焦點確實移動之後,會**主動回報「什麼都沒變」**。

**Win32 那一次特別值得記**,因為它**有**覆寫,看起來已經處理過了。它以「面積最大」作答,而那條規則
對「一個視窗加上 toolkit 的輔助視窗」是對的,對「`focus` 所要創造的情況」是錯的——設定視窗比主視窗
小,於是 identity 持續回報主視窗。**一個存在的覆寫,不是它答對了的證據。**

### 為什麼「更仔細」擋不住它 / Why care does not help

這件事有**兩半**,而只有一半看得見:

1. **把視窗抬到前面**——看得見,做了就知道有沒有效
2. **讓 `currentWindowIdentity()` 察覺到它**——**看不見**,而且它「沒做」與「做了但答錯」產生
   完全相同的畫面

第 1 半做完的那一刻,螢幕上的東西看起來就是對的。第 2 半沒有任何觸發它的理由——不會編譯失敗、
不會執行失敗、不會有測試變紅。三次裡有兩次,是在**別的**東西壞掉時才連帶被發現的。

### 矯正措施 / The corrective

**新增任何「改變目標」的動作時,把 `currentWindowIdentity()` 當成必答題,不是選答題。**
在宣布該動作完成之前,對**每一個** Synthesiser 檔案 grep 該覆寫:

```sh
grep -c currentWindowIdentity Sources/InputEvent/*Synthesiser.swift
```

**回傳 0 的那一個就是下一次的受害者。** 而且不要只看「有沒有覆寫」——還要看它**答的是哪個視窗**,
是否與 `currentWindowGeometry()` 會量測的那一個一致。兩者不一致時,identity 變了而幾何沒變,
比兩者都不動更糟。

Treat `currentWindowIdentity()` as a required second half whenever an action
retargets anything. Grep every Synthesiser for the override before calling the
action done -- and check WHICH window it answers with, not merely that it exists.

### 守衛 / The guard

```sh
grep -c currentWindowIdentity Sources/InputEvent/*Synthesiser.swift
```

三個檔案都必須 > 0。這條在 2026-09-10 之前會回報 AppKit=1、Win32=1、Xdotool=**0**。

---

## 4. 對一個**不存在的目標**執行工具,把「沒有輸出」讀成「乾淨的結果」

**次數:2 次 / 1 天(2026-09-10)。兩次都是檔名錯了一個字,兩次都得出一個看起來很好的結論。**

### 症狀 / What it looks like

| # | 打出去的指令 | 目標實際叫什麼 | 得出的結論 | 真相 |
| --- | --- | --- | --- | --- |
| 1 | `objdump -T libgtk-4-1.dll`、`strings` 同上 | `gtk-4-1.dll`(無 `lib` 前綴) | 「零個符號」 | **量測從未執行** |
| 2 | `zsh compile.sh P61 -gtk4` → `grep -cE ": (error\|warning):"` → `0` | `compile.zsh`(sh→zsh 掃描時改名) | 「建置乾淨,0 errors」 | **建置從未執行** |

**兩次的畫面都與成功完全相同。** 一次乾淨的建置印 0 個錯誤;一支從未啟動的建置也印 0 個錯誤。
一個沒有符號的檔案 `objdump` 沒有輸出;一個不存在的檔案 `objdump` 也沒有輸出——**而錯誤訊息
在別的串流上,或早已捲出畫面**。第 2 次的 `can't open input file: compile.sh` 就在同一份 log 裡,
排在我讀的那一行**下面**。

Running a tool against a filename that does not exist produces no output, and no
output is indistinguishable from a clean result. Both times the error message
existed -- on another stream, or below the line that was read.

### 為什麼「更仔細地看輸出」擋不住它 / Why reading harder does not help

因為**要看的東西不在輸出裡**。輸出是空的,而空的輸出正是好消息的樣子。要察覺,得先知道
「該有多少」——而那正是這次量測本來要回答的問題。**這是循環的**:量測的目的是判定 0 是否正常,
而判定 0 是否正常又需要一次可信的量測。

單靠退出碼也擋不住:第 2 次 `grep -c` 沒命中會回傳 1,而我把 `rc` 放在管線末端,拿到的是
`grep` 的而非 `zsh` 的。第 1 次 `objdump` 對不存在的檔案在某些建置上**以 0 結束**。

### 矯正措施 / The corrective

**任何以「零」為內容的結論,都必須附一個同時執行、且已知會命中的正向對照。**
沒有對照的零,只證明了「這條指令沒有產出」,不證明「那個東西不存在」。

本次同一天做對過一次,值得對照:查 `Sources/Gtk/` 有沒有 focus 綁定時,同一道 `grep` 也涵蓋了
`Sources/AppKitBackend/` 與 `Sources/UIKitBackend/`,而**那兩個有命中**。於是「Gtk 零命中」
是一項發現,而不是一個工具沒跑起來的副作用。

```sh
# 錯:一個零,無從判斷它是不是量到的
grep -rn grabFocus Sources/Gtk/

# 對:同一道指令帶著一個必然命中的對照
grep -rn "grabFocus\|becomeFirstResponder" Sources/Gtk/ Sources/AppKitBackend/
```

對「檔案本身」也一樣,而且更便宜——**先讓路徑失敗,再讓工具執行**:

```sh
ls -l "$target" || exit 1        # 檔名錯在這裡就停,而不是傳給 objdump 去靜靜地什麼都不做
```

Any conclusion whose content is a zero needs a positive control run by the SAME
command -- something known to match. A zero without one only shows the command
produced nothing; it does not show the thing is absent. For files, make the path
fail before the tool runs.

### 同一天,第三次——而這次被守衛擋下了 / The third time the same day, caught

寫下本條之後**數小時內**,同樣的形狀第三次出現:`zsh compile.zsh P61 -winui`。這個腳本
**沒有** `-winui` 旗標(WinUI 是 Windows 上的預設,`-gtk4` 才是覆寫),於是 `-winui` 被當成
第二個 app 名稱,腳本去找 `-winui.swift`。而 `grep -cE ": error:"` 再一次印出 **0**——因為
`Missing source file:` 並不是編譯器診斷的樣式。

**差別在於這次同一個指令裡還有一行 `ls -l output/P61-winui.exe`,而它說 No such file。**
於是那個 0 當場失去意義,前後不到一秒。

這是本條目值得寫的證據:擋下它的不是更小心地讀那個 0,而是**在同一道指令裡放了一個
會說話的第二來源**。前兩次沒有那一行。

Hours after this entry was written the same shape appeared a third time -- and the
`ls -l` on the expected output, in the same command, contradicted the zero within a
second. What caught it was a second source that speaks, not a more careful reading.

### 守衛 / The guard

```sh
ls -l <每一個要傳給工具的路徑> || exit 1
```

以及:寫下「0 個」之前,問**這道指令在什麼情況下會印出非零**,並且讓它印一次。
若答不出來,那個 0 還沒有意義。

**與第 2 條的關係**:兩者都源於「建置系統的狀態與我以為的不同」,但形狀相反。第 2 條是
**建置跑了而檔案沒進去**;本條是**建置根本沒跑**。第 2 條的守衛(`ls -l .build/release.yaml`)
在本條下毫無用處——那個檔案好端端地在那裡,只是這次沒有人碰過它。

---

## 5. 把一個已經死掉的行程讀成一個很慢的行程,並替它編了一套機制

**2026-09-10,1 次 / 1 天。**

### 症狀

P52 加上第四條 arm 之後,日誌停在:

```
CONFIG buttons/arm=48 columns=8 rounds=10 press-passes/round=5 mounts/round=1 steps=240
CONFIG poll=15ms quiet=45ms max-polls=80 warmup=2000ms cpu-clock=unavailable on this platform
```

然後不再前進。**沒有崩潰訊息、沒有非零退出碼、沒有任何一支工具說出任何一句話**——建置回報
`build=0`,而它應該印的那行 `--- P52 results ---` 只是沒有出現。這與「一個跑得太慢的
benchmark」在畫面上完全一樣。

### 我做了什麼

我先把 rounds 從 10 降到 2(48 步,應該一分鐘內跑完)——還是一樣。然後我提出一個解釋:
**AppKit 會節流背景視窗的重繪**,而這支 benchmark 靠輪詢哨兵推進,所以它在背景推不動。

那是一個**真實存在的機制**,這正是它有說服力的地方。我還為它寫了一支 `test_P52.zsh`,把 app
放到前景重跑一次來驗證這個假設。前景一樣停住。

### 真正的原因

`P52Bench` 有四個以 arm 索引的陣列寫死 `count: 3`:

```swift
nonisolated(unsafe) static var lastSentinel = [UInt64](repeating: 0, count: 3)
```

第四條 arm 讓 `lastSentinel[3]` 在第一步跑起來之前就終結了行程。`models` 上方有一行註解說
「數量必須與 `armCount` 一致」,而它只說了 `models`。

### 矯正措施

**在解釋「為什麼慢」之前,先確認它還活著。** 而當改動是我自己做的時候,有一個比任何理論都快的
動作:

```sh
git checkout -- testapp/P52.swift && zsh testapp/compile.zsh P52 && (跑一次)
```

原版跑完了、印出了結果——**一個指令就把「平台的行為」與「我弄壞的東西」分開了**,而我在那之前
已經為一個不存在的原因花掉兩輪重跑與一支新腳本。

The explanation I reached for was a real mechanism, which is what made it
convincing. Reverting my own change took one command and answered it outright.
Do that first, whenever the thing that changed is mine.

---

## 6. 用 grep 過濾出來的一行,宣告整個測試套件「通過了」

**2 次 / 2 天(2026-09-10、2026-09-16)。**

### 第二次(2026-09-16):同一條,換了一個偽裝

這一次不是 `grep`,是 `tail`,而且是在**背景建置**裡:

```sh
zsh testapp/compile.zsh P23 2>&1 | tail -6     # 背景執行
```

管線中的 stdout 是**區塊緩衝**、stderr **不是**,於是最後六行剛好全是編譯器警告——`Done.` 與
那一行 `error:` **都被切掉了**,而我讀到的退出碼是 `tail` 的、不是編譯器的。我據此寫下
「0 errors」並開始下一件事。

**推翻它的不是那份 log**,因為 log 裡已經沒有證據了。是**產物本身**:`P23-WinUI.exe` 的時間戳
仍是兩小時前——那正是第 9 條的矯正措施。改成把完整輸出導到檔案再讀 `$?`,得到 `rc=1`、一個
真正的錯誤(`getCurrentPoint` 會 throw)。

*Second occurrence, a new disguise: `| tail -6` on a backgrounded build. stdout is block-buffered
through a pipe and stderr is not, so the tail held only warnings -- `Done.` and the single `error:`
were both cut -- and the exit status was tail's. What contradicted it was the ARTEFACT's timestamp,
entry 9's corrective, not the log.*

**因此矯正措施加一句:在判斷建置成敗的那一個指令裡,永遠不要把建置接進 `tail` 或 `grep`。**
把整份 log 導到檔案,分開讀 `$?`。

### 第一次(2026-09-10)

### 症狀

```
$ run_checked.zsh --want 'Test run with' -- sh Scripts/test.sh 2>&1 | grep -aE "Test run with|✗" | tail -3
􀢂  Test run with 68 tests in 15 suites passed after 0.339 seconds with 1 known issue.
􁁛  Test run with 14 tests in 1 suite passed after 0.201 seconds.
```

看起來乾淨得無可挑剔。而在那兩行上方,`SwiftCrossUITests` **根本沒有建置成功**:

```
Tests/SwiftCrossUITests/GridLayoutTests.swift:158:23: error: generic parameter could not be inferred
error: Build failed
```

`#118` 的改名移除了 `LazyVGrid.resolve` 與 `plan.columnWidths`,而測試還在用它們。`Scripts/test.sh`
會跑不只一次測試,後面那一次建得起來、也印出了 `passed`——**而我的樣式只認得那一行**。

編譯錯誤那行帶著 `error:`、沒有勾勾,於是落在樣式之外。我據此寫下了 commit 訊息裡的
「Scripts/test.sh passes」,那句話是假的,而它一直到一小時後同一個過濾器碰巧顯示出那行錯誤時才被發現。

### 為什麼工具在手邊卻沒擋住

**`run_checked.zsh` 就在那條指令裡。** 它會掃描失敗訊號、會回報退出碼——而我把它的輸出接進了
`grep | tail`,於是它說了什麼我一個字都沒看到。這正是 mistakes_prevention 那份 skill 所記載的
**第六種偽裝**:不是樣式太窄,是「這次不必看判定」。

### 矯正措施

要摘要**也**要判定時,把兩者分開,不要讓其中一個吃掉另一個:

```sh
run_checked.zsh --want 'Test run with' -- sh Scripts/test.sh > /tmp/t.log 2>&1
echo "exit=$?"        # ← 判定，單獨一行
grep -aE "Test run with|error:" /tmp/t.log
```

**在寫下任何關於建置或測試的主張之前,先讀那一行 `exit=`。** 樣式決定你看到什麼,退出碼決定
事實是什麼。

The tool was inside the very command that hid it: run_checked.zsh scans for
failures and reports an exit status, and I piped its output into `grep | tail`
so none of that reached me. Capture the run to a file, echo the status on its
own line, then grep the file.

---

## 7. 用「編得過」或「答了」回報進度,而它們與「完成」在報告裡長得一樣

**次數:1 次 / 1 天(2026-09-11)。而它發生在我整天都在別人程式碼裡抓同一個形狀之後。**

### 症狀 / What it looks like

一份進度表,六列,五列標著粗體的「已完成」:

| 那份表格說 | 實際做到的 |
| --- | --- |
| **#127 兩格**「都編過了」 | 編得過。`originInWindow` **從未被呼叫過**,更沒有動作檔驗證它回傳的座標是對的 |
| **#122 focus**「已答」 | 回答了一個 API 問題。**協定不存在、實作不存在**,一行程式碼都沒寫 |
| **#109 分工**「已點頭」 | 說了「好」。**零行程式碼** |

沒有任何東西是假的。每一句話單獨看都準確:那兩格**確實**編得過,那個問題**確實**答了,
那個分工**確實**同意了。**錯的是把它們放進一個標題叫「狀態」的欄位裡,而讀者會把那一欄
讀成「這件事好了嗎」。**

使用者一句話就戳破:**「#127 #122 #109 不算完工,如果沒有量測與 action file」**。

A progress table with five of six rows in bold "done". Every individual sentence
was true -- those cells do compile, that question was answered, that split was
agreed. What was wrong was putting them in a column headed "status", which a
reader reads as "is this finished".

### 為什麼「更誠實」擋不住它

**因為每一句都已經是誠實的。** 這不是誇大,是**分類**:三種狀態被併成一種。

| 狀態 | 證據長什麼樣 | 它能保證什麼 |
| --- | --- | --- |
| **答了一個問題** | 一段引用、一個行號 | 下一個人不必再查 |
| **編得過** | `BUILD-RC=0` 加一個 exe 的時間戳 | 型別對得上。**執行期完全未知** |
| **跑過並量到** | 數字,附對照組 | 那個行為**確實發生了** |

**只有第三種能回答「這件事好了嗎」。** 而前兩種在一張表格裡佔一樣寬的格子。

**這一次特別值得記,是因為我當天整天都在抓同一個形狀**:Mac 端推來的每一個檔案都寫著
「**NOT COMPILED HERE**」,而我逐一建置、逐一抓出 build break——`transformPoint` 漏 `try`、
`EventCleanup` 型別、`@preconcurrency`、`ManipulationModes` 沒有 `union`——每一次都在說
「寫得出來不等於編得過」。然後我用**同一個形狀**報了自己的進度:編得過不等於跑得動。

Nothing here is exaggeration; it is a category error. Three states were merged
into one, and only the third answers "is it finished". What makes this instance
worth recording is that I spent the same day catching exactly this shape in
someone else's work -- every file arriving marked "NOT COMPILED HERE" -- and
then used it to report my own.

### 矯正措施 / The corrective

**進度表不得有「完成」欄。它必須有三欄,而且每一欄要求不同的證據。**

```
| 項目 | 答了 | 編得過 | 跑過並量到 |
```

- **答了**：附行號或引用。
- **編得過**：附 `BUILD-RC=0` **與產出檔的時間戳**——`ls -l` 那個 exe。這是第 4 條的守衛,
  在此處同樣適用:一個沒跑起來的建置也會印出 0 個錯誤。
- **跑過並量到**：附**數字與對照組**。沒有數字就是空的。

**一列若第三欄是空的,它就不是完成的**,無論前兩欄多滿。

寫回報時,若一項只有前兩欄,就用「編得過,未跑」四個字,不要用「已完成」——**那四個字的
長度差異,正是這一條要保住的東西。**

A progress table must not have a "done" column. It needs three -- answered,
compiles, ran-and-measured -- each demanding different evidence, and a row whose
third column is empty is not finished however full the first two are.

### 守衛 / The guard

回報一項之前問:**「我能貼出一個數字嗎?」**

貼不出來,就寫「編得過,未跑」。`matrix_coverage/results.csv2` 是那個數字該去的地方,
而它的欄位本來就強制這件事——一列沒有 note 裡的量測,就只是一列而已。

Before reporting an item: can I paste a number? If not, the words are "compiles,
not run".

---

## 8. 把量到的數字拿去和一個**從未被量過的常數**相比,並宣告它有缺陷

**次數:1 次 / 1 天(2026-09-11)。而它的代價不只是我自己走錯——它讓另一台機器照著錯的
診斷寫了一份修法。**

### 症狀 / What it looks like

一次量測:`CompositionTarget.Rendering` 在 1.86 秒內觸發 262 次 = **140.4 Hz**。

我寫下的結論是「WinUI 的速率不對」。理由聽起來完全合理:*畫面更新率是 60 Hz,140 太高了,
所以那個事件每幀觸發不只一次。*

**那句話裡有兩個數字。一個是量到的,另一個是我腦子裡來的。** 而我從未查證後者。

一天之後,`dxdiag /t` 給出一行:

```
Current Mode: 1920 x 1080 (32 bit) (144Hz)
```

**這台顯示器是 144 Hz。** 141.6 Hz(修好時鐘之後)就是更新率減掉少數掉幀,間隔中位數 7.0ms
就是一幀(6.94ms)。那個事件**每幀觸發一次,而且一直都是**。從頭到尾沒有這個缺陷。

A measurement of 140.4 Hz was declared a defect because the display "is 60 Hz".
Two numbers in that sentence: one measured, one from memory. The display is
144 Hz. There was never a defect.

### 它擴散到了別人身上 / It propagated

**這一條之所以比「我自己繞路」嚴重,是因為那個錯的前提被送出去了。** Mac 端讀到「140 Hz,
間隔中位數 0.0ms」,據此推出一個**在他們那一半完全正確**的診斷,然後寫了一份修法:改用
`RenderingEventArgs.renderingTime` 來合併重複的 tick。

結果是兩層的浪費:

1. `RenderingEventArgs` **在 swift-winui 裡根本沒有綁定**(對照組:0 個檔案命中,對照的
   `CompositionTarget` 有 3 個),那個 event 是 `Event<EventHandler<Any?>>`,所以那份修法
   編不過;
2. 就算編得過,**它要解決的問題不存在**。

The wrong premise was handed over. The other machine derived a diagnosis that was
correct about its own half, then wrote a fix for a problem that did not exist --
and the type that fix needed is not even bound.

### 為什麼「更仔細」擋不住它 / Why care does not help

**因為 60 從來沒有以「一個待查的數字」的身分出現過。** 它是背景知識,不是一個步驟。
量測的部分做得很嚴謹——計數、時距、四分位間隔全都有——而比較的另一端連一次呼叫都沒有。

這一條與第 4 條**不同**。第 4 條是「一個零被讀成乾淨的結果」,守衛是正對照組。這一條的
數字是**非零而且正確的**;錯的是它被拿去比較的那個東西。沒有任何對照組會發現這件事,因為
被量的那一側從頭到尾都是對的。

**而且它有一個特別安靜的性質:那個錯誤的結論帶著一個乾淨的機制。**「事件每幀觸發不只一次」
是一個真實存在、在別處確實發生過的現象。一個有機制可以解釋的錯誤結論,讀起來比一個沒有
解釋的正確結論更可信。

This is not entry 4. There the number was zero and the guard is a positive
control. Here the measured number was non-zero and correct; what was wrong was
the thing it was compared against, and no control on the measured side would ever
find that. It is quiet in a particular way: the false conclusion came with a
clean mechanism, and a wrong answer with a mechanism reads as more credible than
a right answer without one.

### 矯正措施 / The corrective

**一次比較有兩端。兩端都要有出處。**

寫下「X 比 Y 大/小,所以有問題」之前,對 **Y** 問和對 X 一樣的問題:*這個數字是哪裡來的?*

| Y 的來源 | 可用 |
| --- | --- |
| 同一次執行量到的 | 是 |
| 一個指令查到的,而那個指令寫在旁邊 | 是 |
| 規格書/文件裡的,並附連結 | 是 |
| **「我知道它是這個值」** | **否——去查。它是本條的全部內容** |

尤其要警覺**那些「大家都知道」的常數**,因為它們正是不會被查的那一種:60 Hz、8 KiB 的頁、
1000 vs 1024、預設 timeout、螢幕 DPI 96。這些每一個都有一台機器上是別的值。

A comparison has two sides. Before writing "X is larger than Y, so something is
wrong", ask of **Y** what you asked of X: where did this number come from? Be
most suspicious of the constants everyone knows, because those are precisely the
ones nobody looks up.

### 守衛 / The guard

**把 Y 的來源指令和 Y 一起寫進那份紀錄。** 這與使用者的 `~/.claude/CLAUDE.md` 已經有的
一條是同一條——「把重新產生的指令放在任何數字旁邊」——只是它先前被理解成只適用於**我產生的**
數字。它同樣適用於**我引用的**數字。

本次的形式:`testapp/FAQ.md` 那一節裡,144 Hz 旁邊就寫著 `dxdiag /t <檔案>`,而且註明
`wmic` 在 Windows 11 26200 上什麼都不回傳——好讓下一個人不必重新發現這件事。

Record the command that produces Y next to Y. The user's own rule -- "put the
regeneration command next to any number" -- was being applied only to numbers I
generated. It applies equally to numbers I quote.
---

## 9. 量到的是上一次的建置,因為「建置」與「打包」是兩個步驟

**2026-09-15,1 次,1 天。**

### 症狀

Android 上的 P57 顯示 `lazy rows: NO`,而 logcat 印出
`-lazyrows: EAGER setItems called with 2000 items`。兩個獨立的訊號一致指向同一個結論:
`BackendFeatures.LazyListRows` 的 conformance 編得進去,執行期卻看不到。於是我開始查
「靜態連結下 protocol conformance record 被丟棄」這類理論。

**Swift 從第一次建置起就是對的。裝置從來沒拿到它。**

`compile.zsh -android` 建到 `.build/`,而 APK 是由 `test_android.zsh` 從**另一次** swift-bundler
建置(`.build-bundler/`)打包的。因此:編譯回傳 0、`adb install` 印出 `Success`、app 啟動並正常
繪製——而每一張截圖、每一次 `dumpsys` 量測,量的都是**上一次**的建置。

### 為什麼沒有任何東西報錯

三個步驟各自都成功,而且各自都誠實:

| 步驟 | 回報 | 它實際保證了什麼 |
| --- | --- | --- |
| `compile.zsh -android` rc=0 | 成功 | **原始碼編得過**——不保證有可安裝的產物 |
| `adb install -r *.apk` | `Success` | **那個檔案裝好了**——不保證那個檔案是新的 |
| app 啟動並渲染 | 畫面出來了 | **某一版跑起來了**——不保證是哪一版 |

沒有一格是假的。錯的是把三者串起來讀成「我剛寫的程式在裝置上跑了」。

### 這與第 7 條不同

第 7 條是「編得過 ≠ 跑過」。這一條是**「跑過 ≠ 跑的是我建的那一份」**——它發生在第三欄
**已經填上數字之後**。我當時確實有數字(389 MB、381 MB、170 MB),那些數字也確實是量出來的,
只是量的是別的二進位。**一個數字不會說出它來自哪一版。**

### 矯正措施

1. **讓 app 自己說出受測的那件事。** P57 現在印
   `lazy rows: yes/NO`——一行 `backend is any BackendFeatures.LazyListRows`。
2. **加一個同形狀的對照組。** 同一檔、同一寫法,換一個**早已落地**的 protocol:
   `control -- scrolling lists:`。若連它也讀作 `NO`,指向的就是**這個二進位**,而不是那個功能。
   這一步會把一小時縮成幾秒。
3. **在相信任何一者之前,先看產物自己的時間戳。** `ls -l` 那個 `.apk`,與 `adb install` 寫在
   同一個指令裡。`compile.zsh -android` 現在會無條件印出它沒有打包 APK。

### 守衛

> 平台的產物若需要**打包**(Android APK、iOS `.app`、任何 bundle),**建置的退出碼不是產物的
> 時間戳**。量測或截圖之前,`ls -l` 那個產物;而受測的事實要由 app 自己印在畫面上,旁邊放一個
> 已知為真的對照。

---

## 9. Measured the previous build, because building and packaging are different steps

P57 on Android displayed `lazy rows: NO` while logcat showed the eager path --
two independent signals agreeing that a conformance compiled but was invisible at
runtime. The Swift was correct from the first build; the device had never been
given it. `compile.zsh -android` builds into `.build/`, while the APK is packaged
by `test_android.zsh` from a separate swift-bundler build in `.build-bundler/`.

Nothing lied. The compile returned 0 (the source compiles), `adb install` printed
`Success` (that file is installed), and the app rendered (some build ran). The
error was reading the three together as "the code I just wrote ran on the device".

This is not entry 7. That one is "compiles is not ran". This is **"ran is not ran
what I built"**, and it happens *after* the third column has a number in it. I had
numbers -- 389 MB, 381 MB, 170 MB -- and they were real measurements of a
different binary. A number does not say which build it came from.

The guard: when a platform's artifact must be PACKAGED, the build's exit code is
not the artifact's timestamp. `ls -l` the artifact in the same command that
installs it, have the app print the fact under test on screen, and put a control
beside it -- a control reading NO too would have pointed at the binary in seconds.

---

## 10. 在「那個缺陷不可能出現」的唯一平台上完成驗證

**2026-09-16,1 次,1 天。**

### 症狀

把 `"AndroidBackend"` 加進 `Package.swift` 的 `migratedToSwift6`。該 target **只在
`SCUI_ANDROID=1` 時存在**,因此在其餘每一種建置上,manifest 自己的打字守衛會開火:

```
Package.swift:928: Fatal error: migratedToSwift6 names 'AndroidBackend',
which is not a target in this package
```

——套件**根本載入不了**。macOS、iOS、Linux、Windows 在那一刻全部壞掉。

### 為什麼我完全沒看到

因為我驗得很勤:**五次重建、一個 APK、一次上機、在 logcat 裡確認啟動旗標到位。** 每一次都在
Android 上。

而 Android 恰恰是那個名字**確實是一個 target** 的平台——也就是那個 fatal error **不可能發生**的
平台。驗證做得越徹底,離那個缺陷越遠。

抓到它的是幾分鐘後的 `Scripts/test.sh`,而不是那個 Android 迴圈裡的任何一步。

### 這與第 4 關(「在我的平台上通過」)不同

第 4 關是「我只在一個平台上驗過,別的沒驗」。這一條更窄也更刺:**這次改動本身是有條件的,而我選的
驗證平台正是那個「條件成立」的分支。** 那不是覆蓋率不足——那是一個**結構上看不見**的實驗:

| | 條件成立(Android) | 條件不成立(其餘四個) |
| --- | --- | --- |
| 那個名字是 target 嗎? | 是 | **否** |
| 那個守衛會開火嗎? | 不會 | **會** |
| 我跑過嗎? | 五次 | **零次** |

### 矯正措施

> 改動一份**每個平台都會讀**的檔案(manifest、共用腳本、設定)之前,先問:**哪些平台走的是另一條
> 分支?** 然後在宣稱它可用之前,至少跑其中最便宜的那一個。在本樹上那就是 host 上的
> `Scripts/test.sh`——它同時也是最便宜的那一個。

**一次只在自身條件下被驗過的條件式改動,等於沒有被驗過。**

---

## 10. Verified on the one platform where the defect was impossible

Adding `"AndroidBackend"` to `Package.swift`'s `migratedToSwift6`. That target
exists only when `SCUI_ANDROID=1`, so on every other build the manifest's own
typo guard fired -- `migratedToSwift6 names 'AndroidBackend', which is not a
target in this package` -- and the package would not load at all. macOS, iOS,
Linux and Windows were broken.

I verified thoroughly: five rebuilds, an APK, a device run, launch flags checked
in logcat. All of it on Android, which is exactly where the name IS a target and
the fatal error cannot occur. The more carefully I checked, the further I was
from the defect. `Scripts/test.sh` caught it minutes later.

This is not gate 4 ("passes on my platform"). It is narrower: the change was
CONDITIONAL, and the platform I chose to verify on was the branch where the
condition holds. That is not thin coverage -- it is an experiment that cannot
fail.

The guard: before editing anything every platform reads, name the platforms that
take the OTHER branch and run the cheapest one. A conditional change verified
only under its own condition is unverified.

---

## 11. 把測試紀錄丟在錯的目錄裡,而 `.gitignore` 讓它永遠不會被回報

**2026-09-16,1 次,1 天。**

### 症狀

`p17`、`p28`、`p34`、`p48`、`p50`、`p57`、`p63`、`p67`、`p69` 九份 `-debug-events.log` 躺在
**repo 根目錄**。不是被使用者注意到的,是被使用者**用眼睛看目錄列表**注意到的。

成因是我自己:今天有幾次為了抓 stderr 而直接跑二進位——

```
./testapp/output/P70 --debug -actionfile testapp/actions/mac/P70-focus.csv
```

——而那些 app 在沒有 `SCUI_DEBUG_EVENTS_DIR` 時的 fallback 是**當前目錄**。`test.zsh` 會設定它,
指向 `testapp/debug-events/`;手動跑不會。

### 為什麼沒有任何東西報錯

`.gitignore:116` 有 `p*-debug-events.log`。所以:

- `git status` **乾淨**
- `git ls-files` 找到 **0** 個
- 提交、推送、測試套件全部照常通過

那個忽略規則本身是**對的**——這些是產物,不該被追蹤——但它同時讓「產物落在錯的地方」成為一件
**沒有任何工具會說出來的事**。它只會累積。

### 而它不只是垃圾,它是假證據

`coverage-matrix.csv2` 早就為 P34 記下過這個形狀:

> *「一行來自 2026-09-04 的舊紀錄,讀起來與一次新鮮的通過**一模一樣**。」*

一份留在當前目錄的舊日誌,與一份剛剛產生的在畫面上無從分辨。今天我就在
`testapp/debug-events/` 讀 `p70-debug-events.log` 的同時,根目錄躺著一份更舊的同名檔案——這一次
我讀對了那一份,而那是運氣,不是方法。

### 矯正措施

> **手動跑任何測試 app 之前,先設 `SCUI_DEBUG_EVENTS_DIR`,而且指向一個空目錄。**
> ```sh
> SCUI_DEBUG_EVENTS_DIR=$(mktemp -d) ./testapp/output/P70 --debug ...
> ```
> 「一個**空**目錄」是關鍵的那一半:它讓「這一次沒有寫出紀錄」與「上一次的紀錄還在」變成兩個
> 看得出差別的結果。

`.gitignore` 蓋住的東西,沒有任何檢查會替你看。**被忽略不等於無害,只等於安靜。**

---

## 11. Put test logs in the wrong directory, where `.gitignore` guaranteed nobody would report it

Nine `p*-debug-events.log` files sat in the REPOSITORY ROOT. Not caught by a
tool -- caught by a human reading a directory listing.

They are what a test app writes when run by hand: the fallback for
`SCUI_DEBUG_EVENTS_DIR` is the current directory, and `test.zsh` sets it while
running the binary directly does not. I ran binaries directly several times
today to capture stderr.

Nothing reported it because `.gitignore` covers `p*-debug-events.log`, so
`git status` was clean, `git ls-files` found zero, and every commit, push and
test run passed. The ignore rule is right -- these are artefacts -- and it also
makes "artefacts in the wrong place" a thing no tool will ever mention. It only
accumulates.

It is not merely litter. `coverage-matrix.csv2` already recorded this shape for
P34: *a stale line from 2026-09-04 reads exactly like a fresh pass*. A leftover
log in the working directory is indistinguishable from one just written, and
today I read `p70-debug-events.log` from `testapp/debug-events/` while an older
copy of the same name sat at the root. I read the right one by luck.

The guard: before running a test app by hand, set `SCUI_DEBUG_EVENTS_DIR`, and
set it to an EMPTY directory -- `SCUI_DEBUG_EVENTS_DIR=$(mktemp -d)`. Empty is
the load-bearing half: it makes "this run wrote no log" distinguishable from
"last run's log is still there". What `.gitignore` hides, no check will look at
for you. Ignored is not harmless; it is only quiet.

---

## 12. 問了 queue「輪到誰」,沒問 origin「已經有什麼」

**2026-09-16,1 次,1 天。**

### 症狀

`#121` 被**實作了兩次**。合併時 git **沒有報任何衝突**——兩份實作在不同檔案裡——而報出來的是編譯器:

```
error: invalid redeclaration of 'keyboardShortcut(_:modifiers:)'
```

我那一份隨即被整份還原。

### 時間線,而它不是運氣問題

| 時間 | 事件 |
| --- | --- |
| 08:31 | Windows 提交他們的 #121(他們機器上) |
| ~09:30 | 我 fetch。`origin/develop` behind **0**——他們還沒推 |
| **09:56** | **Windows 推上來。他們的 #121 此刻已在 origin** |
| ~10:30 | 我**開始**寫我的 #121 |
| 10:46 | 我提交 |

**有 35 分鐘的預警,而我一次都沒再 fetch。** 09:30 那次 fetch 當下是準的;我把「當下是準的」當成了「現在是準的」。

### 為什麼 queue 檔擋不住

`queue.md` 寫著:

> *「Windows 端把它標為『卡在 Mac』」*

那是真的——**在它被寫下的那一刻**。Windows 後來自己解了套:他們挑了一條走 environment 的路,
那條路**完全不需要 Mac 這邊開任何欄位**。

**一個 queue 檔記錄的是「某人寫下它時相信什麼」,不是「現在成立什麼」。** 它是一份意圖,不是一把鎖;
而一份不會自己過期的意圖,讀起來與現況一模一樣。

### 為什麼 git 結構上看不見

同一個功能的兩份實作,寫在不同檔案,**merge 會乾乾淨淨**。版本控制沒有「這個功能做了兩次」這個概念——
它只認得同一行被兩邊改動。唯一看見它的是編譯器,而那已經是兩份都寫完之後。

因此這件事沒有任何**事後**的檢查擋得住。守衛必須在**開始之前**。

### 矯正措施

> 開始任何一項 queue 項目之前,不要問 queue「輪到誰」,要問 **origin**「**已經有什麼**」:
>
> ```sh
> git fetch && git log origin/develop --oneline -S"<那個 API 的名字>" | head
> ```
>
> 這會在幾秒內找到對方的 commit。**`-S` 搜的是內容,不是訊息**——對方不見得會在標題寫上那個名字。

而在多人共用的分支上,**fetch 是「開始一項任務」的一部分**,不是「開始一個 session」的一部分。

---

## 12. Asked the queue whose turn it was, never asked origin what already existed

`#121` was implemented TWICE. Git reported no conflict at all -- the two
implementations lived in different files -- and the compiler is what reported
it: `invalid redeclaration of 'keyboardShortcut(_:modifiers:)'`. Mine was
reverted in full.

It was not bad luck. Windows pushed their implementation at 09:56; I began
writing mine at about 10:30 and committed at 10:46. My one fetch was at 09:30,
when `origin/develop` really was 0 behind. I treated "accurate then" as "accurate
now" for the rest of the session.

`queue.md` said Windows had marked the item "blocked on Mac", and that was true
when it was written. They then unblocked themselves by choosing a route -- the
environment -- that needed nothing from this side. A queue file records what
someone believed when they wrote it, not what holds now. It is an intention, not
a lock, and an intention that never expires reads exactly like a current fact.

Nor could git catch it: two implementations of one feature in different files
merge cleanly. Version control has no concept of "this feature was built twice";
it only knows about the same lines changing on both sides. So no check AFTER the
work could have caught this. The guard has to come before it.

The guard: before starting a queue item, do not ask the queue whose turn it is;
ask ORIGIN what already exists.

    git fetch && git log origin/develop --oneline -S"<the API name>" | head

`-S` searches content, not messages -- the other side may never name the symbol
in a subject line. And on a shared branch, fetching is part of starting a TASK,
not part of starting a session.

---

## 13. 讀了一份過期的 README,然後動手重建一個**已經存在而且用過**的東西

**2026-09-16,1 次,1 天。**

### 症狀

我需要在 iOS 上送鍵盤事件。`testapp/actions/README.md` 第 23 行寫著:

```
  ios/        empty; planned
```

我據此得出「iOS 沒有驅動途徑」,自己寫了三支 `CGEvent` 驅動器去打 Simulator、然後打 DeviceHub,
失敗之後把「建一個 XCUITest target」列為第一優先,並在 queue 裡寫下**「這正是 `testapp/actions/ios/`
至今空著的真正原因」**。

`ls testapp/actions/ios/` 是 **58 個檔案**。那個 XCUITest runner 早就存在
(`testapp/iosContainer/xcodeTestRunner/Tests/ActionFileUITests.swift`,278 行)、早就接進
`test_ios.zsh --actionfile`、而且早就驅動過真實的點擊——`7f4193dc` 的 commit 訊息就寫著
「P60 在 iOS 上被它的 action file 驅動,而那個 tap 差了 118 點」。

**是使用者說「我記得我們以前做過這個」,我才去查 history 的。**

### 為什麼沒有任何東西擋下來

那句「empty; planned」在被寫下的當天是**真的**。它不會自己過期,而**一份過期的文件讀起來與一份
正確的文件一模一樣**——沒有工具會回報一份 README 與它所描述的目錄不一致。

而我還把它**寫進了新的 queue 條目**,等於把那個錯誤複製到第二個地方,並讓它看起來像是被查證過的。

### 這與第 12 條是同一個病,換了一份文件

第 12 條:問了 `queue.md`「輪到誰」,沒問 origin「已經有什麼」——結果 #121 被做了兩次。
這一條:問了 `README.md`「有沒有」,沒問檔案系統與 git history——結果差點把一個 278 行、已在運作的
runner 重造一次。

**兩次的形狀完全相同:把一份「記錄了某人當時相信什麼」的文件,當成了現況。**

### 真正的缺口(它很小,而且是大聲的)

那個 runner 唯一沒做的是**按鍵**:

```swift
case "keydown", "keyup", "key":
    throw ActionFileError.unsupported(action.kind, action.line)
```

它 **throw**,不是靜默略過——所以它從一開始就把自己的缺口說出來了。真正要做的是把這三個動作接到
`XCUIElement.typeKey(_:modifierFlags:)`,而不是造一個 target。

### 矯正措施

> **在動手建任何基礎建設之前,先問檔案系統與 git,不要問文件。**
>
> ```sh
> ls <那份文件說是空的目錄> | wc -l          # 它真的空嗎
> git log --oneline -- <那個功能會住的路徑>   # 有人做過嗎
> grep -rn "<那個功能的名字>" --include=*.zsh testapp/   # 有人接過嗎
> ```
>
> 三個指令,幾秒鐘。今天它們會省下三支驅動器、兩次 iPad 全循環,以及一條寫錯的 queue 條目。

而看到文件與現況不符時,**先修文件**——否則下一個人會踩同一個坑,而且會以為自己查證過了。

---

## 13. Read a stale README, then set out to rebuild something that already existed and had been used

I needed to send key events on iOS. `testapp/actions/README.md:23` says
`ios/  empty; planned`, so I concluded there was no way to drive iOS, wrote three
`CGEvent` drivers aimed at Simulator and then DeviceHub, and after they failed I
made "build an XCUITest target" the first priority -- writing into the queue that
this was *the real reason `testapp/actions/ios/` is still empty*.

`ls testapp/actions/ios/` is 58 files. The XCUITest runner already exists at
`testapp/iosContainer/xcodeTestRunner/Tests/ActionFileUITests.swift`, is already
wired into `test_ios.zsh --actionfile`, and has already driven real taps --
commit `7f4193dc` is literally "P60 on iOS is driven by its action file, and the
tap was missing by 118 points". I only checked because the user said they
remembered doing it.

Nothing caught it because "empty; planned" was TRUE the day it was written, and a
stale document reads exactly like an accurate one. No tool reports that a README
disagrees with the directory it describes. I then copied the error into a new
queue entry, which made it look verified.

This is entry 12 with a different document. That one asked the queue whose turn
it was instead of asking origin what existed, and #121 got built twice. This one
asked a README whether something existed instead of asking the filesystem and git
history.

The real gap is small and it is LOUD: the runner throws
`ActionFileError.unsupported` for `keydown`, `keyup` and `key`. It says so
itself. The work is wiring those three to
`XCUIElement.typeKey(_:modifierFlags:)`, not building a target.

The guard: before building any infrastructure, ask the filesystem and git, not
the prose. `ls` the directory the document calls empty; `git log --` the path the
feature would live at; `grep` the scripts for its name. Three commands, seconds.
And when a document disagrees with the tree, fix the document first -- otherwise
the next person walks into it believing they checked.

---

## 14. 讀了證據的一半,把過渡狀態當成判決

**次數:1 次 / 1 天(2026-09-16)。而同一天稍早,我才因為「只讀了比較的一端」記下第 8 條。**

**編號 14,不是 10,也不是 13——同一天被迫改號兩次。** 第一次寫下時編了 10,而 10、11、12 在同一天
稍早的合併中已經由 Mac 端用掉了;改成 13 之後,Mac 端在當天下午又以 13 記下另一條(過期的 README),
於是這一條再往後挪成 14。**兩次都不是打錯字,而是同一個形狀:在共用分支上,編號是一個共享資源,
而本機的檔案看不見另一端已經取走哪一個。** 這與第 12 條(問了 queue「輪到誰」、沒問 origin
「已經有什麼」)完全同形,並且發生在記錄第 12 條的那份檔案本身裡面。下一次寫新條目之前,
先 `git fetch && git show origin/develop:mistakes.md | grep '^## '` 看對面用到哪一號。
*Numbered 14 -- not 10, and not 13 either: renumbered twice in one day. 10-12 were taken by the other
machine in a merge that morning, and 13 was taken by its stale-README entry that afternoon. Neither
was a typo: on a shared branch the number is a shared resource, and the local file cannot see which
one the other side has already claimed. Same shape as entry 12, inside the file that records entry 12.
Check `git show origin/develop:mistakes.md | grep '^## '` before choosing a number.*

### 症狀 / What it looks like

一份動作檔重放完成,app 的 log 裡有這四行:

```
DISABLED FOCUS reported true
TEXT FOCUS reported true
DISABLED FOCUS reported false
TEXT FOCUS reported false
```

我讀了第一行,宣告「停用的按鈕接受了焦點」,並據此在兩個 backend 上各寫了一段修法。

**那四行是一個正確行為的完整軌跡。** 框架的寫法是:

```swift
if !backend.focus(widget) {
    binding.wrappedValue = false
}
```

app 自己先把 `@FocusState` 設為 `true`(第一行),框架接著問 backend,backend **回傳 false**,框架把它改回來(第三行)。**那個 `false` 就是拒絕在運作的證據**,而我把它讀成了失敗的證據。

A replay finished and four lines appeared. I read the first, declared that a
disabled control had taken focus, and wrote a fix on two backends. The four lines
are the complete trace of CORRECT behaviour: the app sets the binding optimistically,
the framework asks the backend, the backend refuses, and the framework writes it back.

### 我自己的儀器早就答了,而我只讀了一半

為了診斷,我在 `focus()` 裡加了記錄。它印出:

```
  2 took=false      ← 停用按鈕與純 Text
 51 took=true       ← 其餘可聚焦的 widget
```

**我看到 51 個 `true` 就停住了。** 那 2 個 `false` 正是應該被拒絕的那兩個——答案在同一段輸出裡,
在我下結論之前就已經印出來了。

I had already instrumented `focus()`. It printed 2 `took=false` against 51
`took=true`, and the two falses were exactly the two that should be refused. I
stopped reading at the 51.

### 而畫面上寫著正確答案

P70 把結論畫在視窗上:**`disabled button reports focused: no (correct)`**。
那行字在我先前為了量座標而擷取的兩張圖裡都清清楚楚。這類 app 之所以把結論算繪出來,
正是為了防這件事——而我相信了 log 裡的中間行,沒有相信畫面上的結論行。

The app renders the verdict: `disabled button reports focused: no (correct)`. It
was legible in two screenshots I had already taken. Rendering the verdict is what
these apps do to prevent exactly this, and I believed an intermediate log line
over it.

### 為什麼「更仔細地看 log」擋不住它

因為**每一行都是真的**。沒有任何東西失敗、沒有錯誤訊息、那四行都是誠實的事件回報。
錯的是「在一串狀態轉換中,哪一行是結論」——而那個資訊不在 log 裡,在**產生它的程式碼**裡。

這與第 8 條是同一個家族:那次我比較的兩端只量了一端,這次我讀的證據只讀了一半。
兩次的共同點是**證據已經在手上**。

Every line was true. Nothing failed. What was wrong was which line is the
verdict, and that is not in the log -- it is in the code that emits it. Same
family as entry 8: there I measured one side of a comparison, here I read half of
the evidence. Both times the evidence was already in hand.

### 矯正措施 / The corrective

**一串狀態轉換裡,判決是最後一個值,不是第一個。** 在把某一行 log 當成缺陷之前:

| 問題 | 做法 |
|---|---|
| 這是狀態轉換還是結論? | 找出寫出它的那行程式碼。`onChange` 印的是**轉換** |
| 有沒有更晚的同名行? | `grep` 全部,看最後一個值,不要看第一個 |
| app 有沒有把結論畫在畫面上? | 有就以畫面為準;那是它被畫出來的理由 |
| 我自己的儀器印了什麼? | **讀完**。分佈的兩端都要看,不是只看多的那一端 |

In a sequence of state transitions the verdict is the LAST value, not the first.
Before calling a log line a defect: find the code that emits it (`onChange`
prints transitions), grep for later lines with the same name and read the final
value, prefer the verdict the app renders on screen, and finish reading your own
instrument -- both ends of the distribution, not the big one.

### 守衛 / The guard

**在動作檔的標頭裡寫明「哪一行是判決」。** 動作檔已經會說明每一步在斷言什麼;
此處要多寫一句:結論該從**哪裡**讀。`P70-focus.csv` 現在寫著:判決是 app 畫面上那行
`refused (correct)`,而 log 中的 `DISABLED FOCUS reported true` 是 `@FocusState` 被樂觀設定、
尚未經 backend 回寫的**過渡狀態**。

State in the action file's header WHERE the verdict is read from. These files
already say what each step asserts; this adds which line answers it.

---

## 15. 手寫的 CSV 裡有一個沒加引號的逗號,而那個檔案被**靜默**拒絕

**次數:1 次 / 1 天(2026-09-16)。**

**編號 15,並已先問過對面。** 依第 14 條自己的教訓,寫下之前先跑了
`git fetch && git show origin/develop:mistakes.md | grep '^## '`——對面用到 14。

### 症狀 / What it looks like

寫完 `testapp/actions/mac/P23-column-sorting.csv`、跑了測試,然後:

| 看到的東西 | 它說了什麼 |
| --- | --- |
| harness 的退出碼 | `0` |
| 那支 app | 啟動、算繪、被截圖 |
| 摘要 | `RENDER COMPLETE`,以及 app 自己的診斷行 |
| 我 grep 那份 log | **什麼也沒有** |

於是我認定「動作檔根本沒被重放」,並開始去讀 harness 的原始碼找原因。

**真正的那一行在 `testapp/output/p23-actionfile.log` 裡:**

```
-actionfile: failed: line 48: unknown platform 'not restart'; expected any, macos, ...
```

肇因是我自己寫的一行:

```
click,430,385,frame,left,,,the SAME header again -- this must REVERSE, not restart,macos
                                                                    ^ 這個逗號
```

note 欄裡的一個逗號,把它右邊每一欄都左移一格,於是 `platform` 欄拿到的是 `not restart`。

**而我 grep 不到,不是因為那行不存在。** harness 的摘要只 grep `TEST_SUMMARY_PATTERN`
(`RENDER COMPLETE|rows|selection|table|cell|header`),而 `P23-column-sorting.csv` 不含其中
任何一個字。同一個 harness 在同一天稍早顯示過 `P23-row-**selection**.csv` 的那一行——**因為那個
檔名裡剛好有 "selection"**。過濾器的樣式決定了我看不看得見一次失敗,而樣式是為了「好讀」寫的。

### 為什麼既有的守衛都沒攔下它

| 守衛 | 它問的問題 | 為何漏掉 |
| --- | --- | --- |
| `check_action_files.sh` | results.csv2 引用的檔案**存在嗎** | 它從不打開那些檔案 |
| Swift 測試「every **tracked** action file parses」 | 已被 git 追蹤的檔案解析得過嗎 | 這個檔案五分鐘前才建立,還沒 `git add` |

**「寫出一個檔案」到「提交它」之間,什麼都沒有**——而那正是一個動作檔最要緊的時刻:它是拿來跑的。

### 矯正 / Corrective

新增 `Scripts/check_action_file_fields.sh`,接在 `Scripts/test.sh` 中
`check_action_files.sh` 之後。它掃描 `testapp/actions/*/*.csv`——**不問 git**——並回報
「欄位數多於表頭」與「platform 欄不是已知平台」。

寫出來之後**兩個方向都驗過**:把原來那一行放回去,它以 rc=1 指名該行;移除之後回到 rc=0。
第一版還太嚴(寫死 `row[-1]` 取 platform,而帶 `target` 欄的檔案 platform 不在最後),在乾淨的樹上
就誤報了 `P60-open-settings.csv`——那次誤報本身是好事:它是在「這個守衛第一次執行」時發生的。

這與全域 CLAUDE.md 那條 CSV 規則是同一件事,只是從另一個方向抵達:那條講的是**讀** CSV 時不要用
逗號切割;這一條講的是**寫** CSV 時,一個沒加引號的逗號同樣不會有人報錯。

---

## 15. An unquoted comma in a hand-written CSV, and the file was rejected in silence

**Once, on 2026-09-16.** Numbered 15 after checking the other machine first, which is
entry 14's own lesson: `git show origin/develop:mistakes.md | grep '^## '` said 14.

### What it looks like

The harness exited 0. The app launched, rendered and was screenshotted. The summary printed
`RENDER COMPLETE` and the app's own diagnostics. My grep of the harness log for
`actionfile|replay|error` found **nothing**, so I concluded the file had never been replayed and
went to read the harness source.

The line was in `testapp/output/p23-actionfile.log`:

```
-actionfile: failed: line 48: unknown platform 'not restart'
```

A comma inside an unquoted `note` field shifted every field after it one place left, and `platform`
received `not restart`.

**The grep missed it because the harness only greps its summary pattern** --
`RENDER COMPLETE|rows|selection|table|cell|header` -- and this file's name contains none of those
words. The same harness had shown me the equivalent line earlier the same day for
`P23-row-selection.csv`, because that name happens to contain "selection".

### Why neither existing guard caught it

`check_action_files.sh` asks whether a cited file exists; it never opens one. The Swift suite's
check is "every **tracked** action file parses" and enumerates `git ls-files`, so a file written
five minutes ago is outside it. Between writing an action file and committing it there was nothing
-- which is the window in which an action file is actually used.

### Corrective

`Scripts/check_action_file_fields.sh`, wired into `Scripts/test.sh` directly after
`check_action_files.sh`. It reads every `testapp/actions/*/*.csv` without asking git, and reports
rows with more fields than the header, or a `platform` column that is not a known platform.

Proved in both directions before being trusted: it exits 1 and names the line with the original
defect restored, and 0 without it. Its first version was too strict -- it took `platform` as the
last column, which is wrong for files carrying a trailing `target` -- and reported
`P60-open-settings.csv` on a clean tree. That false positive is worth recording: it happened on the
guard's first run, which is the only cheap time to find one.

Same defect as the global CSV rule, from the other direction: that rule is about splitting a CSV on
commas when READING one. This is about writing one, where an unquoted comma is just as silent.

---

## 16. 用 `path` 當迴圈變數,而那是 `PATH` —— 且症狀出現在十二行之外

**次數:1 次 / 1 天(2026-09-16)。**

**這一條寫在我自己的全域 CLAUDE.md 開頭第三段,標題是「轉換 sh/bash 腳本成 zsh —— 先檢查名稱,
再檢查語法」,而那一段舉的第一個例子就是 `path`。我照樣寫了下去。**

### 症狀 / What it looks like

一支新的掃描腳本 `testapp/window_sizes.zsh`,先以三支 app 試跑:

```
P23  822x652
P50  782x918
P57  642x732
```

完全正常。接著跑完整的 22 支:

```
22 apps, backend -WinUI
app      size         note
testapp/window_sizes.zsh:118: command not found: mktemp
```

把 `mktemp` 換成具名目錄之後,同一行變成 `command not found: date`。**兩次都讀起來像是
「這台機器的 coreutils 沒裝好」**,而我第一次也確實是那樣修的——把依賴換掉,而不是問「為什麼
找不到」。

一支獨立的探針(同一個 zsh、同樣的呼叫方式)顯示 `date`、`mktemp`、`mkdir`、`sleep`、`grep`
全部存在。差別只在**腳本內部**。

### 成因 / The cause

```zsh
for path in "$output_dir"/P*"$backend_suffix".exe; do
```

zsh 把 `path` 與 `PATH` 綁成同一個陣列。這個迴圈把整個搜尋路徑換成了一個 `.exe` 檔的路徑,
此後每一個外部指令都找不到。**沒有任何警告,退出碼是 127,而 127 指向的是「那個指令」,
不是「那個賦值」。**

*zsh ties `path` to `PATH`. A loop variable named `path` replaces the search path with an .exe
file, and every external command afterwards is not found. Nothing warns; the exit code names the
command, not the assignment.*

### 為什麼試跑擋不住它 / Why the trial run passed

**指定 app 名稱的那條路徑根本不會進入那個迴圈。** `window_sizes.zsh P23 P50 P57` 走的是
`if [ "${#wanted[@]}" -gt 0 ]` 分支;只有「不指定、掃全部」才會進入 glob 迴圈。

於是:**短程試跑成功、長程掃描失敗**,而兩者之間我什麼都沒改。這比「一直失敗」更難查,因為
它給了我一個「這支腳本是好的」的證據。

### 矯正措施 / The corrective

- **在 zsh 腳本中永遠不要用 `path` 當變數名**,即使是迴圈變數、即使只用一行。同類保留名稱還有
  `status`、`options`、`argv`、`cdpath`、`manpath`、`fpath`、`watch`。
- **`command not found` 出現在一支剛剛還能跑的腳本裡時,先印 `$PATH`**,不要先換掉那個指令。
  第一次修法(把 `mktemp` 換成具名目錄)完全沒有碰到成因,而且讓下一個失敗換了個名字出現。
- 修好一處之後 `grep -rn 'for path in'` 掃過同目錄的其他腳本——本次為零,但那是查過的零。

*Never name a zsh variable `path`. When `command not found` appears in a script that worked a
moment ago, print `$PATH` before replacing the command: the first fix here swapped `mktemp` for a
named directory, touched nothing, and made the next failure wear a different name.*

---

## 16. `path` as a loop variable is `PATH`, and the symptom lands twelve lines away

1 occurrence, 2026-09-16.

A new sweep script worked for a three-app trial and then failed the full run with
`command not found: mktemp`, then `command not found: date` after that dependency was replaced.
Both read as missing coreutils. A standalone probe found every one of those commands present.

The cause was `for path in "$output_dir"/P*.exe`, which in zsh replaces `PATH` with an .exe file.
The trial passed because naming apps explicitly takes the other branch and never enters the loop --
a short run that works and a long run that does not, with nothing changed between them.

This is the first example in my own global CLAUDE.md's "check names before syntax" section. Knowing
it was not enough; the corrective is to print `$PATH` at the first `command not found` rather than
swapping the command out, which is what I did first and which changed nothing.
