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
target_explicit=0
device_name=""
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

# A CSV action file to replay once the window is up, for `--actionfile`.
#
# Handled by the backend rather than by the app, so it works for every Pn
# without any of them knowing about it -- see Sources/GtkBackend/
# ActionFileReplay.swift and the format in Sources/InputEvent/README.md.
#
# `--actionfile` with no path uses testapp/actions/<app>-*.csv, because the
# common case is one file per app named after it and typing the path each time
# invites the wrong one being replayed against the right app.
#
# 供 `--actionfile` 使用：待視窗出現後重放的 CSV 動作檔。
#
# 由 backend 而非 app 處理，因此每一支 Pn 都不需要知道它的存在——詳見
# Sources/GtkBackend/ActionFileReplay.swift，格式見 Sources/InputEvent/README.md。
#
# `--actionfile` 未帶路徑時使用 testapp/actions/<app>-*.csv：常見情況是每支 app 一個以其命名的
# 檔案，而每次都手打路徑，只會招來「對正確的 app 重放了錯誤的檔案」。
action_file="${TEST_ACTION_FILE:-}"
actionfile_log="${app:l}-actionfile.log"

# The platform folder, not the whole tree.
#
# Action files are filed by the platform they passed on, because a list of
# coordinates does not travel: fonts, decorations and display scale all move
# things. Looking in every folder would find a file that works somewhere else
# and run it here, which fails as a series of clicks landing on nothing.
#
# 只在該平台的資料夾中尋找，而非整棵樹。
#
# 動作檔依「通過驗證的平台」歸檔，因為一串座標無法跨平台：字型、視窗裝飾與顯示縮放都會使位置改變。
# 若在所有資料夾中尋找，會找到一個「在別處可用」的檔案並在此執行，其失敗形式是一連串點擊全部落空。
platform_folder() {
    case "$target" in
        windows) printf 'win' ;;
        macos) printf 'mac' ;;
        # Named rather than left to the default. Falling through to `wsl` is how
        # `--ios --actionfile` came to resolve a WSL file and replay it on the
        # Simulator -- the failure the comment above describes, produced by the
        # very function meant to prevent it.
        # 明確列出，而非交給預設值。正是因為落入 `wsl`，`--ios --actionfile` 才會取得一個 WSL
        # 的動作檔並在模擬器上重放——上方註解所描述的那種失敗，由本應防止它的函式親手造成。
        ios) printf 'ios' ;;
        android) printf 'android' ;;
        *) printf 'wsl' ;;
    esac
}

default_action_file() {
    local folder
    folder="$(platform_folder)"
    local candidates=("$script_dir/actions/$folder/$app"-*.csv(N))
    if [ "${#candidates}" -eq 0 ]; then
        printf 'No action file for %s in %s/actions/%s\n' "$app" "$script_dir" "$folder" >&2
        printf 'A file appears there once it has been verified on that platform.\n' >&2
        exit 66
    fi
    if [ "${#candidates}" -gt 1 ]; then
        printf 'Several action files for %s; name one:\n' "$app" >&2
        printf '  %s\n' "${candidates[@]:t}" >&2
        exit 64
    fi
    printf '%s' "${candidates[1]}"
}

