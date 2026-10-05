#!/usr/bin/env zsh
# Move finished items out of queue.md into completed.md, once they are a week old.
#
#   zsh Scripts/archive_done.zsh              list what would move (changes nothing)
#   zsh Scripts/archive_done.zsh --apply      move it
#   zsh Scripts/archive_done.zsh --days N     age threshold in days (default 7)
#
# An item moves when all of these hold:
#   - it is checked off: `- [x]`, or `- [-]` (cancelled -- closed, not open);
#   - every item nested under it is checked off too, so nothing open leaves
#     queue.md with it;
#   - no line of it -- the item, its continuation lines, its sub-items -- was
#     changed in the last N days, by `git blame`. That is "done a week ago"
#     measured from the record rather than from the dates written in the
#     prose, which are not consistent (DONE / FIXED / CLOSED / none). A line
#     not yet committed counts as changed now, so work in progress never moves.
# The largest such block moves as a whole; its sub-items are not moved again on
# their own.
#
# In queue.md the block is replaced by one line at the same indent -- the
# item's opening words and "-> completed.md (archived DATE)" -- because other
# entries point at it ("see below", "the item above"), and a pointer keeps those
# readable. In completed.md the block is appended under "## Archived DATE from
# queue.md", grouped by the queue.md heading it sat under, text unchanged.
#
# Read and written through csv2's line mode (`--headers 0`): each line is one
# field, bytes as they are, so the text that moves is the text that was there.
# heartbeats/heartbeat.zsh reads only open `- [ ]` items, which never move.
#
# 把 queue.md 中已完成、且已滿一週的項目搬到 completed.md。預設只列出、不改動;--apply 才搬。項目要搬，須
# 同時符合：已勾選(`[x]`,或已取消的 `[-]`);底下巢狀的項目也全部已勾選，因此不會有未完成的東西跟著離開;
# 依 `git blame`,該項目的每一行(本身、續行、子項目)在最近 N 天內都沒有被改過——以紀錄而非散文裡寫的日期
# 來衡量「一週前完成」,因為那些日期寫法不一致。尚未 commit 的行算作「現在剛改過」,所以進行中的工作永遠不
# 會被搬。搬走的是最大的那一整塊。queue.md 原處留下一行同縮排的指標，因為其他條目會指向它(「見下方」);
# completed.md 依日期與原本所在的 queue.md 標題分組附加，文字不變。讀寫一律經由 csv2 的逐行模式。

set -euo pipefail

repo_root="${0:A:h:h}"
queue="$repo_root/queue.md"
completed="$repo_root/completed.md"
days=7
apply=0
while (( $# )); do
    case "$1" in
        --apply) apply=1 ;;
        --days) days="${2:?--days needs a number}"; shift ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) print -u2 "unknown option: $1"; exit 64 ;;
    esac
    shift
done

cd "$repo_root"
today="$(date +%Y-%m-%d)"
cutoff=$(( $(date +%s) - days * 86400 ))

