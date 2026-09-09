#!/usr/bin/env zsh
#
# One switch, two jobs: ask live sessions whether they are still working, and
# name the next unfinished queue item.
#
# USAGE
#     nohup zsh heartbeats/heartbeat.zsh -on &    start it: asks every 10 minutes
#     zsh heartbeats/heartbeat.zsh -off           stop it
#     zsh heartbeats/heartbeat.zsh                print this and send nothing
#     zsh heartbeats/heartbeat.zsh -status        ON with a pid, ON with no daemon, or OFF
#     zsh heartbeats/heartbeat.zsh -list          the sessions it would reach
#     zsh heartbeats/heartbeat.zsh -next          the next unchecked queue.md item
#     zsh heartbeats/heartbeat.zsh -once          one beat, for a crontab line
#     zsh heartbeats/heartbeat.zsh -m "text"      send something else, once
#
# Ten minutes is the interval that was asked for; HEARTBEAT_INTERVAL overrides it
# in seconds. The interval is not what keeps the cost down -- the switch is: with
# it off, nothing is sent and nothing is spent.
#
# Started with nohup because the loop runs in the FOREGROUND of this process, so
# nohup is what detaches it from the terminal and -off is what stops it. It logs
# to .heartbeat-log rather than nohup.out, so the log sits beside the switch and
# the pid instead of wherever the shell happened to be.
#
# A crontab line, if a daemon is not wanted:
#     */10 * * * * zsh heartbeats/heartbeat.zsh -once
#
# **CRON CAN DO THIS, AND AN EARLIER VERSION OF THIS FILE SAID IT COULD NOT.**
# What it said was that a shell script cannot inject a prompt into a live
# interactive session, and that `multissh` reaches the machine but not the
# session. The second half is false, and the claim was reasoned rather than
# measured -- the shape CLAUDE.md has a rule for. Measured 2026-09-09:
#
#     multissh -F ~/.multissh/generated/config2Win winnode "echo PING_OK"   PING_OK
#     multissh winnode "echo PING_OK"       name resolution failed; the config
#                                           is not optional
#     screen -S s -p 0 -X stuff "...\r"     the live session ran the line
#     multissh -F config2WSL wsl "tmux send-keys -t s '...' Enter"
#                                           REACHED_WSL_LIVE_SESSION
#
# So the real constraint is narrower and checkable: **the session has to be
# running inside a multiplexer**, because that is the only thing holding a pty
# anyone else can write into. Measured on the two machines the same day:
#
#     this Mac                 screen installed, no sockets -- so nothing to hit
#     winnode (MSYS2)          neither tmux nor screen: cannot be pinged at all
#     wsl (Linux 6.18, :16889) tmux 3.6 and screen 4.09 -- this is the side that works
#
# **WSL's tmux does not reach a Windows session that is already running** -- tmux
# writes into a pty it owns, and a process started from a Windows terminal is not
# in it. But it DOES reach a Windows-native process that was STARTED from inside
# a WSL tmux session, and that turns out to be the whole answer for the Windows
# side, which has no tmux, no screen, and no pacman to install either. Measured
# 2026-09-09, every step run from the Mac:
#
#     multissh -F config2WSL wsl "tmux new-session -d -s wintest 'cmd.exe'"
#     multissh -F config2WSL wsl "tmux send-keys -t wintest 'echo ... > C:\Users\Public\hb_probe.txt' Enter"
#     cat /mnt/c/Users/Public/hb_probe.txt   -> REACHED_WINDOWS_NATIVE_VIA_WSL_TMUX
#     ... 'claude --version > C:\...\hb_ver.txt'  -> 2.1.216 (Claude Code)
#
# The process is Windows-native -- it writes to the C: drive and runs the Windows
# claude.exe -- and only its terminal comes from WSL. So a Windows session can be
# pinged if it is started as:
#
#     (in WSL)  tmux new-session -s claude-win 'cmd.exe /c "cd /d C:\path && claude"'
#
# A shared filesystem is not what makes this work and would not have been enough:
# /mnt/c was already mounted while the Windows side was unreachable. What matters
# is which process owns the pty.
#
#     screen -S claude-<name> claude      (macOS, and WSL)
#     tmux new-session -s claude-<name> claude
#
# 一個開關，兩件事：問活著的 session 還在不在工作，以及指出佇列中的下一個未完成項目。
#
# **cron 做得到，而本檔的前一個版本說它做不到。** 當時寫的是「shell 腳本無法把提示注入活著的互動式
# session」以及「`multissh` 到得了那台機器、到不了那個 session」——後半是假的，而那個主張是憑推理
# 下的、不是量出來的，正是 CLAUDE.md 立了規則的那種形狀。2026-09-09 的量測見上方英文。
#
# 因此真正的限制窄得多，而且可檢查：**該 session 必須跑在 multiplexer 之內**，因為那是唯一持有
# 「別人寫得進去的 pty」的東西。同一天在兩台機器上量到：這台 Mac 裝了 screen 但沒有任何 socket；
# winnode（MSYS2）tmux 與 screen 都沒有，因此完全 ping 不到；wsl（Linux 6.18，port 16889）有
# tmux 3.6 與 screen 4.09——那是今天行得通的一側。
#
# **WSL 的 tmux 到不了一個「已經在跑」的 Windows session**——tmux 寫入的是它自己擁有的 pty，而一個
# 從 Windows 終端機啟動的行程不在其中。但它**到得了**一個「從 WSL tmux 內部啟動」的 Windows 原生
# 行程，而那正是 Windows 這一側的完整答案——該側沒有 tmux、沒有 screen，也沒有 pacman 可以裝。
# 2026-09-09 實測，每一步都從 Mac 送出（見上方英文）：一個在 WSL tmux 裡啟動的 cmd.exe 收到了按鍵，
# 在 C: 槽寫出檔案，而 `claude --version` 回報 2.1.216。該行程是 Windows 原生的，只有終端機來自 WSL。
#
# 讓這件事成立的不是共用檔案系統，而且光靠它也不夠：在 Windows 側還連不到的時候，/mnt/c 早就掛好了。
# 真正決定性的是「誰擁有那個 pty」。
#
# 為什麼兩件事合成一支：它們共用那個開關，而開關才是「沒有任務時不要花 token」的關鍵。分成兩支時，
# 打開一個而忘了另一個，讀起來會與「兩個都開了但很安靜」完全相同。