usage() {
    cat <<EOF_USAGE
Usage: ${script_path:t} [--wsl|-win|--windows|--macos|--ios|--android|--both] [-n|--no-build] [--showtime [seconds]|--showtime=seconds|--no-showtime] [--actionfile [path]]

Runs $app with the common UI dry-run flow.

The platform flag is optional. $app declares "$target"; on a host that cannot
drive it, the run moves to one that can and says so. Naming a platform this host
cannot drive is refused rather than redirected.
Default showtime: ${showtime_seconds}s

--actionfile replays a CSV of synthesised clicks and keystrokes once the window
is up. With no path, testapp/actions/$app-*.csv is used. The format is
documented in Sources/InputEvent/README.md.
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w|--wsl) target="wsl"; target_explicit=1; shift ;;
        -win|--windows) target="windows"; target_explicit=1; shift ;;
        -mac|--macos) target="macos"; target_explicit=1; shift ;;
        # iOS and Android arrived as their own top-level scripts, so reaching
        # them meant knowing a different command and a different flag spelling
        # for the same act -- run this app on that platform. They are targets
        # here like the rest; the scripts stay where they are and do the work.
        # iOS 與 Android 原本各自是頂層腳本，因此要用到它們就得記住另一個命令與另一套旗標寫法，
        # 而所做的其實是同一件事——在某個平台上執行這支 app。此處將它們與其他平台一視同仁地列為
        # target；那兩支腳本仍留在原處並負責實際工作。
        -ios|--ios) target="ios"; target_explicit=1; shift ;;
        -android|--android) target="android"; target_explicit=1; shift ;;
        -b|--both) target="both"; target_explicit=1; shift ;;
        -n|--no-build) do_build=0; shift ;;
        # Only iOS and Android have a device to choose. It lives here rather
        # than only in those two scripts so that one vocabulary covers every
        # platform; the resolution below refuses it where it means nothing.
        # 只有 iOS 與 Android 有裝置可選。此旗標置於此處而非僅存在於那兩支腳本中，是為了讓同一套
        # 詞彙涵蓋所有平台；下方的解析步驟會在它沒有意義之處拒絕它。
        --device)
            [ "$#" -gt 1 ] || { printf -- '--device requires a name or id\n' >&2; exit 64; }
            device_name="$2"
            shift 2
            ;;
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
        --actionfile)
            if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then
                action_file="$2"
                shift 2
            else
                action_file="$(default_action_file)"
                shift
            fi
            ;;
        --actionfile=*) action_file="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

# ==============================================================================
# Which platform this run is for, when nobody said.
#
# Every test script declares a TEST_TARGET, and 23 of the 24 name a Windows or
# WSL one -- they were written on the machine that could run them. On a Mac that
# makes the bare command wrong by default: `zsh testapp/test.zsh P8` resolves to
# `both`, reaches for `wsl.exe`, and fails for a reason that has nothing to do
# with P8.
#
# So a target the host cannot drive is replaced by one it can. The declared
# target is still honoured wherever it works, which matters on Windows: P8 says
# `both` there and `both` is exactly right, so nothing changes for that machine.
#
# An explicitly requested target is never substituted. Asking for `--wsl` on a
# Mac is refused rather than quietly redirected -- a flag that silently runs
# somewhere else is worse than one that fails.
#
# 沒有人指定時，這次執行屬於哪個平台。
#
# 每一支測試腳本都宣告了 TEST_TARGET，而 24 支中有 23 支指定的是 Windows 或 WSL——它們是在能夠
# 執行那些目標的機器上寫成的。在 Mac 上，這使得不帶旗標的指令預設就是錯的：
# `zsh testapp/test.zsh P8` 會解析為 `both`、去呼叫 `wsl.exe`，然後以一個與 P8 毫無關係的理由失敗。
#
# 因此，主機無法驅動的 target 會被替換為它能驅動的。在可行之處仍尊重原宣告的 target，這對 Windows
# 很重要：P8 在該處宣告 `both`，而 `both` 正是對的，因此那台機器上什麼也不會改變。
#
# 明確指定的 target 絕不會被替換。在 Mac 上要求 `--wsl` 會被拒絕，而非悄悄改到別處執行——一個
# 安靜地跑到別的地方去的旗標，比一個直接失敗的旗標更糟。
# ==============================================================================
host_platform() {
    # Same classification ui-lock.zsh uses, so the two cannot disagree about
    # what machine this is.
    # 與 ui-lock.zsh 採用相同的分類方式，兩者對「這是哪一台機器」不會有分歧。
    case "$(uname -s 2>/dev/null || printf unknown)" in
        Darwin) printf 'macos' ;;
        MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
        *) printf 'unknown' ;;
    esac
}

