#!/usr/bin/env zsh
# One UI test at a time, so a screenshot shows what its own test did.
#
#   zsh testapp/ui-lock.zsh acquire <holder>     wait for the UI, then take it
#   zsh testapp/ui-lock.zsh acquire <holder> --no-wait   take it or fail now
#   zsh testapp/ui-lock.zsh release <holder>     give it back
#   zsh testapp/ui-lock.zsh status               who holds it, and why not you
#   zsh testapp/ui-lock.zsh check <replay log>   what the desktop did with our
#                                                input, recorded for `acquire`
#
# Why it exists: every Pn test is judged by a screenshot of the whole desktop or
# of one window, and synthesised input goes to whatever is in front. Two tests
# running at once produce images that each look like a defect in the other's
# app. Measured 2026-08-26 in a different form: an -actionfile replay drove the
# editor that was covering the app, twice, and reported success both times.
#
# `acquire` is also a readiness gate, not just a mutex. It refuses to hand out
# the UI while the desktop is refusing our synthesised input -- locked, or with
# an elevated window in front -- because such a desktop makes every instrument
# return a plausible negative instead of an error: a desktop capture yields the
# lock screen, SendInput moves nothing, and a *window* capture keeps returning
# the app drawn perfectly, because BitBlt reads a window that is not on screen.
# That cost hours before it was understood.
#
# It knows that second-hand, through `check`. The gate runs before a test, and
# the only honest answer comes from having attempted input; `check` reads that
# answer out of a replay's log afterwards and leaves it where the next `acquire`
# will find it. See input_is_denied for why, and for what was rejected.
#
# 一次只跑一個 UI 測試，好讓截圖反映的是它自己的測試。
#
#   zsh testapp/ui-lock.zsh acquire <holder>     等到 UI 可用後取得它
#   zsh testapp/ui-lock.zsh acquire <holder> --no-wait   立刻取得，否則直接失敗
#   zsh testapp/ui-lock.zsh release <holder>     歸還
#   zsh testapp/ui-lock.zsh status               目前由誰持有，以及你為何拿不到
#   zsh testapp/ui-lock.zsh check <replay log>   桌面如何處置我方輸入，記錄供 `acquire` 使用
#
# 存在理由：每個 Pn 測試都以「整個桌面」或「單一視窗」的截圖來判定，而合成輸入會送往位於前方的
# 任何視窗。兩個測試同時進行，產出的影像會各自看起來像是對方 app 的缺陷。2026-08-26 曾以另一種
# 形式實測到此事：一次 -actionfile 重放驅動了覆蓋在 app 上方的編輯器，兩次皆然，且兩次都回報成功。
#
# `acquire` 同時是就緒閘門，而不只是互斥鎖。當桌面正在拒絕我方的合成輸入時——鎖定中，或前方站著一個
# 提權視窗——它拒絕交出 UI，因為這樣的桌面會讓每一項量測工具回傳「看似合理的否定結果」而非錯誤：
# 桌面擷取得到鎖定畫面、SendInput 推不動任何東西，而**視窗**擷取仍持續回傳畫得好好的 app，因為
# BitBlt 讀的是一個並不在螢幕上的視窗。在弄清楚這件事之前，它已耗掉數小時。
#
# 它是間接得知此事的，來源是 `check`。閘門在測試之前執行，而唯一誠實的答案只能來自「已經嘗試過輸入」；
# `check` 事後從重放的 log 中讀出該答案，並留在下一次 `acquire` 找得到的地方。理由與被否決的方案，
# 見 input_is_denied。

set -euo pipefail

script_path="${0:A}"
lock_dir="${script_path:h}/.ui-lock"
retry_seconds="${UI_LOCK_RETRY_SECONDS:-60}"
# A holder that has not released after this long has crashed or been killed.
# Reclaimed loudly rather than left to block every later run forever.
# 持有超過此時長仍未釋放者，即為已崩潰或被終止。將其大聲回收，而非任由它永久擋住往後每一次執行。
stale_seconds="${UI_LOCK_STALE_SECONDS:-1800}"

# Where `check` leaves the desktop's answer, and how long that answer is worth
# reading. Beside the lock rather than inside it: the lock directory is removed
# on every release, and this has to outlive the run that observed it.
# `check` 把桌面的答案留在何處，以及該答案在多久之內仍值得參考。放在鎖的旁邊而非其中：鎖目錄在每次
# 釋放時都會被刪除，而這項紀錄必須比「觀察到它的那次執行」活得更久。
denied_marker="${script_path:h}/.ui-lock-denied"
denied_memory_seconds="${UI_LOCK_DENIED_MEMORY_SECONDS:-300}"