set -euo pipefail

# Captured at file scope. **Inside a zsh function `$0` is the FUNCTION'''s name**,
# not the script'''s path -- so `sed -n ... "$0"` in usage() ran as
# `sed -n ... usage` and failed with "usage: No such file or directory", which
# reads like a usage error from sed rather than like the wrong variable.
# 於檔案層擷取。**在 zsh 的函式內，`$0` 是那個「函式」的名字**，不是腳本的路徑——因此 usage() 裡的
# `sed -n … "$0"` 實際跑成了 `sed -n … usage`，並以 "usage: No such file or directory" 失敗，
# 而那讀起來像是 sed 的用法錯誤，不像是變數取錯。
script_path="${0:a}"
repo_root="${script_path:h:h}"
switch_file="${script_path:h}/.heartbeat-on"
targets_file="${script_path:h}/heartbeat.csv2"
queue_file="$repo_root/queue.md"
message="Are you still working ?"

# Local sessions are matched by name prefix rather than listed, so a restarted
# session with a new pid is still found. `screen -ls` prints "<pid>.<name>".
# 本機 session 以名稱前綴比對而非逐一列出，好讓一個以新 pid 重啟的 session 仍然找得到。
local_prefix="${HEARTBEAT_PREFIX:-claude}"

# multissh is not on PATH and does not find the generated profile by itself:
# measured 2026-09-09, `multissh winnode "echo PING_OK"` failed name resolution
# while the same command with `-F ~/.multissh/generated/config2Win` printed
# PING_OK. The config is therefore not optional.
# multissh 不在 PATH 上，也不會自己找到那份 generated profile：2026-09-09 實測，
# `multissh winnode "echo PING_OK"` 名稱解析失敗，而同一個指令加上
# `-F ~/.multissh/generated/config2Win` 印出了 PING_OK。因此那個 config 不是選配。
multissh_bin="${MULTISSH_BIN:-$HOME/proj/multissh/release/multissh}"
multissh_config="${MULTISSH_CONFIG:-$HOME/.multissh/generated/config2Win}"

