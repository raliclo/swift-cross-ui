#!/usr/bin/env zsh
# Clears whatever is stopping synthesised input from reaching this project's apps.
#
#   zsh testapp/enable_input.zsh                 find and stop known blockers
#   zsh testapp/enable_input.zsh --check         report only, change nothing
#   zsh testapp/enable_input.zsh --from-log F    name the blocker a replay hit
#   zsh testapp/enable_input.zsh --help
#
# WHAT IT IS FOR. Windows UIPI refuses input injection from a lower-integrity
# process to a HIGHER-integrity foreground window. Every symptom is silent:
# `SetCursorPos` returns false and sets no error, a `SendInput` fallback moves
# nothing, and only `AttachThreadInput` says why -- status 5, ACCESS_DENIED.
# Screen capture keeps working, because capture is not input, so a run looks
# healthy in every screenshot while no action file can do anything.
#
# Measured 2026-09-16: `AsMonitorControl.exe`, window class `ASHDRCONTROL`, held
# the foreground. Both Windows backends failed identically, both processes were
# in Console 1 alongside explorer, the desktop capture was a normal unlocked
# desktop, and the cursor clip was the whole virtual desktop. Reverting the
# synthesiser to its previous version failed the same way, which is what ruled
# out our own code.
#
# THE BLOCKER LIST IS EVIDENCE, NOT A GUESS. Only processes actually observed
# holding the foreground and refusing an attach belong in it. Adding a program
# because it "looks like the sort of thing that might" would make this script
# kill things for no reason, on a machine that is not ours.
#
# 清除「阻擋合成輸入抵達本專案 app」的東西。
#
# 它的用途。Windows 的 UIPI 會拒絕「低完整性行程 → **較高**完整性前景視窗」的輸入注入。
# 其所有症狀都是無聲的:`SetCursorPos` 回傳 false 且不設錯誤碼、`SendInput` 的退路也推不動任何東西,
# 只有 `AttachThreadInput` 會說出原因——狀態 5,ACCESS_DENIED。而**螢幕擷取照常運作**,因為擷取不是
# 輸入;於是每一張截圖看起來都很健康,而沒有任何一個動作檔做得了任何事。
#
# 2026-09-16 實測:`AsMonitorControl.exe`(視窗類別 `ASHDRCONTROL`)佔著前景。兩個 Windows backend
# 完全相同地失敗、兩個行程都與 explorer 同在 Console 1、桌面擷圖是正常且未鎖定的、游標的限制矩形
# 是整個虛擬桌面。把合成器還原成前一個版本後失敗方式完全相同——**那才是排除我們自己程式碼的依據。**
#
# 這份阻擋者清單是證據,不是猜測。只有「實際被觀察到佔著前景並拒絕附加」的行程才該列入。
# 因為「它看起來像是會做這種事的程式」而加進來,會讓這支腳本在一台不屬於我們的機器上無故殺掉東西。

set -u

script_path="${0:A}"

show_help() {
    sed -n '2,38p' "$script_path" | sed 's/^# \{0,1\}//'
}

# --help answers before anything else runs. A wrong flag should cost a page of
# text, not a process kill.
# --help 在其餘任何動作之前回答。打錯旗標的代價應該是一頁文字,而不是殺掉一個行程。
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

# Image names observed blocking input on this machine, with the date each was
# measured. One per line; the comment is why it is here.
# 在這台機器上被觀察到阻擋輸入的映像檔名稱,附上各自被量測到的日期。一行一個;註解說明它為何在此。
typeset -a known_blockers
known_blockers=(
    # 2026-09-16: class ASHDRCONTROL held the foreground, AttachThreadInput 5.
    # 2026-09-16:類別 ASHDRCONTROL 佔著前景,AttachThreadInput 回 5。
    'AsMonitorControl.exe'
)