usage() {
    # To the first non-comment line, not a fixed range. The old `2,30p` was
    # written when the header ended at line 30 and went on being right until the
    # header grew, at which point usage silently stopped mid-paragraph.
    # 印到第一個非註解行為止，而非寫死範圍。舊的 `2,30p` 是在標頭剛好結束於第 30 行時寫的，直到標頭
    # 變長之前都還正確；標頭一長，usage 就在段落中間無聲地截斷。
    sed -n '2,${/^#/!q; s/^# \{0,1\}//p;}' "$script_path"
}

case "${1:-}" in
    -h|--help|help|"")
        usage
        exit 0
        ;;
esac

now() {
    date +%s
}

# The desktop's own verdict on synthesised input, as last recorded by `check`.
#
# What this gate protects is one capability: can a process here deliver input to
# the desktop? Windows answers that directly, and only when asked. SendInput
# fails with ERROR_ACCESS_DENIED (5) and the replay prints
#   -actionfile: failed: SendInput exited with status 5
# on stderr. Confirmed twice on 2026-08-27, each time with a desktop capture of
# the PIN screen taken alongside it.
#
# Status 5 is not only the lock screen -- a foreground window at a higher
# integrity level refuses our input the same way. For this gate the two are the
# same thing: no UI result taken now would mean anything.
#
# The tension, stated plainly: the gate wants to know BEFORE a test runs, and
# the honest signal exists only AFTER input has been attempted. So the
# observation is recorded where it happens (`check`) and read here. This gate is
# looking at the last thing the desktop actually said, not at a proxy for it.
#
# The record expires: UI_LOCK_DENIED_MEMORY_SECONDS, 300 by default. A denial is
# evidence about the moment it was written and nothing more, and without an
# expiry an hour-old note would block a machine somebody has since unlocked. A
# lock that outlives the memory costs one void run per window, not every run in
# the sweep.
#
# It fails CLOSED, as the LogonUI check did. A marker whose timestamp cannot be
# read counts as a denial: a check that cannot run is the absence of evidence,
# not evidence that the desktop is usable, and an earlier version of this file
# treated those as the same thing. A wrong "go" costs a whole test run whose
# screenshots look like defects; a wrong "wait" costs 60 seconds.
#
# Three signals were on the table. The two that lost, so nobody re-litigates:
#
# 1. `LogonUI.exe` in `tasklist`, which is what this file read until now. It
#    does not track the lock state on this machine: present at 19:18 while input
#    was being delivered normally, still present at 21:00, also while input was
#    being delivered -- see "What each instrument does on a locked workstation"
#    in testapp/P0-P26-windows-findings.md. As a gate that is a false positive
#    with no bound on it, because the wait loop below never gives up: one
#    long-lived LogonUI.exe blocks every test for as long as it lives. It also
#    spent ~195 ms in `tasklist` on every acquire, including the overwhelming
#    majority that were about to say "go". The MSYS lesson that call carried
#    (`//FI` against MSYS2_ARG_CONV_EXCL, two fixes for one problem that cancel
#    each other out) is written up in that same findings file, so deleting the
#    code here does not lose it.
# 2. A desktop capture. It is the one instrument that does show the lock screen,
#    and it is what confirmed the SendInput reading both times. Rejected as the
#    gate anyway: deciding "this PNG is the lock screen" needs image analysis
#    nothing here has, it costs seconds where reading this marker costs a stat,
#    and a capture is itself a UI operation racing the state it is measuring. It
#    stays what a person uses to confirm a verdict, which is what it is good at.
#
# The third option was to report the failure after the fact and stop there. This
# is that, plus a memory -- without one, a sweep of 25 apps burns 25 void runs
# and reports each of them separately.
#
# 桌面對合成輸入所給出的判決，由 `check` 最近一次記錄下來。
#
# 本閘門所保護的是單一能力：此處的行程能否把輸入送達桌面？Windows 會直接回答這個問題，但只在被
# 詢問時回答。SendInput 會以 ERROR_ACCESS_DENIED（5）失敗，而重放會對 stderr 印出
#   -actionfile: failed: SendInput exited with status 5
# 於 2026-08-27 確認兩次，每次都同時取得一張顯示 PIN 畫面的桌面截圖。
#
# status 5 不只代表鎖定畫面——前方若站著一個完整性等級更高的視窗，同樣會拒絕我方輸入。對本閘門而言
# 兩者是同一件事：此刻取得的任何 UI 結果都不具意義。
#
# 直說這裡的張力：閘門想在測試**之前**知道答案，而誠實的訊號只在嘗試輸入**之後**才存在。因此觀察
# 在它發生之處被記錄（`check`），並在此處被讀取。本閘門看的是「桌面最後一次真正說了什麼」，而不是
# 它的代理指標。
#
# 該紀錄會過期：UI_LOCK_DENIED_MEMORY_SECONDS，預設 300 秒。一次拒絕只是「寫下它的那一刻」的證據，
# 僅此而已；若不過期，一張一小時前的字條會擋住一台早已被解鎖的機器。鎖定時間長於記憶期的代價，是
# 每個記憶週期損失一次無效執行，而非整輪 sweep 全部作廢。
#
# 它與原本的 LogonUI 檢查一樣採「失敗即關閉」。無法讀出時間戳的標記檔一律視為拒絕：無法執行的檢查
# 是「沒有證據」，而不是「桌面可用」的證據，而本檔的舊版把兩者當成同一件事。錯誤的 go 會賠上一整輪
# 測試，其截圖看起來全像缺陷；錯誤的 wait 只賠上 60 秒。
#
# 當初有三個訊號可選。以下是落選的兩個，以免日後重新爭論：
#
# 1. `tasklist` 中的 `LogonUI.exe`，也就是本檔至今所讀的東西。在這台機器上它並不追蹤鎖定狀態：
#    19:18 輸入正常送達時它就在，21:00 輸入同樣正常送達時它還在——見
#    testapp/P0-P26-windows-findings.md 的「各項儀器在工作站鎖定時的行為」。作為閘門，那是一個沒有
#    上限的偽陽性，因為下方的等待迴圈永不放棄：一個長命的 LogonUI.exe 會在它存活期間擋住每一個測試。
#    而且每一次 acquire 都要為 `tasklist` 付出約 195 ms，包含絕大多數即將回答「go」的那些。該呼叫
#    所承載的 MSYS 教訓（`//FI` 與 MSYS2_ARG_CONV_EXCL 是同一問題的兩種解法，會互相抵銷）已記錄在
#    同一份 findings 文件中，因此刪掉此處的程式碼並不會連帶失去它。
# 2. 桌面截圖。它是唯一真的能顯示鎖定畫面的儀器，前述兩次 SendInput 判讀也都是靠它確認的。但仍不
#    採用為閘門：要判定「這張 PNG 是鎖定畫面」需要此處沒有的影像分析、其成本以秒計而讀取本標記檔
#    只需一次 stat，且截圖本身就是一項 UI 操作，正與它想量測的狀態賽跑。它留在「人用來確認判決」的
#    位置上，那正是它擅長之處。
#
# 第三個選項是「事後回報該失敗，到此為止」。本設計即為該選項再加上記憶——沒有記憶的話，一輪 25 支
# app 的 sweep 會燒掉 25 次無效執行，並各自回報一次。
# `read` rather than `head`, here and below: a builtin cannot be absent from
# PATH, and this runs on the path where a missing external command would be read
# as "the desktop is fine". See the note in `check` about grep.
# 此處與下方都用 `read` 而非 `head`：builtin 不可能從 PATH 上消失，而這條路徑上「外部命令不存在」
# 會被讀成「桌面沒問題」。理由詳見 `check` 中關於 grep 的註解。
input_is_denied() {
    [ -f "$denied_marker" ] || return 1
    local when=""
    read -r when < "$denied_marker" 2>/dev/null || when=""
    if [[ "$when" != <-> ]]; then
        printf '!! %s has no timestamp on its first line; treating the desktop as unusable\n' \
            "$denied_marker" >&2
        return 0
    fi
    [ "$(( $(now) - when ))" -lt "$denied_memory_seconds" ]
}

