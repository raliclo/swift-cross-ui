#!/usr/bin/env zsh
# One UI test at a time, so a screenshot shows what its own test did.
#
#   zsh testapp/ui-lock.zsh acquire <holder>     wait for the UI, then take it
#   zsh testapp/ui-lock.zsh acquire <holder> --no-wait   take it or fail now
#   zsh testapp/ui-lock.zsh release <holder>     give it back
#   zsh testapp/ui-lock.zsh status               who holds it, and why not you
#
# Why it exists: every Pn test is judged by a screenshot of the whole desktop or
# of one window, and synthesised input goes to whatever is in front. Two tests
# running at once produce images that each look like a defect in the other's
# app. Measured 2026-08-26 in a different form: an -actionfile replay drove the
# editor that was covering the app, twice, and reported success both times.
#
# `acquire` is also a readiness gate, not just a mutex. It refuses to hand out
# the UI while the Windows workstation is locked, because a locked desktop makes
# every instrument return a plausible negative instead of an error: desktop
# capture yields bare wallpaper, SendInput moves nothing, and window capture
# fails. That cost hours before it was understood.
#
# 一次只跑一個 UI 測試，好讓截圖反映的是它自己的測試。
#
#   zsh testapp/ui-lock.zsh acquire <holder>     等到 UI 可用後取得它
#   zsh testapp/ui-lock.zsh acquire <holder> --no-wait   立刻取得，否則直接失敗
#   zsh testapp/ui-lock.zsh release <holder>     歸還
#   zsh testapp/ui-lock.zsh status               目前由誰持有，以及你為何拿不到
#
# 存在理由：每個 Pn 測試都以「整個桌面」或「單一視窗」的截圖來判定，而合成輸入會送往位於前方的
# 任何視窗。兩個測試同時進行，產出的影像會各自看起來像是對方 app 的缺陷。2026-08-26 曾以另一種
# 形式實測到此事：一次 -actionfile 重放驅動了覆蓋在 app 上方的編輯器，兩次皆然，且兩次都回報成功。
#
# `acquire` 同時是就緒閘門，而不只是互斥鎖。當 Windows 工作站處於鎖定狀態時，它拒絕交出 UI，因為
# 鎖定的桌面會讓每一項量測工具回傳「看似合理的否定結果」而非錯誤：桌面擷取只得到桌布、SendInput
# 推不動任何東西、視窗擷取失敗。在弄清楚這件事之前，它已耗掉數小時。

set -euo pipefail

script_path="${0:A}"
lock_dir="${script_path:h}/.ui-lock"
retry_seconds="${UI_LOCK_RETRY_SECONDS:-60}"
# A holder that has not released after this long has crashed or been killed.
# Reclaimed loudly rather than left to block every later run forever.
# 持有超過此時長仍未釋放者，即為已崩潰或被終止。將其大聲回收，而非任由它永久擋住往後每一次執行。
stale_seconds="${UI_LOCK_STALE_SECONDS:-1800}"

usage() {
    sed -n '2,30p' "$script_path" | sed 's/^# \{0,1\}//'
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

# Present only while the Windows workstation is locked. Absent on Linux, where
# the check is not applicable and must not fail the script.
#
# Two things here are deliberate, and the first version got both wrong.
#
# `tasklist //FI` with NO `MSYS2_ARG_CONV_EXCL`. The doubled slash is how MSYS is
# told to hand a single `/FI` to a native tool, so setting the exclusion -- which
# disables exactly that conversion -- makes tasklist receive a literal `//FI` and
# refuse it. Measured 2026-08-26: with the exclusion set the call printed
# `ERROR: Invalid argument/option - '//FI'` to stderr, stdout was empty, and this
# function therefore reported "unlocked" while LogonUI.exe was running and every
# capture was coming back as bare wallpaper. The gate never fired once.
#
# And it fails CLOSED. If the check itself cannot run, that is not evidence the
# desktop is usable -- it is the absence of evidence, and the first version
# treated the two as the same thing. A wrong "go" costs a whole test run whose
# screenshots look like defects; a wrong "wait" costs 60 seconds.
#
# 僅在 Windows 工作站鎖定期間存在。在 Linux 上不存在，該檢查於該處不適用，且不得使腳本失敗。
#
# 此處有兩點是刻意為之，而第一版兩點都寫錯了。
#
# 使用 `tasklist //FI` 且**不加** `MSYS2_ARG_CONV_EXCL`。雙斜線正是用來告訴 MSYS「請交一個單一的
# `/FI` 給原生工具」，因此設定該排除變數——它關掉的正是這項轉換——會使 tasklist 收到字面上的
# `//FI` 並拒絕。實測於 2026-08-26：設了排除變數後，該呼叫對 stderr 印出
# `ERROR: Invalid argument/option - '//FI'`，stdout 為空，於是本函式在 LogonUI.exe 正在執行、
# 且每一張截圖都只有桌布的情況下，仍回報「未鎖定」。此閘門從未生效過一次。
#
# 而且它採「失敗即關閉」。若檢查本身無法執行，那並不構成「桌面可用」的證據——那是「沒有證據」，
# 而第一版把兩者當成同一件事。錯誤的 go 會賠上一整輪測試，其截圖看起來全像缺陷；錯誤的 wait
# 只賠上 60 秒。
workstation_is_locked() {
    case "$(uname -s 2>/dev/null || printf unknown)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *) return 1 ;;
    esac

    local output
    if ! output="$(tasklist //FI "IMAGENAME eq LogonUI.exe" 2>&1)"; then
        printf '!! cannot tell whether the workstation is locked: %s\n' "$output" >&2
        return 0
    fi
    printf '%s' "$output" | grep -q "LogonUI.exe"
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
            if workstation_is_locked; then
                printf 'wait: the workstation is locked, so no UI result would mean anything\n'
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
        if workstation_is_locked; then
            printf 'workstation: LOCKED -- no UI result would mean anything\n'
        else
            printf 'workstation: unlocked\n'
        fi
        if [ -d "$lock_dir" ]; then
            printf 'ui lock: held by %s for %ss\n' "$(holder_name)" "$(holder_age)"
        else
            printf 'ui lock: free\n'
        fi
        ;;

    *)
        printf 'unknown command: %s\n\n' "$command" >&2
        usage >&2
        exit 2
        ;;
esac