# Reads heartbeat.csv2 THROUGH csv2, never by splitting on commas.
#
# The note column contains commas inside quotes, and `cut -d,` would return half
# a sentence and shift every column after it left by one -- silently. The global
# rule in ~/.claude/CLAUDE.md exists because that has already cost this machine
# real data twice.
#
# csv2 emits JSON Lines with named fields, which is turned into tabs here so the
# zsh loop can read it with `read -r`. Tabs, not spaces: session names and config
# paths are single words today but the note column is not, and a space-separated
# format would break the first time someone reorders the columns.
#
# 一律**透過 csv2** 讀取 heartbeat.csv2，絕不以逗號切割。
#
# note 欄的引號內含有逗號，而 `cut -d,` 會回傳半句話，並讓其後每一欄左移一格——而且是靜默的。
# ~/.claude/CLAUDE.md 裡的全域規則之所以存在，是因為那件事已經在這台機器上真實地弄壞過兩次資料。
#
# csv2 會輸出具名欄位的 JSON Lines，此處把它轉成以 tab 分隔，好讓 zsh 的迴圈能用 `read -r` 讀。
# 用 tab 而非空白：session 名稱與設定檔路徑今天都是單一個詞，但 note 欄不是，而以空白分隔的格式
# 會在有人重排欄位的第一天就壞掉。
read_targets() {
    [ -f "$targets_file" ] || return 0
    if ! command -v csv2 >/dev/null 2>&1; then
        # Loud rather than falling back to a comma split. A fallback that
        # "mostly works" is exactly the shape the global rule forbids.
        # 大聲失敗，而不是退回逗號切割。一個「大致上能用」的退路，正是那條全域規則所禁止的形狀。
        printf 'csv2 is not on PATH; %s cannot be read safely\n' "${targets_file:t}" >&2
        return 1
    fi
    csv2 -r --json -i "$targets_file" 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    row = json.loads(line)
    f = row.get("fields")
    if not f:
        continue                      # the meta line csv2 prints first
    if str(f.get("check_required", "")).strip().lower() not in ("yes", "y", "true", "1"):
        continue
    print("\x1f".join([
        f.get("os", ""), f.get("session", ""), f.get("host", ""),
        f.get("mux", "") or "tmux", f.get("config", ""),
        f.get("session_name", "") or f.get("session", ""),
        # session_id is the LOCAL uuid, which is what `claude -r` accepts. The
        # cloud id (session_01...) is deliberately NOT read here: it is the
        # claude.ai/code URL form and -r rejects it.
        # session_id 是**本機** uuid，那才是 `claude -r` 接受的東西。此處刻意不讀雲端那個 id
        # （session_01…）：它是 claude.ai/code 網址的形式，而 -r 不收它。
        f.get("session_id", ""), f.get("method", "") or "session-id",
        f.get("cwd", ""),
    ]))
'
}

print_next() {
    if [ ! -f "$queue_file" ]; then
        printf 'no %s in this tree\n' "${queue_file:t}" >&2
        return 1
    fi
    local next
    next="$(grep -n -m1 '^- \[ \]' "$queue_file" || true)"
    if [ -z "$next" ]; then
        printf 'QUEUE EMPTY -- every item in %s is checked off.\n' "${queue_file:t}"
        return 0
    fi
    printf 'NEXT (%s:%s)\n%s\n' "${queue_file:t}" "${next%%:*}" "${next#*:}"
}