# Blockers that must NEVER be stopped, only reported.
#
# **Stopping a remote-desktop host disconnects the person running this.** That
# is not a trade-off to make on someone's behalf, however stuck the pointer is,
# so these are a separate list with a separate verb: named, explained, left
# alone.
#
# Chrome Remote Desktop is listed as a SUSPECT, not a proven cause, and the
# distinction is deliberate: automating a mouse over CRD works for plenty of
# people, so its mere presence does not make it the culprit. It earns a place
# here because on 2026-09-16 it was running while mouse injection failed for
# every coordinate, keyboard injection worked in the same minutes, and a local
# desktop capture contained no cursor at all -- which is the one symptom nothing
# else in this list produced.
#
# That keyboard worked while mouse did not is what rules out a locked desktop, a
# wrong desktop and UIPI in one go: both go through the same checks.
#
# The experiment that would settle it has not been run, because it needs the
# remote session disconnected and that is the user's call, not this script's.
#
# Chrome Remote Desktop 在此是**嫌疑者**、不是已證實的成因,而這個區別是刻意的:透過 CRD 自動化
# 滑鼠對許多人是可行的,因此「它在跑」本身並不使它成為元兇。它之所以被列入,是因為 2026-09-16 當時
# 它正在執行,而滑鼠注入對每一個座標都失敗、同一段時間內鍵盤注入正常、且本機桌面擷圖中完全沒有游標
# ——那是本清單中其餘成因都產生不出來的症狀。
#
# 「鍵盤可以而滑鼠不行」這一點,一次排除了桌面鎖定、桌面錯誤與 UIPI:兩者走的是同一道檢查。
#
# 能夠了結此事的那個實驗**尚未執行**,因為它需要中斷遠端連線,而那是使用者的決定、不是這支腳本的。
#
# 絕對**不可以**停掉、只能回報的阻擋者。
#
# **停掉一個遠端桌面主機,會把正在操作的那個人斷線。** 無論指標卡得多嚴重,那都不是可以代替別人
# 做的取捨;因此它們獨立成一份清單、配一個不同的動詞:指名、說明、不碰。
#
# Chrome Remote Desktop,2026-09-16 實測。它透過自己的虛擬輸入驅動握有指標,而破案的關鍵是一個
# 其餘成因都產生不出來的症狀:**本機桌面擷圖裡完全沒有游標**——因為 CRD 是在**用戶端**繪製它,
# 而不是合成到主機桌面上。滑鼠注入對每一個座標都失敗,而**鍵盤注入仍然正常**——兩者走的是同一道
# 桌面與完整性檢查,這一點同時排除了桌面鎖定、桌面錯誤與 UIPI。
typeset -a report_only_blockers
report_only_blockers=(
    'remoting_desktop.exe'
    'remoting_host.exe'
)

check_only=0
from_log=''

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) check_only=1; shift ;;
        --from-log)
            shift
            from_log="${1:-}"
            [[ -n "$from_log" ]] || { printf '--from-log needs a path\n' >&2; exit 2; }
            shift
            ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; show_help >&2; exit 2 ;;
    esac
done

# A replay log names the process that actually refused, which is better evidence
# than the list -- the list is only what has been seen before.
# 一份重放 log 會指出**實際拒絕**的那個行程,而那比清單更有力——清單記的只是「以前見過的」。
if [[ -n "$from_log" ]]; then
    if [[ ! -f "$from_log" ]]; then
        printf '!! no such log: %s\n' "$from_log" >&2
        exit 2
    fi
    blocker_pid="$(grep -oE 'attaching to the foreground window .*process=[0-9]+' "$from_log" \
        | grep -oE 'process=[0-9]+' | tail -1 | cut -d= -f2)"
    if [[ -z "$blocker_pid" ]]; then
        printf '%s names no foreground window, so it says nothing about a blocker\n' "$from_log"
    else
        blocker_name="$(tasklist //FI "PID eq ${blocker_pid}" 2>/dev/null \
            | grep -oE '^[A-Za-z0-9_.-]+\.exe' | head -1)"
        printf 'the log names pid %s = %s\n' "$blocker_pid" "${blocker_name:-unknown}"
        if [[ -n "$blocker_name" ]] \
            && (( ! ${known_blockers[(Ie)$blocker_name]} )); then
            printf '!! %s is not in the known list. Add it only after seeing it refuse\n' \
                "$blocker_name" >&2
            printf '!! an attach, and record the date beside it.\n' >&2
        fi
    fi
fi

found=0
stopped=0
remote=0