# 0 when there is nothing on record, so a caller can print it without a second
# existence test. Distinguishing "no record" from "recorded 0s ago" is what
# `input_is_denied` is for.
# 沒有任何紀錄時回傳 0，讓呼叫端不必再做一次存在性判斷。要區分「沒有紀錄」與「0 秒前記錄」，
# 是 `input_is_denied` 的職責。
denied_age() {
    [ -f "$denied_marker" ] || { printf 0; return; }
    local when=""
    read -r when < "$denied_marker" 2>/dev/null || when=""
    [[ "$when" == <-> ]] || { printf 0; return; }
    printf '%s' "$(( $(now) - when ))"
}

# The second line is provenance. A bare timestamp answers "when" and leaves
# "who says so" to whoever is reading the file at 2am.
# 第二行記錄出處。只有時間戳的話，回答得了「何時」，卻把「誰說的」留給凌晨兩點讀這個檔的人。
record_denial() {
    { now; printf 'observed in %s\n' "$1"; } > "$denied_marker"
}

clear_denial() {
    rm -f "$denied_marker"
}

holder_name() {
    [ -f "$lock_dir/holder" ] && cat "$lock_dir/holder" || printf 'unknown'
}

holder_age() {
    [ -f "$lock_dir/taken_at" ] || { printf 0; return; }
    printf '%s' "$(( $(now) - $(cat "$lock_dir/taken_at") ))"
}