# Defined BEFORE the option handling below, because `-on`'s loop calls it.
# With the definition after the `case`, the daemon started, wrote its pid, logged a
# timestamp every beat and printed `command not found: one_beat` into the log --
# a running daemon that reached nobody. `-status` said ON with a pid the whole time.
# 定義於下方選項處理之前，因為 `-on` 的迴圈會呼叫它。當定義放在 `case` 之後時，daemon 照樣
# 啟動、寫下 pid、每一次心跳都記下時間戳，並在 log 裡印出 `command not found: one_beat`
# ——一個誰也沒送到的執行中 daemon，而 `-status` 全程都回報 ON 與一個 pid。
one_beat() {
    sent=0
    # One row at a time, and every row says which machine it is on and how to
    # reach it. `host` == "local" is the only case that skips multissh: the
    # multiplexer socket is on this machine.
    # 一次一列，而每一列都說明它在哪一台機器上、以及怎麼到得了它。只有 host 等於 "local" 這一種
    # 情況會跳過 multissh：那個 multiplexer 的 socket 就在本機。
    # `session` is the MULTIPLEXER session -- what screen and tmux answer to,
    # and the only name this script can address. `session_name` is the CLAUDE
    # session name, which Claude assigns and which no multiplexer has heard of.
    # They are two namespaces and the table keeps both, because a row that only
    # carried the Claude name would look addressable and would not be.
    # `session` 是 **multiplexer** 的 session——screen 與 tmux 認得的那個名字，也是這支腳本唯一
    # 定址得到的東西。`session_name` 是 **Claude** 的 session 名稱，由 Claude 指派，而任何
    # multiplexer 都沒聽過它。兩者是兩個命名空間，表格兩個都留，因為一列若只帶著 Claude 的名字，
    # 看起來會像是定址得到，而事實上不是。
    # US (0x1f), not a tab. **A tab is whitespace, and zsh's `read` collapses runs
    # of whitespace**, so the local row -- whose `config` column is empty -- lost
    # that field and slid `session_name` into it. The log then said
    # "claude session " with nothing after it while the beat itself worked, which
    # is the kind of wrong that looks like a formatting nit rather than a parse
    # error. 0x1f cannot appear in the CSV and is not whitespace.
    # 用 US（0x1f），不用 tab。**tab 是空白字元，而 zsh 的 `read` 會把連續的空白摺疊掉**，因此
    # 本機那一列——它的 `config` 欄是空的——丟失了該欄位，並讓 `session_name` 滑進去。於是 log 印出
    # 「claude session 」後面空無一物，而心跳本身是好的；那種錯誤看起來像排版小疵，不像解析錯誤。
    # 0x1f 不可能出現在該 CSV 裡，而且它不是空白字元。
    while IFS=$'\x1f' read -r os session host mux config session_name session_id method cwd; do
        [ -n "$session" ] || continue
        # TWO WAYS TO REACH A SESSION, AND THEY ARE NOT THE SAME ACT.
        #
        #   session-id   `claude -p -r <id> "<message>"` appends a HEADLESS turn
        #                to that conversation and returns the reply here, where
        #                it is logged. No multiplexer anywhere, which is what
        #                makes the Windows side reachable at all: measured
        #                2026-09-09, claude is on winnode via multissh and
        #                reports 2.1.216, while that machine has no tmux, no
        #                screen and no pacman to install either.
        #   mux          types into a LIVE terminal, where a human sees it and
        #                the running session answers in place. Needs screen or
        #                tmux to own the pty.
        #
        # The first is the default because it works everywhere; the second is
        # kept because it is the only one a person watching the terminal sees.
        #
        # 到得了一個 session 的兩種方式，而它們並不是同一件事。
        #
        #   session-id   `claude -p -r <id> "<訊息>"` 會在那段對話上追加一個**無頭**回合，並把回覆
        #                帶回此處記進 log。全程不需要任何 multiplexer，而那正是 Windows 側之所以
        #                到得了的原因：2026-09-09 實測，claude 經由 multissh 就在 winnode 上、
        #                回報 2.1.216，而那台機器沒有 tmux、沒有 screen，也沒有 pacman 可以裝。
        #   mux          打進一個**活著的**終端機，人看得到，而正在跑的那個 session 就地回答。
        #                需要 screen 或 tmux 擁有那個 pty。
        #
        # 前者是預設，因為它到處都行得通；後者保留，因為只有它會被盯著終端機的人看到。
        if [ "$method" = "session-id" ]; then
            case "$session_id" in
                ""|"("*)
                    # A placeholder id is not an id. Said out loud, because a
                    # `claude -r "(pending ...)"` would fail in a way that reads
                    # like the machine being down.
                    # 佔位字串不是 id。明講出來，因為 `claude -r "(pending …)"` 的失敗讀起來會像是
                    # 那台機器掛了。
                    printf 'SKIP %s/%s -- no session_id yet\n' "$os" "$session_name" >&2
                    continue
                    ;;
            esac
            # **`claude -r` resolves a session id WITHIN A PROJECT DIRECTORY.**
            # Run from anywhere else it answers "No conversation found with
            # session ID: ..." -- which it did on the first real beat to the
            # Windows machine, because the remote command landed in the login
            # home rather than in the checkout. The cwd column is why that is
            # per row: the two machines keep this tree in different places.
            # **`claude -r` 是在一個「專案目錄之內」解析 session id 的。** 從別處執行時，它會回答
            # "No conversation found with session ID: …"——第一次真的送往 Windows 的那一拍就是如此，
            # 因為那個遠端指令落在登入的 home 而不是這份 checkout 裡。cwd 欄之所以逐列設定，正是
            # 因為兩台機器把這棵樹放在不同的位置。
            claude_cmd="cd ${cwd:-.} && claude -p -r $session_id \"$message\""
            if [ "$host" = "local" ]; then
                reply="$(eval "$claude_cmd" 2>&1 | head -3 || true)"
            else
                config="${config:-$multissh_config}"
                config="${config/#\~/$HOME}"
                reply="$("$multissh_bin" -F "$config" "$host" "$claude_cmd" 2>&1 | head -3 || true)"
            fi
            # **An error message is also a reply, and the first version of this
            # counted one as a success.** `claude -r` with an id it cannot
            # resolve prints "No conversation found with session ID: ..." on
            # stdout and the beat was reported as delivered. Non-empty is not
            # the test; not-an-error is.
            # **一句錯誤訊息也是一個回覆，而本段的第一個版本把它算成了成功。** `claude -r` 在無法
            # 解析某個 id 時，會在 stdout 印出 "No conversation found with session ID: …"，於是那一拍
            # 被回報為已送達。判準不是「非空」，而是「不是錯誤」。
            case "$reply" in
                *"No conversation found"*|*"not found"*|*"Error"*|*"error:"*)
                    printf 'FAILED %s/%s (%s) -- %s\n' \
                        "$os" "$session_name" "$host" "$reply" >&2
                    continue
                    ;;
            esac
            if [ -n "$reply" ]; then
                printf 'asked %s/%s (%s) -- replied: %s\n' \
                    "$os" "$session_name" "$host" "$reply"
                sent=$(( sent + 1 ))
            else
                # Empty is a failure here, unlike the mux route where silence is
                # normal. A resume that returns nothing did not reach anything.
                # 此處「空的」就是失敗，這與 mux 那條路不同——在那裡沉默是常態。一次什麼都沒回傳的
                # resume，代表它什麼都沒到達。
                printf 'FAILED %s/%s (%s) -- no reply from claude -r\n' \
                    "$os" "$session_name" "$host" >&2
            fi
            continue
        fi

        # **The carriage return has to be a REAL one, and a literal backslash-r
        # is silently accepted.** Measured 2026-09-09 with two screen sessions
        # side by side: `stuff 'text\r'` delivered the text with no Enter, so the
        # session never ran the line and wrote nothing, while `screen` still
        # exited 0 and this script still printed "sent". `stuff "text$(printf
        # '\r')"` worked. The remote form keeps the `$(printf ...)` unexpanded on
        # purpose -- the REMOTE shell expands it, which is why it is in single
        # quotes here.
        #
        # **那個 carriage return 必須是真的,而字面的反斜線加 r 會被靜默接受。** 2026-09-09 以兩個
        # 並排的 screen session 實測:`stuff 'text\r'` 送出的是「沒有 Enter 的文字」,於是該 session
        # 從未執行那一行、也沒有寫出任何東西,而 `screen` 依然以 0 結束、本腳本依然印出「sent」。
        # `stuff "text$(printf '\r')"` 才是對的。遠端的那個形式刻意讓 `$(printf …)` 不在此處展開
        # ——由**遠端**的 shell 展開它，所以此處用的是單引號。
        case "$mux" in
            tmux)   send_cmd="tmux send-keys -t $session '$message' Enter" ;;
            screen)
                if [ "$host" = "local" ]; then
                    send_cmd="screen -S $session -p 0 -X stuff \"$message$(printf '\r')\""
                else
                    send_cmd='screen -S '"$session"' -p 0 -X stuff "'"$message"'$(printf "\r")"'
                fi
                ;;
            *)
                printf 'unknown mux "%s" for %s/%s -- use tmux or screen\n' \
                    "$mux" "$os" "$session" >&2
                continue
                ;;
        esac

        if [ "$host" = "local" ]; then
            # -p 0 addresses the session's first window: without it, `stuff` goes
            # to whichever window is current, which for a session someone has been
            # using is not necessarily the one running claude.
            # -p 0 指定該 session 的第一個視窗：少了它，`stuff` 會送到當前視窗，而對一個有人用過的
            # session 來說，那不一定是跑著 claude 的那一個。
            if eval "$send_cmd" 2>/dev/null; then
                printf 'sent to %s/%s (local, claude session %s)\n' \
                    "$os" "$session" "$session_name"
                sent=$(( sent + 1 ))
            else
                printf 'FAILED local %s/%s -- is it running under %s?\n' \
                    "$os" "$session" "$mux" >&2
            fi
        else
            config="${config:-$multissh_config}"
            # ~ is not expanded inside a CSV field, so it arrives literally and
            # multissh would look for a directory named "~". Expanded here rather
            # than in the file, because the file is read by other machines too.
            # CSV 欄位裡的 ~ 不會被展開，因此它會原樣抵達，而 multissh 會去找一個名為 "~" 的目錄。
            # 在此處展開而不在檔案裡寫死，因為那個檔案也會被其他機器讀到。
            config="${config/#\~/$HOME}"
            if "$multissh_bin" -F "$config" "$host" "$send_cmd" >/dev/null 2>&1; then
                printf 'sent to %s/%s via %s (claude session %s)\n' \
                    "$os" "$session" "$host" "$session_name"
                sent=$(( sent + 1 ))
            else
                # Loud. A failed send that printed nothing would leave the count
                # looking like a quiet machine rather than an unreachable one.
                # 大聲失敗。一次什麼都不印的傳送失敗，會讓計數讀起來像是一台安靜的機器，而不是
                # 一台連不上的機器。
                printf 'FAILED to reach %s/%s via %s\n' "$os" "$session" "$host" >&2
            fi
        fi
    done < <(read_targets)

    # The count, always, including zero. "Armed and reached nothing" is the state
    # this script is most likely to be in, and it must not read as success.
    # 一律印出數目，包含 0。「已開啟但一個也沒送到」正是這支腳本最可能處於的狀態，而它不可以讀起來
    # 像是成功。
    printf 'heartbeat: %d target(s)\n' "$sent"
    [ "$sent" -gt 0 ] || printf 'heartbeat: armed but reached nothing -- see --list\n' >&2

}