# Checked FIRST, because when one of these is running it is almost certainly the
# answer, and everything below would otherwise read as "no blocker found".
# 先檢查這一類,因為只要其中之一在跑,它幾乎肯定就是答案;否則下方的一切會被讀成「沒有找到阻擋者」。
for image in "${report_only_blockers[@]}"; do
    running="$(tasklist //FI "IMAGENAME eq ${image}" 2>/dev/null | grep -c -i "$image")"
    [[ "$running" -eq 0 ]] && continue
    remote=$(( remote + 1 ))
    printf 'REMOTE SESSION: %s (%s instance(s)) -- NOT stopped, on purpose\n' "$image" "$running"
done

if [[ "$remote" -gt 0 ]]; then
    printf -- '---\n'
    printf 'A remote-desktop host is running. This is a CORRELATION, not a proven\n'
    printf 'cause, and the difference matters: plenty of people automate a mouse\n'
    printf 'over Chrome Remote Desktop, so it is not inherently a blocker.\n'
    printf '\n'
    printf 'What WAS measured here on 2026-09-16, while it was connected:\n'
    printf '  - mouse injection failed for every coordinate, SetCursorPos and\n'
    printf '    SendInput alike, including a point inside our own window\n'
    printf '  - keyboard injection worked in the same minutes\n'
    printf '  - a local desktop capture contained no cursor at all\n'
    printf '\n'
    printf 'To settle it: disconnect the remote session, or run at the physical\n'
    printf 'machine, and drive one mouse action file. If it works then and not\n'
    printf 'now, this is the cause; if it fails both ways, it is not.\n'
    printf 'Nothing was stopped: that would disconnect whoever is using it.\n'
    exit 4
fi

for image in "${known_blockers[@]}"; do
    # `//FI` not `-fi`: the double slash is what stops Git Bash rewriting the
    # argument into a path. Same reason `taskkill` takes `-f -im` here.
    # 用 `//FI` 而非 `-fi`:雙斜線才能阻止 Git Bash 把該引數改寫成路徑。`taskkill` 在此使用
    # `-f -im` 也是同一個理由。
    running="$(tasklist //FI "IMAGENAME eq ${image}" 2>/dev/null | grep -c -i "$image")"
    if [[ "$running" -eq 0 ]]; then
        printf 'not running: %s\n' "$image"
        continue
    fi

    found=$(( found + 1 ))
    printf 'BLOCKER RUNNING: %s (%s instance(s))\n' "$image" "$running"

    if [[ "$check_only" -eq 1 ]]; then
        continue
    fi

    taskkill -f -im "$image" 2>&1 | sed 's/^/  taskkill: /'
    sleep 1

    # The verdict is whether it is GONE, not taskkill's exit code. Against an
    # elevated target taskkill prints "Access is denied" and still exits 0 --
    # the same silent success this project keeps finding elsewhere.
    # 判準是「它還在不在」,不是 taskkill 的結束碼。對提權目標,taskkill 會印出
    # 「Access is denied」卻**仍以 0 結束**——與本專案一再遇到的靜默成功是同一種。
    left="$(tasklist //FI "IMAGENAME eq ${image}" 2>/dev/null | grep -c -i "$image")"
    if [[ "$left" -eq 0 ]]; then
        printf '  stopped: %s\n' "$image"
        stopped=$(( stopped + 1 ))
    else
        printf '  STILL RUNNING: %s -- it is elevated and this shell is not\n' "$image"
        printf '  run the elevating launcher beside this script:\n'
        printf '    testapp/enable_input.ps1\n'
    fi
done

printf -- '---\n'
if [[ "$found" -eq 0 ]]; then
    printf 'no known blocker is running.\n'
    printf 'If input is still refused, the blocker is one this list has not seen.\n'
    printf 'Drive any action file, then: zsh %s --from-log <that log>\n' "$script_path"
    exit 0
fi

if [[ "$check_only" -eq 1 ]]; then
    printf '%s blocker(s) running; nothing was changed (--check).\n' "$found"
    exit 3
fi

if [[ "$stopped" -eq "$found" ]]; then
    printf 'all %s blocker(s) stopped. Input should reach the apps again.\n' "$stopped"
    printf 'Verify by driving an action file rather than by trusting this line.\n'
    exit 0
fi

printf '%s of %s stopped. Elevation is needed for the rest.\n' "$stopped" "$found"
exit 1
