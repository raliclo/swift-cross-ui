# heartbeats

定期問各個 Claude session「還在工作嗎」,並把回覆記下來。

Asks each Claude session whether it is still working, on an interval, and logs
what comes back.

```sh
nohup zsh heartbeats/heartbeat.zsh -on &   # 開:每 100 分鐘問一次
zsh heartbeats/heartbeat.zsh -off          # 關
zsh heartbeats/heartbeat.zsh               # 不帶參數 = 印用法,不送任何東西
zsh heartbeats/heartbeat.zsh -list         # 這張表,以及其中真正會被送到的那些
zsh heartbeats/heartbeat.zsh -f fleet.csv2 -on   # 換一份清單
```

`-f` 可指定另一份同格式的 `.csv2`。**開關、pid 與 log 都跟著檔案走**,因此兩份清單可以同時跑,
`-f fleet.csv2 -off` 停的是 fleet 那一個、而不會動到預設那一個。若共用單一開關,`-off` 會停掉
「剛好最後啟動的那一個」並回報成功。

| 檔案 | 是什麼 |
| --- | --- |
| `heartbeat.zsh` | 那支腳本 |
| `heartbeat.csv2` | 那張表:一列一個 session |
| `.heartbeat-on` | 開關。存在即為開,不納入版控 |
| `.heartbeat-pid` | 執行中 daemon 的 pid |
| `.heartbeat-log` | 每一拍的紀錄,含各個 session 的回覆 |

---

## 一、為什麼存在 / Why it exists

因為一次會**產生零行輸出**的失敗:一個工作單位做完了、報告寫好了、該回合結束——而清單上還有
沒開始的項目。沒有任何東西失敗。使用者發現它的方式,是連問兩次「Are you still working ?」。

紀錄在 [`../mistakes.md`](../mistakes.md) 第 1 條。這個資料夾就是那條的矯正措施。

Because of a failure that produces no output at all: a unit of work finishes, the
report is written, the turn ends, and items nobody started stay on the list.
Nothing fails. It was found by a human asking twice. See `../mistakes.md` entry 1.

---

## 二、那張表 / The table

`heartbeat.csv2` 有**兩列表頭**(英文、中文),這是 `.csv2` 的格式;只寫一列時 `csv2` 會把第一筆
資料當成第二列表頭吃掉,而且不會報錯。

| 欄位 | 意義 |
| --- | --- |
| `date` | 該列最後一次被查證的日期 |
| `os` | `macos` / `windows` / `wsl` / `linux` |
| `session` | **multiplexer** 的 session 名稱——screen 或 tmux 認得的那個 |
| `session_name` | **Claude** 的 session 名稱——Claude 自己指派的那個 |
| `session_id` | **本機** session UUID——`~/.claude/projects/<proj>/<uuid>.jsonl` 的檔名,`claude -r` 吃的就是它 |
| `cloud_session_id` | `claude.ai/code/<id>` 那個形式,出現在 commit 的 `Claude-Session:` trailer。**`-r` 不收它**,留著只是為了對照 |
| `cwd` | 該機器上這棵樹的位置。`claude -r` 是**在專案目錄之內**解析 session 的 |
| `method` | `session-id`(預設)或 `mux` |
| `check_required` | `yes` 才會被送到。這是那個「一列一列的開關」 |
| `host` | `local`,或一個 multissh 主機名 |
| `mux` | `screen` 或 `tmux`,只有 `method=mux` 時才用得到 |
| `config` | multissh 的設定檔路徑 |
| `note` | 該列是怎麼被查證的 |

**`session` 與 `session_name` 是兩個命名空間,而這不是重複。** Claude 為自己的 session 命名,
screen 與 tmux 為它們的命名,而這支腳本在 `mux` 模式下只定址得到後者。一列若只帶著 Claude 的
名字,看起來會像是定址得到,實際上不是。

`session` and `session_name` are two namespaces, not a duplicate. Claude names
its own sessions; screen and tmux name theirs; the mux route can only address the
second. A row carrying only the Claude name would look addressable and would not be.

### 一律用 `csv2` 讀寫這個檔

```sh
csv2 -r -i heartbeats/heartbeat.csv2                        # 讀
csv2 -update 1:7 yes -i heartbeats/heartbeat.csv2 --in-place # 打開第 1 列
csv2 -append '...' -i heartbeats/heartbeat.csv2 --in-place    # 加一列
```

`note` 欄的引號內含有逗號。`cut -d,` 會回傳半句話,並讓其後每一欄左移一格——**而且不會報錯**。
腳本在 `csv2` 不在 PATH 上時會**大聲失敗**,而不是退回逗號切割。

The note column has commas inside quotes; `cut -d,` returns half a value and
shifts every later column left, with no error. The script fails loudly when
`csv2` is missing rather than falling back to a comma split.

---

## 三、兩種送達方式,而它們不是同一件事 / Two routes, not the same act

| method | 做什麼 | 需要什麼 |
| --- | --- | --- |
| `session-id` | `claude -p -r <id> "<訊息>"`——在那段對話上追加一個**無頭**回合,並把回覆帶回腳本、記進 log | 什麼都不需要,只要那台機器上有 `claude` |
| `mux` | 打進一個**活著的**終端機,人看得到,正在跑的那個 session 就地回答 | 該 session 必須跑在 screen 或 tmux 之內 |

預設是 `session-id`,因為它到處都行得通。`mux` 保留下來,因為**只有它會被盯著終端機的人看到**。

2026-09-09 實測(全部從這台 Mac 送出):