# `wsl` and `both` drive WSL through `wsl.exe`, so they need a Windows host
# rather than a Linux one -- running this from inside WSL, or on plain Linux,
# is not the same thing. `ios` and `android` delegate to scripts that already
# refuse to run anywhere but macOS.
# `wsl` 與 `both` 是透過 `wsl.exe` 驅動 WSL，因此需要的是 Windows 主機而非 Linux 主機——從 WSL
# 內部或在一般 Linux 上執行並非同一回事。`ios` 與 `android` 則委派給本就拒絕在 macOS 以外執行的
# 腳本。
case "$(host_platform)" in
    macos)
        host_targets=(macos ios android)
        host_default="macos"
        ;;
    windows)
        host_targets=(windows wsl both)
        host_default="windows"
        ;;
    *)
        # Unknown host: assume nothing and change nothing. A wrong guess here
        # would send a run to a platform the caller never asked for.
        # 未知主機：不做任何假設，也不做任何更動。此處猜錯會把一次執行送往呼叫者從未要求的平台。
        host_targets=()
        host_default=""
        ;;
esac

if [ -n "$device_name" ] && [[ "$target" != "ios" && "$target" != "android" ]]; then
    printf -- '--device applies to --ios and --android only; target is "%s".\n' "$target" >&2
    exit 64
fi

if [ -n "$host_default" ] && [[ ! " ${host_targets[*]} " == *" $target "* ]]; then
    if [ "$target_explicit" -eq 1 ]; then
        printf 'Target "%s" cannot run on this host (%s).\n' "$target" "$(host_platform)" >&2
        printf 'Available here: %s\n' "${host_targets[*]}" >&2
        exit 64
    fi
    printf '==> %s defaults to "%s"; running "%s" on this host\n' \
        "$app" "$target" "$host_default"
    target="$host_default"
fi

# Takes a screenshot and says so when it does not.
#
# The call sites used to end in `|| true`, which was accurate while
# screenshot.zsh exited 0 whatever happened -- it could not fail, so there was
# nothing to swallow. It can now: 1 when it produced no image, 3 when the host
# has no capture path at all. `|| true` would discard exactly the signal that
# was missing before.
#
# The run is not aborted. A screenshot is evidence, not the assertion, and a
# window that rendered and logged its diagnostics is still worth reading. But
# the failure is announced where it happens and counted for the summary, so a
# run that produced no pictures cannot look like one that did.
#
# 擷取畫面；若未能擷取，就明白說出來。
#
# 各呼叫點原本以 `|| true` 結尾，而在 screenshot.zsh 無論如何都回傳 0 的年代，那是準確的——它不
# 可能失敗，因此也沒有什麼可被吞掉。現在它會失敗了：未產生影像時回傳 1，主機根本沒有擷取路徑時
# 回傳 3。`|| true` 會恰好丟棄那個先前一直欠缺的訊號。
#
# 執行不會因此中止。截圖是證據而非斷言，一個已完成繪製並寫下診斷的視窗仍然值得閱讀。但失敗會在
# 它發生之處被公告，並計入摘要——如此一來，一次沒有產出任何圖片的執行，就不會看起來像有產出。
screenshot_failures=0
capture() {
    zsh "$script_dir/screenshot.zsh" "$@"
    # Not `status`. That is one of zsh's special parameters -- a read-only alias
    # for $? -- so `local status=$?` aborts the run with
    # "capture:2: read-only variable: status". The same family as `path`,
    # `options` and `watch`; this file's own notes warn about it, and the warning
    # was still not enough to avoid it.
    # 不用 `status`。它是 zsh 的特殊參數之一——`$?` 的唯讀別名——因此 `local status=$?` 會以
    # 「capture:2: read-only variable: status」中止執行。與 `path`、`options`、`watch` 同一族；
    # 本檔自身的註解已提出警告，而該警告仍不足以讓人避開它。
    local rc=$?
    [ "$rc" -eq 0 ] && return 0

    screenshot_failures=$(( screenshot_failures + 1 ))
    case "$rc" in
        3) printf '!! no screenshot: this host has no capture path (screenshot.zsh exited 3)\n' >&2 ;;
        *) printf '!! no screenshot: screenshot.zsh exited %d and produced no image\n' "$rc" >&2 ;;
    esac
    return 0
}

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

    if [ "$target" = "macos" ]; then
        pkill -TERM -x "$app" 2>/dev/null || true
        printf '    macOS: clear\n'
        return 0
    fi

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
    print_actionfile_report "$out/$actionfile_log"
}

