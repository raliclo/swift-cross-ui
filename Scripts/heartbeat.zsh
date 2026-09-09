#!/usr/bin/env zsh
#
# One switch, two jobs: ask live sessions whether they are still working, and
# name the next unfinished queue item.
#
# USAGE
#     nohup zsh Scripts/heartbeat.zsh -on &    start it: asks every 10 minutes
#     zsh Scripts/heartbeat.zsh -off           stop it
#     zsh Scripts/heartbeat.zsh                print this and send nothing
#     zsh Scripts/heartbeat.zsh -status        ON with a pid, ON with no daemon, or OFF
#     zsh Scripts/heartbeat.zsh -list          the sessions it would reach
#     zsh Scripts/heartbeat.zsh -next          the next unchecked queue.md item
#     zsh Scripts/heartbeat.zsh -once          one beat, for a crontab line
#     zsh Scripts/heartbeat.zsh -m "text"      send something else, once
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
#     */10 * * * * zsh Scripts/heartbeat.zsh -once
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
switch_file="$repo_root/.heartbeat-on"
targets_file="$repo_root/.heartbeat-targets"
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

list_local() {
    # `|| true` is load-bearing under `set -o pipefail`: `screen -ls` exits 1
    # when there are no sockets, which is the ORDINARY case here, and the
    # pipeline's failure would otherwise take the whole script down at --list.
    # Measured 2026-09-09: --list exited 1 and printed an empty list, which
    # reads as a broken script rather than as "no sessions are under screen".
    # 在 `set -o pipefail` 之下這個 `|| true` 是必要的：沒有任何 socket 時 `screen -ls` 以 1 結束，
    # 而那在此處是常態；該管線的失敗會讓整支腳本在 --list 時倒下。2026-09-09 實測：--list 以 1
    # 結束並印出空清單，讀起來像腳本壞了，而不是「沒有 session 跑在 screen 裡」。
    { screen -ls 2>/dev/null || true; } | awk -v p="$local_prefix" '
        $1 ~ /^[0-9]+\./ {
            name = substr($1, index($1, ".") + 1)
            if (index(name, p) == 1) print $1
        }'
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
    for target in $(list_local); do
        # -p 0 addresses the session's first window: without it, `stuff` goes to
        # whichever window is current, which for a session someone has been using is
        # not necessarily the one running claude.
        # -p 0 指定該 session 的第一個視窗：少了它，`stuff` 會送到當前視窗，而對一個有人用過的 session
        # 來說，那不一定是跑著 claude 的那一個。
        screen -S "$target" -p 0 -X stuff "$message$(printf '\r')"
        printf 'sent to local %s\n' "$target"
        sent=$(( sent + 1 ))
    done

    # Remote targets, one per line:
    #
    #     <host> <session-name> [tmux|screen] [multissh-config-path]
    #
    # The last two columns exist because the two remote machines are not the same
    # machine and do not have the same tools -- see the measurements in the header.
    # 遠端目標，一行一個。後兩欄之所以存在，是因為那兩台遠端並非同一台機器、工具也不同——見檔頭的量測。
    if [ -f "$targets_file" ]; then
        while read -r host name mux config; do
            case "$host" in ''|\#*) continue ;; esac
            [ -n "$name" ] || continue
            mux="${mux:-tmux}"
            config="${config:-$multissh_config}"
            case "$mux" in
                tmux)   remote_cmd="tmux send-keys -t $name '$message' Enter" ;;
                screen) remote_cmd="screen -S $name -p 0 -X stuff '$message\r'" ;;
                *)
                    printf 'unknown multiplexer "%s" for %s:%s -- use tmux or screen\n' \
                        "$mux" "$host" "$name" >&2
                    continue
                    ;;
            esac
            if "$multissh_bin" -F "$config" "$host" "$remote_cmd" >/dev/null 2>&1; then
                printf 'sent to %s:%s\n' "$host" "$name"
                sent=$(( sent + 1 ))
            else
                # Loud. A failed remote send that printed nothing would leave the
                # count looking like a quiet machine rather than an unreachable one.
                # 大聲失敗。一次什麼都不印的遠端傳送失敗，會讓計數讀起來像是一台安靜的機器，而不是
                # 一台連不上的機器。
                printf 'FAILED to reach %s:%s\n' "$host" "$name" >&2
            fi
        done < "$targets_file"
    fi

    # The count, always, including zero. "Armed and reached nothing" is the state
    # this script is most likely to be in, and it must not read as success.
    # 一律印出數目，包含 0。「已開啟但一個也沒送到」正是這支腳本最可能處於的狀態，而它不可以讀起來
    # 像是成功。
    printf 'heartbeat: %d target(s)\n' "$sent"
    [ "$sent" -gt 0 ] || printf 'heartbeat: armed but reached nothing -- see --list\n' >&2

}

pid_file="$repo_root/.heartbeat-pid"
log_file="$repo_root/.heartbeat-log"
interval="${HEARTBEAT_INTERVAL:-600}"

usage() {
    sed -n '3,27p' "$script_path" | sed 's/^#$//; s/^# //'
}

# Both spellings. The single dash is what gets typed (`nohup zsh
# Scripts/heartbeat.zsh -on`), the double dash is what the rest of this tree's
# scripts use, and refusing one of them would be a papercut with no upside.
# 兩種寫法都收。單破折號是實際會被打出來的那一種（`nohup zsh Scripts/heartbeat.zsh -on`），
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
        printf 'local screen sessions matching "%s*":\n' "$local_prefix"
        list_local | sed 's/^/  /'
        # Nothing found is printed as such. An empty list and a list this script
        # failed to read look identical otherwise, and the first is the ordinary
        # case here -- sessions started in a bare terminal.
        # 找不到時明講。否則「空清單」與「這支腳本沒讀到清單」看起來相同，而在此處前者才是常態
        # ——那些在裸終端機中啟動的 session。
        [ -n "$(list_local)" ] || printf '  (none -- start sessions with `screen -S %s-<name> claude`)\n' "$local_prefix"
        if [ -f "$targets_file" ]; then
            printf 'remote targets from %s:\n' "${targets_file:t}"
            grep -v '^[[:space:]]*#' "$targets_file" | grep -v '^[[:space:]]*$' | sed 's/^/  /'
        else
            printf 'remote targets: none (%s absent, see %s.example)\n' \
                "${targets_file:t}" "${targets_file:t}"
        fi
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