reclaim_if_stale() {
    [ -d "$lock_dir" ] || return 0
    local age
    age="$(holder_age)"
    [ "$age" -lt "$stale_seconds" ] && return 0
    printf '!! reclaiming a stale lock held by %s for %ss\n' "$(holder_name)" "$age" >&2
    rm -rf "$lock_dir"
}

# mkdir is the atomic step. Two processes racing it, one wins and one gets
# EEXIST; a test-and-then-create written with `[ -d ]` would let both through.
# mkdir 即為原子步驟。兩個行程競逐它時，一者成功、另一者得到 EEXIST；若寫成先 `[ -d ]` 判斷再建立，
# 則會讓兩者都通過。
try_take() {
    local holder="$1"
    mkdir "$lock_dir" 2>/dev/null || return 1
    printf '%s\n' "$holder" > "$lock_dir/holder"
    now > "$lock_dir/taken_at"
    return 0
}

command="$1"
shift || true

case "$command" in
    acquire)
        holder="${1:-}"
        [ -n "$holder" ] || { printf 'acquire needs a holder name\n' >&2; exit 2; }
        wait_for_it=1
        [ "${2:-}" = "--no-wait" ] && wait_for_it=0

        while :; do
            reclaim_if_stale
            if input_is_denied; then
                printf 'wait: the desktop refused synthesised input %ss ago, so no UI result would mean anything\n' \
                    "$(denied_age)"
            elif try_take "$holder"; then
                printf 'go: %s holds the UI\n' "$holder"
                exit 0
            else
                printf 'wait: %s holds the UI (%ss)\n' "$(holder_name)" "$(holder_age)"
            fi
            [ "$wait_for_it" -eq 1 ] || exit 1
            sleep "$retry_seconds"
        done
        ;;

    release)
        holder="${1:-}"
        [ -n "$holder" ] || { printf 'release needs a holder name\n' >&2; exit 2; }
        if [ ! -d "$lock_dir" ]; then
            printf 'nothing to release\n'
            exit 0
        fi
        current="$(holder_name)"
        if [ "$current" != "$holder" ]; then
            # Not fatal, but say so: releasing someone else's lock is how two
            # tests end up running at once after everything looked fine.
            # 並非致命錯誤，但必須說出來：釋放他人的鎖，正是「一切看起來都正常，卻有兩個測試同時
            # 在跑」的成因。
            printf '!! %s tried to release a lock held by %s; refusing\n' "$holder" "$current" >&2
            exit 1
        fi
        rm -rf "$lock_dir"
        printf 'released by %s\n' "$holder"
        ;;

    status)
        # Three states, not two. "Nothing on record" and "a refusal old enough
        # to be ignored" both let a run proceed, but they are not the same
        # thing to a reader deciding whether to believe a screenshot, and
        # collapsing them into "unlocked" is the claim this gate used to make
        # and could not support.
        # 三種狀態，而非兩種。「沒有紀錄」與「一次舊到可以忽略的拒絕」都會放行，但對一個正在決定
        # 「該不該相信這張截圖」的讀者而言，兩者並不相同；把它們併成「未鎖定」，正是本閘門過去
        # 做出卻無法支撐的那個宣稱。
        if input_is_denied; then
            printf 'desktop: refused our input %ss ago -- acquire will wait until that is %ss old\n' \
                "$(denied_age)" "$denied_memory_seconds"
        elif [ -f "$denied_marker" ]; then
            printf 'desktop: last refusal was %ss ago, past the %ss memory -- acquire will not wait\n' \
                "$(denied_age)" "$denied_memory_seconds"
        else
            printf 'desktop: no refusal on record (which is not the same as verified usable)\n'
        fi
        if [ -d "$lock_dir" ]; then
            printf 'ui lock: held by %s for %ss\n' "$(holder_name)" "$(holder_age)"
        else
            printf 'ui lock: free\n'
        fi
        ;;

    # What the desktop did with one run's input, read out of that run's replay
    # log, and left where the next `acquire` will see it.
    #
    # Give it the file a `-actionfile` run's stderr went to -- on Windows that is
    # testapp/output/<pn>-actionfile.log, truncated at every launch, so an old
    # verdict cannot be mistaken for this one's.
    #
    # Three answers, and the exit status carries them because the caller may be
    # a script: 0 the input was delivered, 3 it was refused, 4 the log says
    # nothing either way. Only 3 writes the marker and only 0 clears it. 4 leaves
    # it exactly as it was, which is the fail-closed half of this: a log that
    # cannot be read is not permission to believe the desktop is fine.
    #
    # A silent log is the normal case for a WinUI build, not a fault. Its
    # stdout and stderr are closed before anything can be piped from them --
    # `Console.attachToParentConsole()` reopens both on NUL, see
    # Sources/WinUIBackend/Console.swift -- so a WinUI run can never confirm or
    # deny anything here. GtkBackend builds are what this reads.
    #
    # 某一次執行的輸入被桌面如何處置：從該次重放的 log 中讀出，並留在下一次 `acquire` 看得到的地方。
    #
    # 傳入 `-actionfile` 執行時 stderr 所寫入的檔案——在 Windows 上是
    # testapp/output/<pn>-actionfile.log，每次啟動都會截斷，因此舊的判決不會被誤認為這一次的。
    #
    # 三種答案，並以 exit status 表達，因為呼叫端可能是腳本：0 輸入已送達、3 輸入被拒、
    # 4 log 對此沒有任何說法。只有 3 會寫入標記檔，也只有 0 會清除它；4 原封不動，這正是此處
    # 「失敗即關閉」的那一半：讀不到的 log 不構成「可以相信桌面沒問題」的許可。
    #
    # 對 WinUI 建置而言，log 為空是常態而非故障。它的 stdout 與 stderr 在任何東西能從中導出之前
    # 就已被關閉——`Console.attachToParentConsole()` 會把兩者重新開在 NUL 上，見
    # Sources/WinUIBackend/Console.swift——因此 WinUI 的執行永遠無法在此確認或否認任何事。
    # 本命令讀的是 GtkBackend 建置的輸出。
    check)
        log="${1:-}"
        [ -n "$log" ] || { printf 'check needs the path to a replay log\n' >&2; exit 2; }

        if [ ! -r "$log" ]; then
            printf '!! no readable replay log at %s; the desktop verdict is left as it was\n' "$log" >&2
            exit 4
        fi

        # Read and matched with zsh's own `$(<file)` and `==`, not `grep`. Two
        # reasons. `grep` is not always on PATH where this runs: the harness
        # this was tested through died with status 127 inside
        # print_actionfile_report, and that function already carries a note
        # about `sed` going missing in the same place. And `grep` decides a file
        # holding one stray byte is binary and then prints a warning instead of
        # a match, which reads exactly like "no failure found" -- `-a` turns
        # that off, but only if somebody remembers it. No external command
        # cannot be missing and has no such mode.
        #
        # 以 zsh 自身的 `$(<file)` 與 `==` 讀取並比對，而非用 `grep`。兩個理由。`grep` 未必存在於
        # 執行此處的 PATH 上：測試用的 harness 就在 print_actionfile_report 之中以狀態 127 死去，
        # 而該函式本身早已留有一則「`sed` 在同一個地方消失」的註解。再者，`grep` 會判定含有單一雜散
        # 位元組的檔案為二進位，然後印出警告而非比對結果——那讀起來正好就是「沒找到失敗」；`-a` 能
        # 關掉該行為，但前提是有人記得加。不存在的外部命令不會消失，也沒有這種模式。
        local text
        text="$(<"$log")"

        if [[ "$text" == *'SendInput exited with status 5'* ]]; then
            record_denial "$log"
            printf '!! the desktop refused this run every input it sent (ERROR_ACCESS_DENIED).\n' >&2
            printf '!! Nothing this run captured is evidence about the app: a window capture\n' >&2
            printf '!! still shows it drawn correctly. Unlock the workstation, or close whatever\n' >&2
            printf '!! elevated window holds the foreground, and run it again.\n' >&2
            exit 3
        fi

        if [[ "$text" == *'-actionfile: replayed '* ]]; then
            clear_denial
            printf 'desktop: input reached the app, so this run means what it looks like\n'
            exit 0
        fi

        printf '!! %s says nothing about a replay, so the desktop verdict is unchanged\n' "$log" >&2
        exit 4
        ;;

    *)
        printf 'unknown command: %s\n\n' "$command" >&2
        usage >&2
        exit 2
        ;;
esac