# What the backend said about the replay, if one was asked for.
#
# Printed unconditionally when --actionfile was passed, including when the file
# produced no line at all -- silence there means the app died before the replay
# or the backend never saw the flag, and both look identical to a replay that
# ran and did nothing.
#
# 傳入 --actionfile 時一律印出 backend 對重放的說明，即使該檔案完全沒有產生任何一行——那種沉默
# 代表 app 在重放之前就結束了，或 backend 根本沒看到該旗標，而這兩者與「重放執行了卻毫無作用」
# 在外觀上完全相同。
print_actionfile_report() {
    local path="$1"
    if [ -z "$action_file" ]; then
        return 0
    fi
    printf '==> Action file report\n'

    # Captured and split with zsh's own `${(f)…}` rather than piped through
    # sed. Two reasons, both measured here: `sed` was not on PATH in this
    # context and the function died with `command not found`, and `if grep |
    # sed` tests *sed's* status -- so a grep that found nothing still reported
    # success and printed nothing at all.
    # 以 zsh 自身的 `${(f)…}` 擷取並分行，而非透過管線交給 sed。兩個理由都是在此處實測到的：
    # `sed` 不在此情境的 PATH 上，該函式因而以 `command not found` 中止；而 `if grep | sed`
    # 判斷的是 **sed** 的結束狀態——因此即使 grep 一無所獲，仍會回報成功且什麼都不印。
    local report
    report="$(grep -a actionfile "$path" 2>/dev/null)"
    if [ -n "$report" ]; then
        printf '    %s\n' ${(f)report}
    else
        printf '    no report -- the app exited before replaying, or never saw the flag\n'
    fi
}

print_summary_wsl() {
    printf '\n==> WSLg %s diagnostics\n' "$app"
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $log_name $extra_log 2>/dev/null | sed 's/^$app [0-9-]* [0-9:]* +0000 //' | sort -u" || true
    # Read through WSL: the app ran from the rsync'd Linux copy, so its stderr
    # landed in the Linux output directory, not the Windows one.
    # 透過 WSL 讀取：app 是從 rsync 過去的 Linux 副本啟動的，其 stderr 落在 Linux 端的 output
    # 目錄，而非 Windows 端。
    if [ -n "$action_file" ]; then
        printf '==> Action file report\n'
        local report
        report="$(MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -a actionfile ~/proj/swift-cross-ui/testapp/output/$actionfile_log 2>/dev/null" \
            || true)"
        if [ -n "$report" ]; then
            printf '%s\n' "$report" | sed 's/^/    /'
        else
            printf '    no report -- the app exited before replaying, or never saw the flag\n'
        fi
    fi
}

