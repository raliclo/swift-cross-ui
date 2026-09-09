#!/usr/bin/env zsh
#
# Names the next unfinished queue item, or says IDLE.
#
# **The switch is the point, not the printing.** A heartbeat that always has
# something to say costs tokens on every beat of a day with no queue, and one
# that says nothing is indistinguishable from one that is not running. So: off
# by default, one file turns it on, and a beat while off is a single script run
# that prints IDLE and ends.
#
# It exists because the queue used to live in the conversation. A table pasted
# into a message fades with compaction, and after it fades "the queue is empty"
# and "I no longer remember the queue" read the same from the inside -- neither
# produces a line of output. See mistakes.md entry 1.
#
# CRON CAN DO THIS, AND AN EARLIER VERSION OF THIS COMMENT SAID IT COULD NOT.
# What it said was that a shell script cannot inject a prompt into a live
# interactive session and that `multissh` reaches the machine but not the
# session. The second half is false. `multissh` has an exec channel, and
# `screen -X stuff` writes into a live session's stdin -- both measured
# 2026-09-09, end to end, in Scripts/session_ping.zsh, which is where that
# correction lives. The real constraint is that the session must be running
# inside a multiplexer.
#
# `/loop` remains the mechanism for THIS script, for a different reason: it
# re-enters from inside the session that is doing the work, so the next item is
# read by the session that has to act on it rather than typed at it.
#
#     /loop 20m sh Scripts/queue_heartbeat.zsh and do what it says
#
# 指出佇列中的下一個未完成項目，或回報 IDLE。
#
# **重點在那個開關，不在列印。** 一個永遠有話可說的心跳，會在沒有佇列的日子裡於每一次跳動都花掉
# token；而一個什麼都不說的心跳，與一個根本沒在跑的心跳無從區分。因此：預設關閉、以一個檔案開啟，
# 而關閉狀態下的一次跳動就只是執行這支腳本、印出 IDLE、結束。
#
# 它之所以存在，是因為佇列過去存在於對話裡。一份貼在訊息中的表格會隨著 context 壓縮而淡出，
# 而淡出之後，「佇列已經空了」與「我不記得佇列了」在內部讀起來完全相同——兩者都不會產生任何一行
# 輸出。見 mistakes.md 第 1 條。
#
# cron 做得到，而本註解的前一個版本說它做不到。當時寫的是「shell 腳本無法把提示注入活著的互動式
# session」以及「`multissh` 到得了那台機器、到不了那個 session」——後半是假的。`multissh` 有 exec
# 通道，而 `screen -X stuff` 會寫進一個活著的 session 的 stdin；兩者都在 2026-09-09 端到端實測過，
# 而那份更正記在 Scripts/session_ping.zsh 裡。真正的限制是：該 session 必須跑在 multiplexer 之內。
#
# 對**這一支**腳本而言，`/loop` 仍然是那個機制，但理由不同：它從「正在做事的那個 session 內部」
# 重新進入，因此下一個項目是由必須採取行動的那個 session 自己讀到的，而不是被別人打進去的。

set -euo pipefail

repo_root="${0:a:h:h}"
queue_file="$repo_root/queue.md"
switch_file="$repo_root/.queue-heartbeat-on"

case "${1:-}" in
    --on)
        # Tracked nowhere: the switch is one machine's state, not the tree's.
        # 不納入版控：這個開關是某一台機器的狀態，不是這棵樹的狀態。
        : > "$switch_file"
        printf 'queue heartbeat ON -- %s\n' "$switch_file"
        exit 0
        ;;
    --off)
        rm -f "$switch_file"
        printf 'queue heartbeat OFF\n'
        exit 0
        ;;
    --status)
        if [ -e "$switch_file" ]; then printf 'ON\n'; else printf 'OFF\n'; fi
        exit 0
        ;;
    --help|-h)
        sed -n '3,30p' "$0"
        exit 0
        ;;
esac

if [ ! -e "$switch_file" ]; then
    printf 'IDLE -- heartbeat off. `zsh Scripts/queue_heartbeat.zsh --on` to arm it.\n'
    exit 0
fi

if [ ! -f "$queue_file" ]; then
    # Loud, because an armed heartbeat with no queue file is a setup error and
    # not an empty queue -- and the two would otherwise print the same thing.
    # 大聲失敗：一個「已開啟但找不到佇列檔」的心跳是設定錯誤，不是空佇列，而兩者原本會印出同一句話。
    printf 'queue heartbeat is ON but %s does not exist\n' "$queue_file" >&2
    exit 1
fi

# `- [ ]` unchecked, `- [x]` done. grep -m1 gives the first still open.
# Printed with its line number so a second beat can tell "still on item 4"
# from "back on item 4".
# `- [ ]` 為未完成、`- [x]` 為已完成。grep -m1 取出第一個仍未完成者。附上行號，好讓下一次跳動
# 能分辨「還停在第 4 項」與「又回到第 4 項」。
next="$(grep -n -m1 '^- \[ \]' "$queue_file" || true)"

if [ -z "$next" ]; then
    printf 'QUEUE EMPTY -- every item in queue.md is checked off.\n'
    exit 0
fi

printf 'NEXT (%s:%s)\n' "${queue_file:t}" "${next%%:*}"
printf '%s\n' "${next#*:}"
