#!/usr/bin/env zsh
# One dry-run of P7: build, launch, wait until it has actually rendered,
# screenshot, close, and print the geometry it measured.
#
#   zsh testapp/test_p7.zsh              # Windows / WinUIBackend
#   zsh testapp/test_p7.zsh -w           # WSLg / GtkBackend
#   zsh testapp/test_p7.zsh -b           # both, one after the other
#   zsh testapp/test_p7.zsh -n           # skip the build, just run
#
# 一次 P7 dry-run：建置、啟動、等到真的畫完、截圖、關窗、印出量到的幾何數字。
#
# The step that is easy to get wrong is the wait. Sleeping a fixed number of
# seconds either captures a half-built window or wastes time, so this polls the
# app's own log for the line it prints once every pane has been measured.
# 最容易做錯的是「等待」。固定睡幾秒不是拍太早就是白等，因此改為輪詢 app 自己在
# 量測完成時印出的那一行。
#
# --------------------------------------------------------------------------
# What this script had to learn the hard way
#
# Every bug found while building it shared one shape: the action appeared to
# succeed while quietly doing nothing, or the work succeeded while the way of
# observing it broke. Each produced confident, wrong conclusions about
# GtkBackend and WinUIBackend that took a measurement to undo. They are listed
# here because the same shapes will recur in the next test script.
#
# 1. `taskkill /F /IM` -- Git Bash rewrites the /F and /IM arguments, so the
#    call failed and P7.exe accumulated across runs. Its output had been sent
#    to /dev/null, so nothing said so. Needs MSYS2_ARG_CONV_EXCL='*'.
# 2. `wsl.exe ... bash -lc "... &"` -- backgrounding inside the inner shell
#    lets that shell exit and take the app with it. The app never ran, and the
#    summary reported the *previous* run's numbers as if they were fresh.
# 3. `pkill -f 'output/P7'` -- the app starts as `cd .../output && ./P7`, so
#    its command line is `./P7 --debug` and never contains "output/P7". pkill
#    matched nothing, exited happily, and left the window open.
# 4. Cleanup ran after the build, so a stale window stayed on screen through
#    a rebuild and could be captured instead of the new one.
# 5. A backgrounded wsl.exe holding this script's stdout swallowed the
#    progress lines. The run was fine; only the reporting vanished, which
#    looked exactly like WSLg failing to render.
#
# 每一個 bug 都是同一種形狀：動作看似成功卻什麼都沒做，或工作成功但觀測管道壞掉。
# 它們都曾導致對 GtkBackend / WinUIBackend 的錯誤結論，只能靠實測推翻。列在這裡是
# 因為下一支測試腳本會再遇到同樣的形狀。
# --------------------------------------------------------------------------

set -euo pipefail

script_dir="${0:a:h}"
# Captured at top level on purpose. zsh sets FUNCTION_ARGZERO by default, so
# inside a function $0 is the function's own name -- usage() read "usage"
# instead of this file and failed with "sed: can't read usage".
# 刻意在頂層取得。zsh 預設啟用 FUNCTION_ARGZERO，函式內的 $0 是函式名稱本身，
# 因此 usage() 會去讀 "usage" 而非本檔，報出 "sed: can't read usage"。
script_path="${0:a}"
app="P7"
log_name="p7-debug-events.log"
split_log="splitview-debug.log"
marker="RENDER COMPLETE"
# Long enough for a cold WinUI start. The poll returns as soon as the marker
# lands, so this only costs anything when something is genuinely wrong.
timeout_seconds=30