run_windows() {
    local out="$script_dir/output"
    local label="${app:l}-windows"

    # GTK's bin directory on PATH for the launch, not only for the build.
    #
    # compile.zsh exports it, but that only lasts for the build shell -- so an
    # app built with -gtk4 and launched from here died before main with
    # `api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file`. The
    # missing library is the UCRT rather than GTK, which sends the reader
    # looking for a broken Visual C++ install; what is actually missing is the
    # whole directory that would have satisfied both.
    #
    # This was invisible until an action file forced stderr to be kept. Every
    # earlier Windows run sent it to /dev/null, so a -gtk4 build that never
    # started looked exactly like one that started and rendered nothing.
    #
    # 讓 GTK 的 bin 目錄在「啟動」時也位於 PATH 上，而不只是在「建置」時。
    #
    # compile.zsh 有 export 它，但那只在建置的 shell 中有效——因此以 -gtk4 建置、再由此處啟動的
    # app，會在進入 main 之前就以
    # `api-ms-win-crt-locale-l1-1-0.dll: cannot open shared object file` 死掉。缺少的那個函式庫是
    # UCRT 而非 GTK，這會把讀者引向「Visual C++ 安裝損壞」的方向；但真正缺少的，是那個原本能同時
    # 滿足兩者的整個目錄。
    #
    # 在動作檔迫使 stderr 被保留之前，此問題完全不可見。先前每一次 Windows 執行都把 stderr 送進
    # /dev/null，因此「一個從未啟動的 -gtk4 建置」與「一個啟動了卻什麼都沒繪製的建置」看起來
    # 一模一樣。
    # Converted to POSIX form before it goes anywhere near PATH. `:` is the
    # separator here, so `C:/gtk4/bin` is not one entry -- it is `C` and
    # `/gtk4/bin`, neither of which exists, and the entry that was supposed to
    # fix the launch instead adds two broken ones. The first attempt at this fix
    # did exactly that and changed nothing.
    # 在放進 PATH 之前先轉為 POSIX 形式。此處的 `:` 是分隔符，因此 `C:/gtk4/bin` 並非單一項目——
    # 它是 `C` 與 `/gtk4/bin` 兩項，兩者都不存在；原本要修好啟動問題的那一項，反而新增了兩個壞掉的
    # 項目。本修正的第一次嘗試正是如此，且毫無作用。
    local gtk_prefix="${GTK4_PREFIX:-C:/gtk4}"
    local gtk_bin
    gtk_bin="$(cygpath -u "$gtk_prefix/bin" 2>/dev/null || printf '%s' "$gtk_prefix/bin")"
    if [ -d "$gtk_bin" ]; then
        export PATH="$gtk_bin:$PATH"
    fi

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for Windows\n' "$app"
        # SCUI_DEBUG=1 whenever an action file is being replayed, because
        # without it the flag does not exist in the binary. A build that omits
        # it produces an executable that ignores -actionfile entirely -- which
        # is the whole point of DebugFeatures, and which this script then
        # reported as "the app never saw the flag". Correct, and useless.
        # 只要要重放動作檔就帶上 SCUI_DEBUG=1，因為少了它，該旗標根本不存在於執行檔中。省略它的
        # 建置會產生一個完全忽略 -actionfile 的執行檔——那正是 DebugFeatures 的目的，而本腳本當時
        # 把它回報為「app 從未看到該旗標」。正確，但毫無用處。
        SCUI_DEBUG="${action_file:+1}" \
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
    local args="$app_args"
    if [ -n "$action_file" ]; then
        # cygpath -m, because the app is a Windows binary and cannot open an
        # MSYS path such as /c/Users/... . Nothing reports this: Foundation
        # returns nil, the backend logs that the file could not be read, and
        # the window sits there looking like the replay did nothing.
        # 使用 cygpath -m：該 app 是 Windows 原生執行檔，無法開啟 /c/Users/... 這類 MSYS 路徑。
        # 沒有任何機制會回報此事：Foundation 回傳 nil，backend 記錄檔案無法讀取，而視窗就這樣停在
        # 那裡，看起來就像重放什麼都沒做。
        args="$args -actionfile $(cygpath -m "$action_file")"
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

    printf '==> Launching %s.exe\n' "$app"
    # stderr kept, not discarded, when a file is being replayed. The backend
    # reports there whether the replay ran, and a failed replay leaves a window
    # that looks untouched -- indistinguishable from the app ignoring the input,
    # and the wrong thing to go looking for. Measured: the first run through
    # this script dropped the line and the failure read as a product defect.
    # 重放動作檔時保留 stderr 而不丟棄。backend 在該處回報重放是否執行；失敗的重放會留下一個看似
    # 未被觸碰的視窗，與「app 忽略了輸入」無法區分，而那是錯誤的追查方向。實測：本腳本的第一次
    # 執行丟掉了這行訊息，於是該失敗看起來像是產品缺陷。
    if [ -n "$action_file" ]; then
        ( cd "$out" && env ${(z)app_env} "./$app.exe" ${(z)args} \
            >/dev/null 2>"$actionfile_log" & )
    else
        ( cd "$out" && env ${(z)app_env} "./$app.exe" ${(z)args} >/dev/null 2>&1 & )
    fi

    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_windows "$out"; then
        showtime "Windows $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
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
        # See the Windows branch: without SCUI_DEBUG=1 the -actionfile flag is
        # not compiled into the binary at all.
        # 見 Windows 分支：少了 SCUI_DEBUG=1，-actionfile 旗標根本不會被編入執行檔。
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu --cd /home/lowei/proj/swift-cross-ui -- \
            zsh -lc "SCUI_DEBUG='${action_file:+1}' zsh testapp/compile.zsh $app" 2>&1 \
            | grep -E 'error:|Build of product' || true
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && : > $log_name$clear_extra_fragment"

    local args="$app_args"
    local redirection=">/dev/null 2>&1"
    if [ -n "$action_file" ]; then
        # Re-rooted onto the WSL copy of the repo. The file lives in the
        # Windows checkout, which WSL can reach as /mnt/c -- but the app is
        # launched from the rsync'd Linux copy, and giving it a /mnt/c path
        # would replay whichever version happened to be on the Windows side.
        # A path outside the repo is rejected rather than guessed at.
        # 重新指向 repo 的 WSL 副本。該檔案位於 Windows 端的 checkout，WSL 可透過 /mnt/c 存取
        # ——但 app 是由 rsync 過去的 Linux 副本啟動的，給它 /mnt/c 路徑等於重放「Windows 端當下
        # 恰好是哪個版本」。位於 repo 之外的路徑一律拒絕，而不做猜測。
        local relative="${action_file#$script_dir/}"
        if [ "$relative" = "$action_file" ]; then
            printf 'Action file must be inside %s: %s\n' "$script_dir" "$action_file" >&2
            exit 64
        fi
        args="$args -actionfile /home/lowei/proj/swift-cross-ui/testapp/$relative"
        # X11, not Wayland. xdotool speaks XTEST, which is an X11 extension; a
        # GTK 4 app left to its own devices under WSLg becomes a Wayland client
        # with no X window at all, and Wayland deliberately does not let one
        # client drive another. Forced here rather than left to the tester,
        # because the failure is a replay that reports it could not find the
        # app's own window -- which reads as a bug in the finding, not as the
        # session being the wrong kind.
        # 強制使用 X11 而非 Wayland。xdotool 使用的 XTEST 是 X11 擴充；在 WSLg 下放任不管的 GTK 4
        # app 會成為 Wayland client，根本沒有 X window，而 Wayland 也刻意不允許一個 client 驅動
        # 另一個。在此強制而非交由測試者設定，是因為其失敗表現為「重放回報找不到 app 自己的視窗」
        # ——那看起來像是尋找邏輯的 bug，而不像是 session 型別不對。
        app_env="GDK_BACKEND=x11 $app_env"
        # See the Windows branch: stderr carries the backend's report of whether
        # the replay ran, and discarding it makes a failed replay look like a
        # product defect.
        # 見 Windows 分支：stderr 承載 backend 對「重放是否執行」的回報，丟棄它會使失敗的重放
        # 看起來像產品缺陷。
        redirection=">/dev/null 2>$actionfile_log"
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

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
        zsh -lc "env $app_env ./$app $args $redirection" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_wsl; then
        showtime "WSLg $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
    fi

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
    printf '==> Closed %s under WSLg\n' "$app"
    print_summary_wsl
}

