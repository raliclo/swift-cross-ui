#!/usr/bin/env zsh
#
# Types a line into live Claude sessions, on this machine and on others.
#
# **This script exists because a claim I wrote was wrong.** flow.md and
# mistakes.md said a cron job could not reach a running interactive session and
# that `multissh` reached the machine but not the session. The second half is
# false: `multissh` has an `exec` channel (README.md:199, "with a trailing
# command, multissh runs it via an exec channel"), and what that command has to
# be is `screen -X stuff`, which writes into a live session's stdin. Measured
# 2026-09-09 on this Mac:
#
#     $ screen -dmS scui_probe /bin/sh
#     $ screen -S scui_probe -p 0 -X stuff "echo HELLO_FROM_STUFF > /tmp/x\r"
#     $ cat /tmp/x
#     HELLO_FROM_STUFF
#
# So the real constraint is narrower, and it is checkable rather than absolute:
# **the session has to be running inside a multiplexer.** A session started in a
# bare terminal has no socket anyone can write to, and on this machine today
# there is none -- `tmux` is not installed and `screen -ls` finds no sockets.
# That is a setup gap, not an impossibility, and the difference matters: the
# first is fixed by starting sessions with `screen -S <name> claude`, the second
# would not be fixed by anything.
#
# 把一行文字打進活著的 Claude session——本機的，以及其他機器上的。
#
# **這支腳本的存在，是因為我寫下的一項主張是錯的。** flow.md 與 mistakes.md 曾說 cron 到不了一個
# 執行中的互動式 session，而 `multissh` 到得了那台機器、到不了那個 session。後半是假的：`multissh`
# 有 `exec` 通道（README.md:199），而該通道要執行的東西是 `screen -X stuff`——它會寫進一個活著的
# session 的 stdin。2026-09-09 於本機實測（見上方英文中的三行）。
#
# 因此真正的限制窄得多，而且是可檢查的而非絕對的：**那個 session 必須跑在 multiplexer 之內。**
# 在裸終端機中啟動的 session 沒有任何人寫得進去的 socket，而這台機器今天正是如此——tmux 沒有安裝，
# `screen -ls` 也找不到任何 socket。那是設定缺口，不是做不到，而這個差別很重要：前者只要改用
# `screen -S <名稱> claude` 啟動就好，後者則沒有任何辦法。
#
# USAGE
#     zsh Scripts/session_ping.zsh --on            arm it
#     zsh Scripts/session_ping.zsh --off           disarm; a beat then costs one exec and no tokens
#     zsh Scripts/session_ping.zsh --status
#     zsh Scripts/session_ping.zsh --list          show the sessions it would reach
#     zsh Scripts/session_ping.zsh                 send the question to every armed target
#     zsh Scripts/session_ping.zsh -m "your text"  send something else
#
# A crontab line, now that this is a thing cron can actually do:
#     */20 * * * * cd /Volumes/Windows/proj_Win/swift-cross-ui && zsh Scripts/session_ping.zsh
#
# Off by default, and the switch is the point: a beat while off runs this
# script, prints IDLE, contacts nothing and spends no tokens anywhere.

set -euo pipefail

repo_root="${0:a:h:h}"
switch_file="$repo_root/.session-ping-on"
targets_file="$repo_root/.session-ping-targets"
message="Are you still working ?"

# Local sessions are matched by name prefix rather than listed, so a restarted
# session with a new pid is still found. `screen -ls` prints "<pid>.<name>".
# 本機 session 以名稱前綴比對而非逐一列出，好讓一個以新 pid 重啟的 session 仍然找得到。
local_prefix="${SESSION_PING_PREFIX:-claude}"

# multissh is not on PATH and does not read ~/.ssh/config or plain ~/.multissh
# by itself: measured 2026-09-09, `multissh winnode "echo PING_OK"` failed name
# resolution while `multissh -F ~/.multissh/generated/config2Win winnode` printed
# PING_OK. The config is therefore not optional here.
# multissh 不在 PATH 上，而且它本身不會讀 ~/.ssh/config，也不會自己讀到那份 generated config：
# 2026-09-09 實測，`multissh winnode "echo PING_OK"` 名稱解析失敗，而
# `multissh -F ~/.multissh/generated/config2Win winnode` 印出了 PING_OK。因此此處的 config 不是選配。
multissh_bin="${MULTISSH_BIN:-$HOME/proj/multissh/release/multissh}"
multissh_config="${MULTISSH_CONFIG:-$HOME/.multissh/generated/config2Win}"