# Kill anything left over from a previous run, on both platforms, before
# launching. Two P7.exe processes once accumulated unnoticed because taskkill
# had failed silently, and a screenshot then captured the wrong window.
# 啟動前先清掉兩個平台上一次執行的殘留。先前曾因 taskkill 靜默失敗而累積兩個
# P7.exe，截圖也就拍到了錯的視窗。
kill_existing() {
    printf '==> Closing any running %s\n' "$app"

    # Windows: list, kill, then list again. taskkill's own output was being
    # discarded, so a failure looked exactly like a success.
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

    # WSL: find the pids with ps, kill those pids, then check with ps again.
    # Matching on a path never worked -- the app is started as `cd .../output
    # && ./P7`, so its command line is `./P7 --debug` and contains no
    # "output/P7". pkill found nothing, reported success, and left the window
    # open through the next run.
    # WSL：用 ps 找出 pid、對 pid 下 kill，再用 ps 確認。先前以路徑比對從來不會命中：
    # app 以 `cd .../output && ./P7` 啟動，命令列是 `./P7 --debug`，不含 "output/P7"。
    # pkill 找不到東西卻回報成功，視窗就一直留到下一輪。
    # Kept to one shallow line on purpose. An earlier version did the same work
    # with ps, awk and a pid list, and the quoting did not survive the trip
    # through zsh -> wsl.exe -> bash: the count came back empty and the check
    # reported a failure that had not happened.
    # 刻意維持單行淺層引號。先前用 ps + awk + pid 清單的版本，引號在
    # zsh → wsl.exe → bash 這一路上沒能存活，計數變成空字串，於是報出了一個
    # 並未發生的失敗。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "pkill -x $app 2>/dev/null; sleep 1; pgrep -ax $app || printf '    WSLg: clear\n'" \
        2>/dev/null || true
}

target="windows"
do_build=1

usage() {
    # Just the synopsis. The block below it is history for whoever maintains
    # this, not something to print at someone who asked for --help.
    # 只印用法。下方那段是給維護者看的來由，不該對著問 --help 的人傾倒。
    sed -n '2,16p' "$script_path" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w|--wsl) target="wsl"; shift ;;
        -b|--both) target="both"; shift ;;
        -n|--no-build) do_build=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

# The log lines are written as "P7 <date> <message>", while the same text goes
# to stdout as "[P7] <message>". Matching only the bracketed form silently
# dropped every measurement from the summary.
# log 檔的格式是「P7 <日期> <訊息>」，而同樣的內容送到 stdout 時是「[P7] <訊息>」。
# 只比對括號形式會讓摘要靜默漏掉所有量測值。
summary_pattern='(content|sidebar content=|\[SplitView\])'

run_windows() {
    local out="$script_dir/output"

    if [ "$do_build" -eq 1 ]; then
        printf '==> Building P7 for Windows\n'
        zsh "$script_dir/compile.zsh" "$app" | grep -E 'error:|Build of product' || true
    fi

    rm -f "$out/$log_name" "$out/$split_log"

    printf '==> Launching P7.exe\n'
    ( cd "$out" && SCUI_DEBUG_SPLIT=1 "./$app.exe" --debug >/dev/null 2>&1 & )

    # One shot at 1s regardless, so there is always a picture of the early
    # state to compare against -- if the render never completes, this is the
    # only evidence of what the window was doing.
    # 無論如何先在 1 秒拍一張，保留早期狀態以供對照；萬一始終沒完成 render，這張
    # 就是視窗當時狀況的唯一證據。
    zsh "$script_dir/screenshot.zsh" -d 1 -w "P7 lists and split views" p7-windows-1s || true

    local waited=1
    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if [ -f "$out/$log_name" ] && grep -q "$marker" "$out/$log_name" 2>/dev/null; then
            printf ' -- rendered after %ss\n' "$waited"
            break
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done
    [ "$waited" -lt "$timeout_seconds" ] || printf '\n==> Timed out after %ss\n' "$timeout_seconds"

    zsh "$script_dir/screenshot.zsh" -d 0 -w "P7 lists and split views" p7-windows-final || true

    # MSYS2_ARG_CONV_EXCL stops Git Bash's path conversion mangling /F and /IM.
    # Without it taskkill silently failed and P7.exe accumulated across runs --
    # invisible, because the output had been sent to /dev/null.
    # 若不設 MSYS2_ARG_CONV_EXCL，Git Bash 的路徑轉換會把 /F 與 /IM 弄壞，taskkill
    # 靜默失敗、P7.exe 每跑一次就多一個——而輸出被丟進 /dev/null 所以完全看不出來。
    if MSYS2_ARG_CONV_EXCL='*' taskkill.exe /F /IM "$app.exe" 2>&1 | grep -q SUCCESS; then
        printf '==> Closed P7.exe\n'
    else
        printf '==> WARNING: P7.exe may still be running; check with tasklist\n'
    fi

    printf '\n==> Windows geometry\n'
    grep -hE "$summary_pattern" "$out/$log_name" "$out/$split_log" 2>/dev/null \
        | sed 's/^P7 [0-9-]* [0-9:]* +0000 //' | sort -u || true
}