# macOS uses AppKitSynthesiser, which posts directly into the app's own event
# queue and therefore does not need System Events Accessibility permission.
# macOS 使用 AppKitSynthesiser，直接把事件送入 app 自己的 event queue，因此不需要
# System Events 的輔助使用權限。
run_macos() {
    local out="$script_dir/output"
    local label="${app:l}-macos"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building %s for macOS\n' "$app"
        SCUI_DEBUG="${action_file:+1}" \
            zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build complete|Build of product' || true
    fi

    mkdir -p "$out"
    : > "$out/$log_name"
    local action_log="$out/$actionfile_log"
    : > "$action_log"
    local args=( ${(z)app_args} )
    if [ -n "$action_file" ]; then
        action_file="${action_file:A}"
        args+=( -actionfile "$action_file" )
        printf '==> Action file: %s\n' "${action_file:t}"
    fi

    printf '==> Launching %s on macOS\n' "$app"
    ( cd "$out" && env ${(z)app_env} "./$app" ${(q)args} >"$action_log" 2>&1 & )

    # macOS took no screenshots at all until now -- not failed ones, none. The
    # run announced "final screenshot follows" and then did not follow, because
    # screenshot.zsh had no macOS path to call. It has one now.
    # macOS 在此之前完全不曾截圖——不是失敗，而是根本沒有嘗試。執行過程會宣告
    # 「final screenshot follows」，然後並未跟上，因為 screenshot.zsh 當時沒有 macOS 路徑可供
    # 呼叫。現在它有了。
    capture -d 1 -w "$title" "$label-1s"
    if wait_for_marker_macos; then
        showtime "macOS $app"
        capture -d 1 -w "$title" "$label-final"
    else
        capture -d 0 -w "$title" "$label-timeout"
    fi

    pkill -TERM -x "$app" 2>/dev/null || true
    printf '==> Closed %s on macOS\n' "$app"
    print_summary_macos
}