# The lines, through csv2; "(@f)" in quotes keeps the empty ones.
# 經由 csv2 讀入各行;加引號的 "(@f)" 會保留空行。
lines=("${(@f)$(csv2 --headers 0 -r -i "$queue")}")
n=${#lines}

# When each line last changed. --line-porcelain gives every line its own
# author-time; uncommitted lines show the current time.
# 每一行最後一次被修改的時間。--line-porcelain 讓每一行都帶自己的 author-time;未 commit 的行顯示現在時間。
times=(${(f)"$(git blame --line-porcelain -- "$queue" | sed -n 's/^author-time //p')"})
(( ${#times} == n )) || { print -u2 "git blame gave ${#times} times for $n lines"; exit 1; }

item_re='^( *)- \[([ x-])\] (.*)$'
typeset -a indent marker
for (( i = 1; i <= n; i++ )); do
    if [[ "${lines[i]}" =~ $item_re ]]; then
        indent[i]=${#match[1]}
        marker[i]="${match[2]}"
    else
        indent[i]=-1
        marker[i]=""
    fi
done

# The last line belonging to the item at $1: continuation lines and sub-items
# are indented deeper; a blank line belongs only if more of the item follows.
# 屬於第 $1 行項目的最後一行：續行與子項目縮排更深；空行只有在後面還有該項目的內容時才算。
block_end() {
    local i=$1 k=${indent[$1]} j=$(( $1 + 1 )) last=$1 line lead
    while (( j <= n )); do
        line="${lines[j]}"
        [[ "$line" == \#* ]] && break
        if [[ -z "${line//[[:space:]]/}" ]]; then
            (( j++ ))
            continue
        fi
        lead="${line%%[^ ]*}"
        (( ${#lead} > k )) || break
        last=$j
        (( j++ ))
    done
    print $last
}

typeset -a starts ends
skip_to=0
for (( i = 1; i <= n; i++ )); do
    (( i <= skip_to )) && continue
    (( indent[i] >= 0 )) || continue
    [[ "${marker[i]}" == [x-] ]] || continue
    e=$(block_end $i)
    open=0 newest=0
    for (( j = i; j <= e; j++ )); do
        [[ "${marker[j]}" == " " ]] && open=1
        (( times[j] > newest )) && newest=${times[j]}
    done
    (( open == 0 && newest <= cutoff )) || continue
    # Already a pointer left by an earlier run: nothing to move.
    # 已是先前執行留下的指標：沒有東西可搬。
    [[ "${lines[i]}" == *"-> completed.md (archived "* ]] && continue
    starts+=($i)
    ends+=($e)
    skip_to=$e
done

if (( ${#starts} == 0 )); then
    print "nothing to archive: no checked-off item in queue.md is older than $days days"
    exit 0
fi

heading_of() {
    local j=$1
    while (( j > 0 )); do
        [[ "${lines[j]}" == \#* ]] && { print -r -- "${lines[j]}" | sed 's/^#* *//'; return; }
        (( j-- ))
    done
    print -r -- "(top)"
}

moved=0
for (( b = 1; b <= ${#starts}; b++ )); do
    s=${starts[b]}; e=${ends[b]}
    moved=$(( moved + e - s + 1 ))
    printf '%5d-%-5d %s\n' $s $e "${${lines[s]#*- \[?\] }[1,90]}"
done
print "${#starts} item(s), $moved line(s), older than $days days"
(( apply )) || { print "list only; --apply moves them"; exit 0; }

# completed.md: what is there, then today's section.
# completed.md:原有內容，再加上今天這一節。
typeset -a out
if [ -f "$completed" ]; then
    out=("${(@f)$(csv2 --headers 0 -r -i "$completed")}")
else
    out=("# completed.md" ""
        "Finished items moved out of queue.md by Scripts/archive_done.zsh once no line"
        "of them had changed for a week. The text is as it was in queue.md; the"
        "headings say which queue.md section each block came from."
        ""
        "由 Scripts/archive_done.zsh 從 queue.md 搬來的已完成項目：每一行都已一週沒有改動。文字與在 queue.md"
        "時相同；標題標明每一塊原本位於 queue.md 的哪一節。")
fi
out+=("" "## Archived $today from queue.md")
last_heading=""
for (( b = 1; b <= ${#starts}; b++ )); do
    s=${starts[b]}; e=${ends[b]}; k=${indent[s]}
    h="$(heading_of $s)"
    if [[ "$h" != "$last_heading" ]]; then
        out+=("" "### $h" "")
        last_heading="$h"
    fi
    for (( j = s; j <= e; j++ )); do
        out+=("${lines[j]:$k}")
    done
done

# queue.md: every moved block becomes one pointer line at its own indent.
# queue.md:每一塊被搬走的內容都換成同縮排的一行指標。
typeset -a keep
b=1
for (( i = 1; i <= n; i++ )); do
    if (( b <= ${#starts} && i == starts[b] )); then
        title="${lines[i]#*- \[?\] }"
        (( ${#title} > 80 )) && title="${title[1,80]}..."
        keep+=("${lines[i]%%- \[*}- [${marker[i]}] $title -> completed.md (archived $today)")
        i=${ends[b]}
        (( b++ ))
        continue
    fi
    keep+=("${lines[i]}")
done

print -rl -- "${out[@]}" | csv2 -si --headers 0 -r -o "$completed"
print -rl -- "${keep[@]}" | csv2 -si --headers 0 -r -o "$queue"
print "moved ${#starts} item(s) to completed.md; queue.md $n -> ${#keep} lines"