run_wsl() {
    if [ "$do_build" -eq 1 ]; then
        printf '==> Syncing sources to WSL\n'
        zsh "$script_dir/rsync_WSL.zsh" >/dev/null
        printf '==> Building P7 for WSLg\n'
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "cd ~/proj/swift-cross-ui && zsh testapp/compile.zsh $app 2>&1 | grep -E 'error:|Build of product'" || true
    fi

    # Clear the logs in their own call, so a stale file can never be mistaken
    # for this run's output.
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && rm -f $log_name $split_log"

    # Background the wsl.exe process itself rather than putting `&` inside
    # `bash -lc`. Backgrounding within the inner shell lets that shell exit
    # immediately and the app goes with it -- which looked like success while
    # the summary quietly reported the previous run's numbers.
    # 背景化 wsl.exe 這個行程本身，而不是在 `bash -lc` 內部加 `&`。在內層 shell
    # 背景化會讓該 shell 立刻結束、app 一併被收掉——表面上像成功，摘要卻默默印出
    # 上一次執行的數字。
    printf '==> Launching P7 under WSLg\n'
    # Detach the background job from this script's stdout and from job control.
    # While it held the terminal, the progress lines this function prints -- the
    # screenshot paths and "rendered after Ns" -- were swallowed, and zsh
    # reported "Terminated" in their place. The run itself was fine; only the
    # reporting was lost, which is the worst way for it to fail.
    # 讓背景工作脫離本腳本的 stdout 與 job control。它佔住終端時，本函式印出的進度
    # （截圖路徑與「rendered after Ns」）會被吞掉，取而代之的是 zsh 的 "Terminated"。
    # 執行本身沒問題，只有回報消失了——那是最糟的失敗方式。
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && SCUI_DEBUG_SPLIT=1 ./$app --debug >/dev/null 2>&1" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    zsh "$script_dir/screenshot.zsh" -d 1 -w "P7 lists and split views" p7-wslg-1s || true

    local waited=1
    printf '==> Waiting for "%s"' "$marker"
    while [ "$waited" -lt "$timeout_seconds" ]; do
        if MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
            "grep -q '$marker' ~/proj/swift-cross-ui/testapp/output/$log_name 2>/dev/null"; then
            printf ' -- rendered after %ss\n' "$waited"
            break
        fi
        sleep 1
        waited=$((waited + 1))
        printf '.'
    done

    zsh "$script_dir/screenshot.zsh" -d 0 -w "P7 lists and split views" p7-wslg-final || true

    if [ "$waited" -ge "$timeout_seconds" ]; then
        printf '\n==> FAILED: P7 never reported a completed render under WSLg.\n'
        printf '==> The two screenshots are still there to compare, but the\n'
        printf '==> geometry below is withheld: any log present would be stale.\n'
        MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
        return 1
    fi

    # WSLg composites onto the Windows desktop, so the same gdigrab capture
    # works and the two platforms stay directly comparable.
    # WSLg 會合成到 Windows 桌面，因此同一套 gdigrab 擷取也適用，兩平台可直接比對。
    zsh "$script_dir/screenshot.zsh" -d 1 -w "P7 lists and split views" p7-wslg || true

    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc "pkill -x '$app' 2>/dev/null" || true
    printf '==> Closed P7 under WSLg\n\n==> WSLg geometry\n'
    MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Ubuntu -- zsh -lc \
        "cd ~/proj/swift-cross-ui/testapp/output && grep -hE '$summary_pattern' $log_name $split_log 2>/dev/null | sed 's/^P7 [0-9-]* [0-9:]* +0000 //' | sort -u" || true
}

# Clear both platforms before anything else, including before the build:
# leaving a window from the previous run open while a rebuild runs means the
# screenshot can catch the stale one.
# 在任何動作之前先清乾淨兩個平台——包含建置之前。若舊視窗在重建期間仍開著，
# 截圖就可能拍到上一次的視窗。
kill_existing

case "$target" in
    windows) run_windows ;;
    wsl) run_wsl ;;
    both) run_windows; printf '\n'; run_wsl ;;
esac