wait_for_marker_macos() {
    local waited=0

    if [ -z "$marker" ]; then
        printf '==> No render marker configured; using launch timing\n'
        sleep 1
        return 0
    fi

    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$script_dir/output/$log_name" ] \
            && grep -q "$marker" "$script_dir/output/$log_name" 2>/dev/null; then
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

print_summary_macos() {
    local out="$script_dir/output"
    printf '\n==> macOS %s diagnostics\n' "$app"
    grep -hE "$summary_pattern" "$out/$log_name" "$out/$actionfile_log" 2>/dev/null \
        | sed "s/^$app [0-9-]* [0-9:]* +0000 //" | sort -u || true
}

# Ctrl-C closes the app rather than orphaning it.
#
# The app is launched detached -- a subshell on Windows, `disown` under WSLg --
# so it outlives this script's own process group. Without this trap, Ctrl-C
# during the showtime wait killed the runner and left the window open, and the
# next run's `kill_existing` was the only thing that ever closed it. `kill_existing`
# already knows how to close it on both platforms, so the trap reuses it and
# exits with the conventional 130.
#
# Ctrl-C 會關閉該 app，而非使其成為孤兒行程。
#
# 該 app 以分離方式啟動——Windows 上是子 shell，WSLg 下是 `disown`——因此它的生命週期超出本腳本
# 自身的行程群組。若無此 trap，在 showtime 等待期間按下 Ctrl-C 會結束執行器卻留下視窗開著，而唯一
# 會關掉它的，是下一次執行的 `kill_existing`。`kill_existing` 本就知道如何在兩個平台上關閉它，因此
# 此 trap 直接沿用，並以慣例的 130 結束。
# One UI test at a time, taken here rather than left to whoever is running one.
#
# A mutex nobody calls is not a mutex. ui-lock.zsh was added so two tests could
# not screenshot each other, and then every test runner went on launching apps
# without asking for it -- so it only worked when a person or an agent
# remembered, which is the failure mode it exists to remove. Acquiring it here
# means every path through test.zsh is serialised, including the ones nobody
# thought about.
#
# It also waits while the workstation is locked, because a locked desktop makes
# capture return bare wallpaper and synthesised input reach nothing, with no
# error anywhere.
#
# SCUI_NO_UI_LOCK=1 skips it. A developer running one test on their own machine
# should not be blocked for up to 60 seconds by a lock left over from something
# they are not running, and a gate with no way past it gets deleted rather than
# fixed.
#
# 一次只跑一個 UI 測試，且由此處取得，而非交給執行測試的人自行處理。
#
# 沒有人呼叫的互斥鎖不是互斥鎖。當初加入 ui-lock.zsh 是為了讓兩個測試不會互相截圖，然而每一支
# 測試 runner 依舊照常啟動 app 而不去索取它——於是它只在人或 agent 記得時才生效，而那正是它要
# 消除的失敗模式。在此取得，代表經過 test.zsh 的每一條路徑都被序列化，包含沒人想到的那些。
#
# 它同時會在工作站鎖定期間等待，因為鎖定的桌面會讓擷取只得到桌布、讓合成輸入什麼也碰不到，而且
# 任何地方都不會報錯。
#
# SCUI_NO_UI_LOCK=1 可略過。開發者在自己機器上跑單一測試，不該被一個與他無關的殘留鎖擋上 60 秒；
# 而一個沒有繞道的閘門，最終會被刪掉而不是被修好。
ui_lock_script="$script_dir/ui-lock.zsh"
ui_lock_holder="test-${app:l}"
ui_lock_held=0

release_ui_lock() {
    [ "$ui_lock_held" -eq 1 ] || return 0
    ui_lock_held=0
    zsh "$ui_lock_script" release "$ui_lock_holder" >/dev/null 2>&1 || true
}

on_interrupt() {
    printf '\n==> Interrupted; closing %s\n' "$app"
    kill_existing
    release_ui_lock
    exit 130
}
trap on_interrupt INT

# Not for the delegated targets: `exec` replaces this process, so neither the
# release below nor an EXIT trap would ever run, and the lock would be held by
# nobody until it went stale.
# 不套用於委派的 target：`exec` 會取代本行程，因此下方的釋放與 EXIT trap 都不會執行，該鎖將由
# 「沒有人」持有，直到它過期為止。
case "$target" in
    ios|android) ;;
    *)
        if [ "${SCUI_NO_UI_LOCK:-0}" != "1" ]; then
            zsh "$ui_lock_script" acquire "$ui_lock_holder"
            ui_lock_held=1
            trap release_ui_lock EXIT
        fi
        ;;