list_local() {
    # `|| true` is load-bearing under `set -o pipefail`: `screen -ls` exits 1
    # when there are no sockets, which is the ORDINARY case here, and the
    # pipeline's failure would take the whole script down at --list. Measured
    # 2026-09-09: --list exited 1 and printed an empty list, which reads as a
    # broken script rather than as "no sessions are running under screen".
    # 在 `set -o pipefail` 之下，這個 `|| true` 是必要的：沒有任何 socket 時 `screen -ls` 會以 1
    # 結束，而那在此處是**常態**；該管線的失敗會讓整支腳本在 --list 時倒下。2026-09-09 實測：
    # --list 以 1 結束並印出一份空清單，讀起來像是腳本壞了，而不是「沒有任何 session 跑在 screen 裡」。
    { screen -ls 2>/dev/null || true; } | awk -v p="$local_prefix" '
        $1 ~ /^[0-9]+\./ {
            split($1, parts, ".")
            name = substr($1, index($1, ".") + 1)
            if (index(name, p) == 1) print $1
        }'
}

send_local() {
    local target="$1"
    # -p 0 addresses the session'\''s first window: without it, `stuff` goes to
    # whichever window is current, which for a session someone has been using is
    # not necessarily the one running claude.
    # -p 0 指定該 session 的第一個視窗：少了它，`stuff` 會送到當前視窗，而對一個有人用過的 session
    # 來說，那不一定是跑著 claude 的那一個。
    screen -S "$target" -p 0 -X stuff "$message$(printf '\r')"
}

case "${1:-}" in
    --on)  : > "$switch_file"; printf 'session ping ON -- %s\n' "$switch_file"; exit 0 ;;
    --off) rm -f "$switch_file"; printf 'session ping OFF\n'; exit 0 ;;
    --status)
        if [ -e "$switch_file" ]; then printf 'ON\n'; else printf 'OFF\n'; fi
        exit 0
        ;;
    --list)
        printf 'local screen sessions matching "%s*":\n' "$local_prefix"
        list_local | sed 's/^/  /'
        # Nothing found is printed as such. An empty list and a list this script
        # failed to read look identical otherwise, and the first is the ordinary
        # case here -- sessions started in a bare terminal.
        # 找不到時明講。否則「空清單」與「這支腳本沒讀到清單」看起來完全相同，而在此處前者才是
        # 常態——那些在裸終端機中啟動的 session。
        [ -n "$(list_local)" ] || printf '  (none -- start sessions with `screen -S %s-<name> claude`)\n' "$local_prefix"
        if [ -f "$targets_file" ]; then
            printf 'remote targets from %s:\n' "${targets_file:t}"
            grep -v '^[[:space:]]*#' "$targets_file" | grep -v '^[[:space:]]*$' | sed 's/^/  /'
        else
            printf 'remote targets: none (%s absent)\n' "${targets_file:t}"
        fi
        exit 0
        ;;
    -m)
        shift
        message="${1:?-m needs a message}"
        shift || true
        ;;
    --help|-h) sed -n '3,45p' "$0"; exit 0 ;;
esac

if [ ! -e "$switch_file" ]; then
    printf 'IDLE -- session ping off. `zsh Scripts/session_ping.zsh --on` to arm it.\n'
    exit 0
fi

sent=0
for target in $(list_local); do
    send_local "$target"
    printf 'sent to local %s\n' "$target"
    sent=$(( sent + 1 ))
done

# Remote targets, one per line: "<host> <screen-session-name>". Sent through
# multissh's exec channel, which is the half of this that was wrongly ruled out.
# 遠端目標，一行一個："<主機> <screen session 名稱>"。經由 multissh 的 exec 通道送出，而那正是
# 先前被誤判為做不到的那一半。
if [ -f "$targets_file" ]; then
    while read -r host name; do
        case "$host" in ''|\#*) continue ;; esac
        [ -n "$name" ] || continue
        if "$multissh_bin" -F "$multissh_config" "$host" \
            "screen -S $name -p 0 -X stuff '$message\r'" >/dev/null 2>&1
        then
            printf 'sent to %s:%s\n' "$host" "$name"
            sent=$(( sent + 1 ))
        else
            # Loud. A failed remote send that printed nothing would leave the
            # count looking like a quiet machine rather than an unreachable one.
            # 大聲失敗。一次「什麼都沒印」的遠端傳送失敗，會讓計數讀起來像是一台安靜的機器，
            # 而不是一台連不上的機器。
            printf 'FAILED to reach %s:%s\n' "$host" "$name" >&2
        fi
    done < "$targets_file"
fi

# The count, always, including zero. "Armed and reached nothing" is the state
# this whole script is most likely to be in, and it must not read as success.
# 一律印出數目，包含 0。「已開啟但一個也沒送到」正是這支腳本最可能處於的狀態，而它不可以讀起來
# 像是成功。
printf 'session ping: %d target(s)\n' "$sent"
[ "$sent" -gt 0 ] || printf 'session ping: armed but reached nothing -- see --list\n' >&2