| 量測 | 結果 |
| --- | --- |
| `claude -p -r <id> "Are you still working ?"`(拋棄式 session) | 回傳同一個 session id 與一句真的回覆 |
| 同上,但在錯誤的目錄執行 | `No conversation found with session ID: …`——**它印在 stdout,而第一版腳本把它算成了成功** |
| 加上 `cd <cwd> &&` 之後送往 Windows | Windows 那個 session 真的回話了 |
| `multissh -F config2Win winnode "claude --version"` | `2.1.216 (Claude Code)` |
| `multissh winnode "echo PING_OK"`(不給 `-F`) | 名稱解析失敗——那個 config 不是選配 |
| `screen -S s -p 0 -X stuff "…$(printf '\r')"` | 該 session 執行了送進去的那一行 |
| Windows 端的 tmux / screen / pacman | **三者皆無** |
| WSL(port 16889) | tmux 3.6、screen 4.09 |

---

## 四、Windows 那一側 / The Windows side

**共用檔案系統不是重點,而且光靠它不夠。** Windows 側連不到的那段時間,`/mnt/c` 早就掛好了。
決定性的是「誰擁有那個 pty」。

有兩條路,都實測過:

1. **`session-id`(現行做法,較簡單)。** `multissh` 直接在 winnode 上執行 `claude -p -r <id>`。
   不需要 multiplexer,而那正好,因為那台機器一個都沒有、也沒有 pacman 可以裝。
2. **`mux`,經由 WSL 的 tmux。** 一個**從 WSL tmux 內部啟動**的 Windows 原生行程是打得到的,
   因為 pty 屬於 WSL、而行程屬於 Windows:

   ```sh
   # 在 WSL 裡
   tmux new-session -s Swift-Cross-UI-Windows 'cmd.exe /c "cd /d C:/proj/swift-cross-ui && claude"'
   ```

   實測:以此方式啟動的 `cmd.exe` 收下了從 Mac 送出的按鍵、在 C: 槽寫出檔案,並讓
   `claude --version` 回報 2.1.216。

**WSL 的 tmux 到不了一個「已經在 Windows 終端機裡跑著」的 session。** 要在哪一邊被 ping,
就必須在哪一邊啟動。

A shared filesystem is not what makes this work: `/mnt/c` was already mounted
while the Windows side was unreachable. What matters is which process owns the
pty. The session-id route sidesteps that entirely, which is why it is the default.

---

## 五、跑起來才發現的三個缺陷 / Three defects that only running it found

每一個都**沒有讓任何工具報錯**,而這正是它們被記在這裡的原因。

| 缺陷 | 它看起來像什麼 |
| --- | --- |
| `screen -X stuff 'text\r'` | 字面的反斜線加 r **不是** Enter。文字送到了、那一行從未執行,而 `screen` 以 0 結束、腳本印出 `sent` |
| 用 tab 當欄位分隔符 | tab 是空白字元,zsh 的 `read` 會摺疊連續空白;本機那一列的空 `config` 欄消失,`session_name` 滑了進去。log 印出「claude session 」後面空無一物,而心跳本身是好的 |
| `one_beat` 定義在呼叫它的 `case` 之後 | daemon 照樣啟動、寫下 pid、每一拍記下時間戳,並把 `command not found` 印進 log——一個誰也沒送到的執行中 daemon,而 `-status` 全程回報 ON |
| 迴圈裡的指令吃掉 stdin | 這個迴圈由 `done < <(read_targets)` 餵入,而 `claude -p` 讀了 stdin——於是它吃掉的是剩下的**資料列**。兩列都開著時只送出一列,而輸出寫著 `heartbeat: 1 target(s)`:對「送出了什麼」為真,對「從未看見的那一列」則沉默。修法是迴圈內每個指令都加 `< /dev/null` |
| `awk -F'\x1f'` | BSD 的 awk 不把十六進位那個形式當分隔符,而是靜默地把整筆記錄當成單一欄位。`-list` 於是印出整列黏在一起——看起來像排版小疵。改用八進位 `\037` |

第三個是這支腳本自己「必須大聲」的理由:它一律印出目標數目(包含 0),而「已開啟但一個也沒送到」
會另外再說一次。

None of the three made any tool report an error, which is why they are listed
here. The third is why the script always prints the target count including zero,
and says "armed but reached nothing" separately.

---

## 六、成本 / What it costs

**壓低成本的不是那個間隔,是那個開關。** 關閉時,一次跳動只會執行這支腳本、印出 `IDLE`、結束
——不聯絡任何人,也不花掉任何東西。`check_required` 則是第二層:只有標成 `yes` 的列會被送到。

`session-id` 的每一拍會在對方那邊產生一個真的回合(因此會花 token);`mux` 的每一拍只是一次按鍵
注入,由那個活著的 session 自行決定要不要回應。

The switch is what keeps the cost down, not the interval; `check_required` is the
second layer. A session-id beat costs a real turn on the other side; a mux beat
is only a keystroke.

---

## 七、`/loop` 與 cron / Both work

```
*/10 * * * * cd /Volumes/Windows/proj_Win/swift-cross-ui && zsh heartbeats/heartbeat.zsh -once
```

或直接 `nohup zsh heartbeats/heartbeat.zsh -on &`,它自己帶迴圈。

而如果要問的是「**這個** session 的下一件事是什麼」,用的是 `-next` 搭配 `/loop`——它從正在做事
的那個 session 內部重新進入,因此下一個項目是由必須採取行動的那個 session 自己讀到的,而不是
被別人打進去的:

```
/loop 20m zsh heartbeats/heartbeat.zsh -next and do what it says
```
