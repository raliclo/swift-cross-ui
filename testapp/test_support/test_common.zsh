#!/usr/bin/env zsh
# Shared GUI dry-run helper for test_P*.zsh wrappers.
#
# The flow intentionally matches test_P8.zsh: build, launch, take an early
# screenshot, optionally wait for an app render marker, keep the window open for
# tester collaboration, take a final screenshot, close, and print diagnostics.

set -euo pipefail

support_dir="${0:a:h}"
script_dir="${support_dir:h}"
script_path="${0:a}"
app="${TEST_APP:?TEST_APP is required}"
title="${TEST_TITLE:-$app}"
log_name="${TEST_LOG_NAME:-${app:l}-debug-events.log}"
marker="${TEST_MARKER:-}"
timeout_seconds="${TEST_TIMEOUT_SECONDS:-30}"
showtime_seconds="${TEST_SHOWTIME_SECONDS:-30}"
target="${TEST_TARGET:-wsl}"
do_build=1
summary_pattern="${TEST_SUMMARY_PATTERN:-RENDER COMPLETE|content:|geometry|size|scroll|Scroll|#}"
app_args="${TEST_APP_ARGS:---debug}"

# Environment the app is launched with, as `NAME=value` pairs separated by
# spaces. Empty for most apps.
#
# Some diagnostics live in SwiftCrossUI itself rather than in the test app, and
# those are gated on an environment variable because the library has no
# command line to read. P7 needs SCUI_DEBUG_SPLIT: without it the run still
# reports every content size, but not the bounds the layout system hands the
# backend nor where the divider actually ended up -- and content width is not
# pane width. Reading one as the other produced two confident, wrong diagnoses
# of #556 before the variable existed.
# app 啟動時附帶的環境變數，格式為以空白分隔的 `NAME=value`，多數 app 為空。
#
# 部分診斷位於 SwiftCrossUI 本身而非測試 app，只能以環境變數開關，因為函式庫讀不到
# 命令列。P7 需要 SCUI_DEBUG_SPLIT：少了它仍會回報所有內容尺寸，但看不到 layout
# 系統交給 backend 的上下界，也看不到分隔線最後停在哪——而內容寬度並不等於 pane
# 寬度，把兩者混為一談曾對 #556 造成兩次自信但錯誤的判斷。
app_env="${TEST_APP_ENV:-}"

# An optional second log to clear before the run and include in the summary.
# Diagnostics that live in the library write their own file rather than the
# app's, so without this the run would silently report only half of what it
# collected -- and a summary that looks complete while missing the deciding
# numbers is worse than one that is obviously empty.
# 可選的第二個 log：執行前一併清空，摘要時一併納入。位於函式庫的診斷會寫自己的檔案
# 而非 app 的，若不處理，執行結果會靜默地只呈現一半——而看起來完整卻缺少關鍵數字的
# 摘要，比明顯空白的摘要更危險。
extra_log="${TEST_EXTRA_LOG:-}"

# The remote command is assembled here rather than tested inside the string
# sent to WSL. A conditional written there is parsed before it is evaluated, so
# an empty name still leaves `: >` with nothing to redirect into and the whole
# command dies with `parse error near ';'` -- before the app is ever launched.
# Building the fragment in advance means the empty case contributes no text.
# 遠端指令在此組好，而不是在送往 WSL 的字串內做條件判斷。字串裡的條件式會先被解析
# 再求值，因此名稱為空時 `: >` 仍然沒有重導向目標，整條指令會以
# `parse error near ';'` 失敗——而且是在 app 啟動之前。事先組好片段，空值就不會
# 產生任何文字。
clear_extra_fragment=""
if [ -n "$extra_log" ]; then
    clear_extra_fragment=" && : > $extra_log"
fi

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} [--wsl|--windows|--both] [-n|--no-build] [--showtime [seconds]|--showtime=seconds|--no-showtime]

Runs $app with the common UI dry-run flow.
Default target: $target
Default showtime: ${showtime_seconds}s
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w|--wsl) target="wsl"; shift ;;
        --windows) target="windows"; shift ;;
        -b|--both) target="both"; shift ;;
        -n|--no-build) do_build=0; shift ;;
        --showtime)
            if [ "$#" -gt 1 ] && [[ "$2" == <-> ]]; then
                showtime_seconds="$2"
                shift 2
            else
                showtime_seconds=30
                shift
            fi
            ;;
        --showtime=*)
            showtime_seconds="${1#*=}"
            if ! [[ "$showtime_seconds" == <-> ]]; then
                printf 'Invalid --showtime value: %s\n' "$showtime_seconds" >&2
                exit 64
            fi
            shift
            ;;
        --no-showtime) showtime_seconds=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

showtime() {
    local label="$1"

    if [ "$showtime_seconds" -le 0 ]; then
        return 0
    fi

    printf '==> Showtime: keeping %s open for %ss after render\n' "$label" "$showtime_seconds"
    printf '    You can inspect or interact with the window now; final screenshot follows.\n'
    sleep "$showtime_seconds"
}

kill_existing() {
    printf '==> Closing any running %s\n' "$app"

    if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $app.exe" 2>/dev/null \
        | grep -qi "$app.exe"; then
        MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" >/dev/null 2>&1 || true
    fi
    if MSYS2_ARG_CONV_EXCL='*' tasklist.exe /NH /FI "IMAGENAME eq $app.exe" 2>/dev/null \
        | grep -qi "$app.exe"; then
        printf '    WARNING: %s.exe is still running on Windows\n' "$app"
    else
        printf '    Windows: clear\n'
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "pkill -x $app 2>/dev/null; sleep 1; pgrep -ax $app || printf '    WSLg: clear\n'" \
        2>/dev/null || true
}

