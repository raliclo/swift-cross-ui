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