esac

kill_existing

# iOS and Android delegate rather than reimplement. Their scripts already take a
# Pn as their first argument, so the only thing missing was a way to reach them
# through the same command and the same flag as every other platform.
#
# `exec` so the delegate's exit status is this script's, and so the trap above
# does not outlive it -- the delegate owns the app it launches and does its own
# cleanup.
#
# iOS 與 Android 採「轉呼叫」而非重新實作。那兩支腳本本來就以 Pn 作為第一個引數，因此唯一缺少的，
# 只是一條「用與其他平台相同的命令與相同的旗標」抵達它們的途徑。
#
# 使用 `exec`，讓委派對象的結束狀態即為本腳本的結束狀態，且上方的 trap 不會存活超過它——啟動的
# app 由委派對象自己擁有，也由它自己清理。
# The flags this run resolved to, in the delegate's spelling.
#
# `"$@"` was passed here before, and by this point the parse loop above has
# shifted every argument away -- so the delegate received the app name and
# nothing else. `test.zsh P14 --ios -n --showtime 5` reached test_ios.zsh as
# `test_ios.zsh P14`: the build was performed anyway and showtime fell back to
# 30. Traced with `zsh -x`; the exec line read `zsh …/test_ios.zsh P14`.
#
# Rebuilding the flags from the parsed state rather than forwarding raw
# arguments also means the two vocabularies cannot drift: whatever spelling the
# caller used, the delegate is handed the one it documents.
#
# 本次執行所解析出的旗標，以委派對象的寫法表達。
#
# 此處原本傳的是 `"$@"`，而到達這裡時，上方的解析迴圈已把每一個引數 shift 掉——因此委派對象收到
# 的只有 app 名稱，其餘什麼都沒有。`test.zsh P14 --ios -n --showtime 5` 抵達 test_ios.zsh 時是
# `test_ios.zsh P14`：建置照樣執行，showtime 也退回 30。以 `zsh -x` 追蹤確認，exec 那一行是
# `zsh …/test_ios.zsh P14`。
#
# 由解析後的狀態重建旗標、而非轉送原始引數，也使兩套詞彙不會分歧：無論呼叫端用哪種寫法，交到委派
# 對象手上的都是它自己文件所載的那一種。
delegated_args() {
    local -a args
    [ "$do_build" -eq 0 ] && args+=(--no-build)
    if [ "$showtime_seconds" -eq 0 ]; then
        args+=(--no-showtime)
    else
        args+=(--showtime "$showtime_seconds")
    fi
    [ -n "$action_file" ] && args+=(--actionfile "${action_file:A}")
    [ -n "$device_name" ] && args+=(--device "$device_name")
    printf '%s\n' "${args[@]}"
}

run_ios() {
    local -a args
    args=("${(@f)$(delegated_args)}")
    exec zsh "$script_dir/test_ios.zsh" "$app" "${args[@]}"
}

run_android() {
    local -a args
    args=("${(@f)$(delegated_args)}")
    exec zsh "$script_dir/test_android.zsh" "$app" "${args[@]}"
}

case "$target" in
    wsl) run_wsl ;;
    windows) run_windows ;;
    macos) run_macos ;;
    ios) run_ios ;;
    android) run_android ;;
    both) run_wsl; printf '\n'; run_windows ;;
    *) printf 'Unknown target: %s\n' "$target" >&2; exit 64 ;;
esac