pid_file="${script_path:h}/.heartbeat-pid"
log_file="${script_path:h}/.heartbeat-log"
interval="${HEARTBEAT_INTERVAL:-600}"

usage() {
    sed -n '3,27p' "$script_path" | sed 's/^#$//; s/^# //'
}

# Both spellings. The single dash is what gets typed (`nohup zsh
# heartbeats/heartbeat.zsh -on`), the double dash is what the rest of this tree's
# scripts use, and refusing one of them would be a papercut with no upside.
# 兩種寫法都收。單破折號是實際會被打出來的那一種（`nohup zsh heartbeats/heartbeat.zsh -on`），
# 雙破折號則與這棵樹其他腳本一致；只認其中一種，是一個沒有任何好處的小刺。
case "${1:-}" in
    -on|--on)
        if [ -e "$switch_file" ] && [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
        then
            # Refusing a second daemon rather than starting one. Two loops would
            # double every ping and neither pid file would name both, so `-off`
            # would stop one and leave the other running -- and a session being
            # asked twice per beat looks like a busy machine, not a bug.
            # 拒絕啟動第二個 daemon，而不是照做。兩個迴圈會讓每一次 ping 都變成兩次，而 pid 檔
            # 只認得其中一個，於是 `-off` 會停掉一個、留下另一個——而一個 session 每次心跳被問兩遍，
            # 看起來像是機器很忙，不像是一個缺陷。
            printf 'heartbeat already running (pid %s)\n' "$(cat "$pid_file")" >&2
            exit 1
        fi
        : > "$switch_file"
        printf '%s\n' "$$" > "$pid_file"
        printf 'heartbeat ON -- pid %s, every %ss, log %s\n' "$$" "$interval" "${log_file:t}"
        # The loop is IN THE FOREGROUND, which is what makes `nohup ... &` the
        # documented way to start it: nohup backgrounds and detaches this
        # process, and the loop then outlives the terminal. Running it in the
        # background from in here instead would make `nohup` a no-op and leave
        # the user with no pid to stop.
        # 這個迴圈跑在**前景**，而那正是「`nohup … &` 是啟動方式」的原因：nohup 會把這個行程放到
        # 背景並脫離終端機，於是迴圈的壽命長於該終端機。若改由此處自行放到背景，`nohup` 就成了空操作，
        # 而使用者也拿不到一個可以用來停止它的 pid。
        while [ -e "$switch_file" ]; do
            printf -- '--- %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
            one_beat >> "$log_file" 2>&1 || true
            # Slept in short steps so `-off` is noticed within a second rather
            # than within the interval. A ten-minute sleep would mean the switch
            # file is gone and the daemon still there, which reads as `-off`
            # having failed.
            # 以短步長睡眠，好讓 `-off` 在一秒內、而非在一個間隔之後被察覺。睡滿十分鐘會造成
            # 「開關檔已消失、daemon 卻還在」，而那讀起來會像是 `-off` 失效了。
            local waited=0
            while [ "$waited" -lt "$interval" ] && [ -e "$switch_file" ]; do
                sleep 1
                waited=$(( waited + 1 ))
            done
        done
        rm -f "$pid_file"
        printf 'heartbeat stopped\n' >> "$log_file"
        exit 0
        ;;
    -off|--off)
        rm -f "$switch_file"
        # The switch alone would be enough within a second, but a daemon whose
        # machine slept, or whose sleep is wedged, would linger. Signalling as
        # well makes `-off` mean stopped rather than probably stopped.
        # 光靠開關檔在一秒內就足夠了，但一個「機器睡過」或「sleep 卡住」的 daemon 會留著。同時送出
        # 信號，讓 `-off` 的意思是「已停止」而不是「大概停了」。
        if [ -f "$pid_file" ]; then
            pid="$(cat "$pid_file")"
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                printf 'heartbeat OFF -- stopped pid %s\n' "$pid"
            else
                printf 'heartbeat OFF -- pid %s was already gone\n' "$pid"
            fi
            rm -f "$pid_file"
        else
            printf 'heartbeat OFF\n'
        fi
        exit 0
        ;;
    -status|--status)
        if [ -e "$switch_file" ]; then
            if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                printf 'ON -- pid %s\n' "$(cat "$pid_file")"
            else
                # Armed with nobody home. Said out loud because it is the state
                # that otherwise reads as running: the switch is on, and no
                # heartbeat is being sent by anyone.
                # 開著，但沒有人在家。明講出來，因為這正是那個「否則會讀成正在執行」的狀態：
                # 開關是開的，而沒有任何人在送心跳。
                printf 'ON but no daemon -- start it with `nohup zsh %s -on &`\n' "${script_path:t}"
            fi
        else
            printf 'OFF\n'
        fi
        exit 0
        ;;
    -once|--once)
        # One beat, for cron. The daemon is the default way in; this is here so
        # a crontab line does not need a daemon at all.
        # 送一次，給 cron 用。daemon 是預設的用法；這個選項的存在，是為了讓一行 crontab 完全不需要
        # 任何 daemon。
        if [ ! -e "$switch_file" ]; then
            printf 'IDLE -- heartbeat off. `zsh %s -on` to arm it.\n' "${script_path:t}"
            exit 0
        fi
        one_beat
        exit 0
        ;;
    -next|--next) print_next; exit $? ;;
    -list|--list)
        # Prints the whole table, then the subset that would actually be sent
        # to. The two differ by check_required, and showing only the second
        # would make a row switched off look like a row that was never added.
        # 先印出整張表，再印出「真正會被送到」的子集。兩者的差別在 check_required，而只印後者會讓
        # 一個「被關掉的列」看起來像是一個「從來沒被加進去的列」。
        printf 'targets in %s:\n' "${targets_file:t}"
        if command -v csv2 >/dev/null 2>&1; then
            csv2 -r --json -i "$targets_file" 2>/dev/null | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    f = json.loads(line).get("fields")
    if not f:
        continue
    method = f.get("method","") or "session-id"
    via = method if method == "session-id" else f.get("mux","")
    print("  [%s] %-8s %-24s host=%-8s via=%-11s id=%s" % (
        "x" if str(f.get("check_required","")).lower() in ("yes","y","true","1") else " ",
        f.get("os",""), f.get("session_name","") or f.get("session",""),
        f.get("host",""), via, f.get("session_id","") or "(none)"))
