#!/usr/bin/env zsh
#
# One switch, two jobs: ask live sessions whether they are still working, and
# name the next unfinished queue item.
#
# USAGE
#     zsh Scripts/heartbeat.zsh --on              arm it
#     zsh Scripts/heartbeat.zsh --off             disarm; a beat then costs nothing
#     zsh Scripts/heartbeat.zsh --status          ON or OFF
#     zsh Scripts/heartbeat.zsh --list            the sessions it would reach
#     zsh Scripts/heartbeat.zsh                   send the question to every target
#     zsh Scripts/heartbeat.zsh -m "your text"    send something else
#     zsh Scripts/heartbeat.zsh --next            print the next unchecked queue.md item
#
# A crontab line, ten minutes, which is the interval that was asked for. The
# interval is not what keeps the cost down -- the switch is: a beat while off
# contacts nothing and spends nothing.
#
#     */10 * * * * cd /Volumes/Windows/proj_Win/swift-cross-ui && zsh Scripts/heartbeat.zsh
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
# **WSL's tmux does not reach a Windows-native session.** tmux writes into a pty
# it owns, and an MSYS2 process is not in it. A session has to be started inside
# whichever side it is to be pinged in:
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
# **WSL 的 tmux 到不了一個 Windows 原生的 session。** tmux 寫入的是它自己擁有的 pty，而一個 MSYS2
# 行程不在其中。要在哪一邊被 ping，就必須在哪一邊啟動。
#
# 為什麼兩件事合成一支：它們共用那個開關，而開關才是「沒有任務時不要花 token」的關鍵。分成兩支時，
# 打開一個而忘了另一個，讀起來會與「兩個都開了但很安靜」完全相同。

set -euo pipefail

repo_root="${0:a:h:h}"
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

case "${1:-}" in
    --on)  : > "$switch_file"; printf 'heartbeat ON -- %s\n' "$switch_file"; exit 0 ;;
    --off) rm -f "$switch_file"; printf 'heartbeat OFF\n'; exit 0 ;;
    --status)
        if [ -e "$switch_file" ]; then printf 'ON\n'; else printf 'OFF\n'; fi
        exit 0
        ;;
    --next) print_next; exit $? ;;
    --list)
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
        ;;
    --help|-h) sed -n '3,20p' "$0"; exit 0 ;;
esac

if [ ! -e "$switch_file" ]; then
    printf 'IDLE -- heartbeat off. `zsh Scripts/heartbeat.zsh --on` to arm it.\n'
    exit 0
fi

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