wait_for_marker_windows() {
    local out="$1"
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$out/$log_name" ] && grep -q "$marker" "$out/$log_name" 2>/dev/null; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

wait_for_marker_wsl() {
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using screenshot timing\n'
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -q '$marker' ~/proj/swift-cross-ui/testapp/output/$log_name 2>/dev/null"; then
            printf ' -- rendered after %ss\n' "$waited"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    printf '\n==> Timed out after %ss\n' "$timeout_seconds"
    return 1
}

print_summary_windows() {
    local out="$script_dir/output"

    printf '\n==> Windows %s diagnostics\n' "$app"
    grep -hE "$summary_pattern" "$out/$log_name" ${extra_log:+"$out/$extra_log"} 2>/dev/null \
        | sed "s/^$app [0-9-]* [0-9:]* +0000 //" | sort -u || true
}

print_summary_wsl() {
    printf '\n==> WSLg %s diagnostics\n' "$app"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $log_name $extra_log 2>/dev/null | sed 's/^$app [0-9-]* [0-9:]* +0000 //' | sort -u" || true
}

run_windows() {
    local out="$script_dir/output"
    local label="${app:l}-windows"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for Windows\n' "$app"
        zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build of product' || true
    fi

    mkdir -p "$out"
    : > "$out/$log_name"
    # `if`, not `[ -n ... ] && ...`: under `set -e` a false test as the last
    # command in the list aborts the script.
    # 用 `if` 而非 `[ -n ... ] && ...`：在 `set -e` 下，測試為假會使整個腳本中止。
    if [ -n "$extra_log" ]; then
        : > "$out/$extra_log"
    fi
    printf '==> Launching %s.exe\n' "$app"
    ( cd "$out" && env ${(z)app_env} "./$app.exe" ${(z)app_args} >/dev/null 2>&1 & )

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-1s" || true
    if wait_for_marker_windows "$out"; then
        showtime "Windows $app"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-final" || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" "$label-timeout" || true
    fi

    if MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" 2>&1 | grep -q SUCCESS; then
        printf '==> Closed %s.exe\n' "$app"
    else
        printf '==> WARNING: %s.exe may still be running; check with tasklist\n' "$app"
    fi

    print_summary_windows
}

run_wsl() {
    local label="${app:l}-wslg"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Syncing sources to WSL\n'
        zsh "$script_dir/rsync_WSL.zsh" >/dev/null
        printf '==> Building %s for WSLg\n' "$app"
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui -- \
            zsh testapp/compile.zsh "$app" 2>&1 | grep -E 'error:|Build of product' || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && : > $log_name$clear_extra_fragment"

    printf '==> Launching %s under WSLg\n' "$app"
    # Plain `$app_args`, deliberately unadorned. Unlike the Windows branch just
    # above -- which passes real argv words and so wants `(z)` -- this builds a
    # single command *string* for `zsh -lc`, and the inner shell does its own
    # parsing. Both parameter flags break that, in opposite directions:
    #
    #   (q)  escapes the spaces, so the inner shell sees one argument:
    #        P6 received `-f -autoplay --debug` whole and matched no flag.
    #   (z)  splits into separate words even inside double quotes, so `-lc`
    #        took `env ./P6 -f` as the command and quietly dropped the rest
    #        into its positional parameters. Measured: P6 logged
    #        `autoplay off` and never started playback.
    #
    # Every wrapper before P6 passed the single word `--debug`, where `(q)` is
    # a no-op -- which is why the original went unnoticed for so long, and why
    # the first attempt at a fix reproduced the same class of bug.
    # A value containing a space must be quoted inside TEST_APP_ARGS
    # (`-f "/path/with a space.webm"`); the quotes travel as literal text and
    # the inner shell honours them. Verified both ways.
    # 刻意使用未加任何旗標的 `$app_args`。與上方 Windows 分支不同——那裡傳遞的是真正
    # 的 argv 詞，因此需要 `(z)`——這裡組出的是給 `zsh -lc` 的單一命令「字串」，由內層
    # shell 自行解析。兩個參數旗標都會破壞它，且方向相反：
    #
    #   (q)  跳脫空白，內層 shell 只看到一個參數：P6 收到完整的
    #        `-f -autoplay --debug`，任何旗標都比對不到。
    #   (z)  即使在雙引號內仍會拆成多個詞，於是 `-lc` 把 `env ./P6 -f` 當成命令，
    #        其餘的靜靜落入位置參數。實測：P6 記錄 `autoplay off`，從未開始播放。
    #
    # P6 之前的每個 wrapper 都只傳單一詞 `--debug`，該情況下 `(q)` 等同無作用——這正是
    # 原本的問題長期未被發現的原因，也是第一次嘗試修正時又重現同類錯誤的原因。
    # 含空白的值必須在 TEST_APP_ARGS 內自行加引號（`-f "/path/with a space.webm"`）；
    # 引號會以字面文字傳遞，由內層 shell 解讀。兩種情況皆已驗證。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui/testapp/output -- \
        zsh -lc "env $app_env ./$app $app_args >/dev/null 2>&1" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-1s" || true
    if wait_for_marker_wsl; then
        showtime "WSLg $app"
        zsh "$script_dir/screenshot.zsh" -d 1 -w "$title" "$label-final" || true
    else
        zsh "$script_dir/screenshot.zsh" -d 0 -w "$title" "$label-timeout" || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
    printf '==> Closed %s under WSLg\n' "$app"
    print_summary_wsl
}

kill_existing

case "$target" in
    wsl) run_wsl ;;
    windows) run_windows ;;
    both) run_wsl; printf '\n'; run_windows ;;
    *) printf 'Unknown target: %s\n' "$target" >&2; exit 64 ;;
esac