'
        else
            printf '  csv2 is not on PATH; refusing to parse %s by hand\n' "${targets_file:t}" >&2
        fi
        printf 'would send to:\n'
        read_targets | awk -F'\x1f' '{ printf "  %s/%s via %s (%s)\n", $1, $6, $3, $8 }'
        # Said out loud, because "no rows are switched on" and "the file could
        # not be read" produce the same silence otherwise.
        # 明講出來，因為「沒有任何一列被開啟」與「這個檔案讀不到」否則會產生同樣的沉默。
        [ -n "$(read_targets)" ] || printf '  (none -- set check_required to yes on a row)\n'
        exit 0
        ;;
    -m)
        shift
        message="${1:?-m needs a message}"
        shift || true
        one_beat
        exit 0
        ;;
    ""|-h|-help|--help)
        # **No argument prints usage and sends nothing.** A bare run used to
        # send a beat, which made an accidental invocation indistinguishable
        # from an intended one, and made `--help` the thing you had to remember.
        # **不帶參數時印出用法，而且不送出任何東西。** 過去裸執行會送出一次心跳，那讓「手滑執行」
        # 與「刻意執行」變得無從分辨，也讓 `--help` 成了必須記得的那一個。
        usage
        exit 0
        ;;
    *)
        printf 'unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 1
        ;;
esac
