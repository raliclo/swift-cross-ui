#!/usr/bin/env zsh
# Drive and photograph the action files of some apps on Windows (WinUI) or on
# native Linux (GtkBackend under X11), one file at a time, for CI.
#
#   zsh testapp/sweep_desktop.zsh --windows P2 P8      actions/win/, WinUI builds
#   zsh testapp/sweep_desktop.zsh --linux P2 P8        actions/wsl/, GTK builds, $DISPLAY
#   zsh testapp/sweep_desktop.zsh --help
#
# Writes output/<windows|linux>-sweep.csv2 with the columns sweep_apple.zsh
# uses, one row per ACTION FILE. A row is `pass` when the app logged
# `-actionfile: replayed <file>`, a capture was written during the run, the
# file's `# expect: log-contains` line (if any) was met, and the run exited 0.
# Like sweep_apple.zsh it does not prove each click did what the file's header
# says; the capture is uploaded for that.
#
# Why two platforms in one script: test.zsh drives Linux only through wsl.exe
# from Windows, so on a Linux runner there is nothing to call. The replay is
# done by the app itself (XdotoolSynthesiser, Win32Synthesiser) once it is
# launched with `-actionfile <path>`, so --linux launches it directly with the
# environment test.zsh's WSL branch uses (GDK_BACKEND=x11, GTK_CSD=1) and
# photographs the root window with ImageMagick's `import`. --windows hands
# each file to test.zsh, which already does the Windows run end to end.
#
# The builds must be SCUI_DEBUG=1 (compile.zsh), or `-actionfile` is not
# compiled in and every row fails on `replay`.
#
# 為 CI 在 Windows(WinUI)或原生 Linux(X11 下的 GtkBackend)上，一次一份地驅動並拍攝部分 app 的動作檔。寫出
# output/<windows|linux>-sweep.csv2,欄位與 sweep_apple.zsh 相同，每份**動作檔**一列。app 記下
# `-actionfile: replayed <檔名>`、本次執行期間寫出擷圖、檔案的 `# expect: log-contains`(若有)達成、執行以 0 結束，
# 該列才是 `pass`。與 sweep_apple.zsh 一樣，它不證明每次點擊都達成檔頭所說的事；擷圖會上傳供檢視。為什麼一支腳本
# 兩個平台:test.zsh 只能從 Windows 經 wsl.exe 驅動 Linux,在 Linux runner 上沒有東西可呼叫。重放由 app 自己完成
# (XdotoolSynthesiser、Win32Synthesiser),只要以 `-actionfile <路徑>` 啟動它，所以 --linux 直接以 test.zsh WSL
# 分支用的環境(GDK_BACKEND=x11、GTK_CSD=1)啟動，再用 ImageMagick 的 `import` 拍 root 視窗。--windows 把每份檔案
# 交給 test.zsh,它本來就完整處理 Windows 的執行。建置必須是 SCUI_DEBUG=1(compile.zsh),否則 `-actionfile` 沒有編入，
# 每一列都會在 `replay` 失敗。

set -uo pipefail
script_path="${0:A}"
script_dir="${script_path:h}"

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ] || [ $# -eq 0 ]; then
    sed -n '2,25p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

platform=""
case "$1" in
    --windows) platform=windows; action_dir="$script_dir/actions/win" ;;
    --linux) platform=linux; action_dir="$script_dir/actions/wsl" ;;
    *) printf 'first argument must be --windows or --linux (got %s)\n' "$1" >&2; exit 64 ;;
esac
shift
apps=("$@")
timeout_s="${SWEEP_TIMEOUT:-300}"

output_dir="$script_dir/output"
shots_dir="$output_dir/screenshots"
run_dir="$output_dir/sweep-$platform"
out_csv="$output_dir/$platform-sweep.csv2"
mkdir -p "$run_dir" "$shots_dir"

# The longest prefix that names an app (see sweep_apple.zsh: P15-DARK is an app).
# 能對應到某支 app 的最長前綴(見 sweep_apple.zsh:P15-DARK 是一支 app)。
app_of() {
    local stem="${1%.actions}" candidate="" best=""
    local -a parts=("${(@s:-:)stem}")
    local i
    for i in {1..${#parts}}; do
        candidate="${(j:-:)parts[1,$i]}"
        [ -f "$script_dir/$candidate.swift" ] && best="$candidate"
    done
    printf '%s\n' "$best"
}

files=()
for f in "$action_dir"/P*.actions(N); do
    app="$(app_of "${f:t}")"
    [ -n "$app" ] || continue
    if [ "${#apps[@]}" -gt 0 ] && (( ! ${apps[(Ie)$app]} )); then
        continue
    fi
    # actions/win holds GtkBackend twins as `-gtk4` files; this sweep is WinUI.
    # actions/win 以 `-gtk4` 檔存放 GtkBackend 版本；本 sweep 跑 WinUI。
    if [ "$platform" = windows ] && [[ "${f:t}" == *-gtk4.actions ]]; then
        continue
    fi
    files+=("$f")
done
if [ "${#files[@]}" -eq 0 ]; then
    printf 'no action files matched under %s\n' "$action_dir" >&2
    exit 1
fi
printf '==> %s sweep: %s action files\n' "$platform" "${#files[@]}"

source "$script_dir/test_support/csv2_rows.zsh"
today="$(date +%Y-%m-%d)"
backend=WinUI
[ "$platform" = linux ] && backend=gtk4
device="$(uname -sm)"
csv2_new "$out_csv" \
    "date,platform,backend,app,action_file,result,exit,replay,capture,seconds,screenshot,device,note" \
    "日期,平台,backend,app,動作檔,結果,結束碼,重放,擷取,秒數,擷圖,裝置,備註"

# The `# expect: log-contains <text>` line of a file, or nothing.
# 檔案的 `# expect: log-contains <文字>` 行，沒有則為空。
expectation_of() {
    local line
    line="$(grep -m1 -E '^# *expect: *log-contains .' "$1" 2>/dev/null || true)"
    line="${line#*log-contains }"
    printf '%s' "${line%$'\r'}"
}

# One Linux run: launch, wait for the app's replay line, hold, photograph, close.
# Sets rc, replay_log and shot.
# 一次 Linux 執行：啟動、等 app 的重放行、停留、拍照、關閉。設定 rc、replay_log 與 shot。
run_linux() {
    local f="$1" app="$2" stem="$3" launch_args="$4"
    local exe="$output_dir/$app" events="$run_dir/events-$stem"
    replay_log="$run_dir/$stem-app.log"
    rm -rf "$events"
    mkdir -p "$events"
    if [ ! -x "$exe" ]; then
        printf 'no executable %s\n' "$exe" > "$replay_log"
        rc=127
        return
    fi
    # `${=launch_args}` splits the file's `# launch-args:` into words.
    # `${=launch_args}` 把檔案的 `# launch-args:` 拆成多個詞。
    env SCUI_DEBUG_EVENTS_DIR="$events" GDK_BACKEND=x11 GTK_CSD=1 \
        SCUI_GTK_APP_ID="dev.scui.sweep.${stem//[^A-Za-z0-9]/_}" \
        "$exe" --debug ${=launch_args} -actionfile "$f" > "$replay_log" 2>&1 &
    local pid=$! started=$(date +%s)
    rc=0
    while ! grep -aqE -- '-actionfile: (replayed|failed)' "$replay_log" 2>/dev/null; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            rc=$?
            [ "$rc" -eq 0 ] && rc=70
            break
        fi
        if (( $(date +%s) - started > timeout_s )); then
            rc=124
            break
        fi
        sleep 1
    done
    sleep 2
    # The app's own X windows, each photographed, the largest file kept: GTK
    # also maps a 1x1 leader window, which `import` cannot read. Not the root
    # window first: WSLg's X server is rootless and `import -window root`
    # fails there ("missing an image filename"), so the root is the fallback
    # (Xvfb has one).
    # app 自己的 X 視窗逐一拍攝，保留最大的檔案:GTK 另有一個 1x1 的 leader 視窗,`import` 讀不了。不先拍 root:WSLg 的 X
    # 伺服器沒有 root,`import -window root` 在那裡失敗(「missing an image filename」),所以 root 是退路(Xvfb 有)。
    shot="$shots_dir/${app:l}-linux-final-$stem-$(date +%Y%m%d-%H%M%S).png"
    # A window that cannot be read gets its xwininfo written to the log, and a
    # viewable one off the screen is named in the row's note. That is how a
    # WSLg-only failure was found (2026-11-15): one P2 launch in several opened
    # at (-32736, -32736) and stayed there, though the placement helper had
    # moved it to (32, 32) in a work area read as 0,0 1920x1080 (measured with
    # a probe in scui_window_place_in_work_area). -32736 is -32768 + 32, so the
    # window manager had put the window's frame at -32768. xdotool's clicks
    # then miss the window and the replay still reports `replayed`, so no
    # retry: the row fails and says why. Xvfb on CI has no window manager.
    # 讀不了的視窗會把 xwininfo 寫進 log,在螢幕外但可見的視窗會寫進該列的備註。WSLg 專有的失敗就是這樣找到的(2026-11-15):
    # 幾次啟動中有一次 P2 開在 (-32736, -32736) 並停在那裡，而放置輔助函式已把它移到 (32, 32),讀到的工作區是 0,0 1920x1080
    # (以 scui_window_place_in_work_area 中的探針量得)。-32736 是 -32768 + 32,也就是視窗管理員把視窗外框放在 -32768。這時
    # xdotool 的點擊點不到視窗，重放卻照樣回報 `replayed`,所以不重試：該列失敗並說明原因。CI 上的 Xvfb 沒有視窗管理員。
    local id candidate best=0 size info
    offscreen=""
    for id in $(xdotool search --pid "$pid" 2>/dev/null); do
        candidate="$run_dir/.window-$id.png"
        if ! import -window "$id" "$candidate" 2>>"$replay_log"; then
            info="$(xwininfo -id "$id" 2>&1 | grep -E 'Absolute|Width|Height|Map State' | tr -s ' ' | tr '\n' ';')"
            printf 'unreadable window %s:%s\n' "$id" "$info" >> "$replay_log"
            if [[ "$info" == *IsViewable* && "$info" == *"upper-left X: -"* ]]; then
                offscreen="window off screen:${info%%; Width*}"
            fi
            continue
        fi
        size=$(wc -c < "$candidate")
        if [ "$size" -gt "$best" ]; then
            best=$size
            mv -f "$candidate" "$shot"
        else
            rm -f "$candidate"
        fi
    done
    # Keep a desktop capture for diagnostics, never as proof of an app capture.
    # 桌面截圖只供診斷，不算作應用程式截圖。
    if [ "$best" -eq 0 ]; then
        shot=""
        if [ -z "$offscreen" ]; then
            local diagnostic="$run_dir/$stem-desktop.png"
            if import -window root "$diagnostic" 2>>"$replay_log"; then
                printf 'No app window captured; desktop diagnostic: %s\n' "$diagnostic" >> "$replay_log"
            fi
        fi
    fi
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    local -a event_logs=("$events"/*.log(N))
    if (( ${#event_logs} )); then
        cat "${event_logs[@]}" >> "$replay_log"
    fi
}

for f in "${files[@]}"; do
    name="${f:t}"
    app="$(app_of "$name")"
    stem="${name%.actions}"
    log="$run_dir/$stem.log"
    marker="$run_dir/.started-$stem"
    touch "$marker"
    started=$(date +%s)
    launch_args="$(grep -m1 -E '^# *launch-args:' "$f" | sed -E 's/^# *launch-args: *//')"
    shot=""
    replay_log=""
    offscreen=""
    rc=0

    if [ "$platform" = windows ]; then
        # TEST_BACKEND=WinUI: with a -gtk4 build beside the WinUI one, test.zsh
        # refuses to guess (six of eight files failed that way locally,
        # 2026-11-15). -n: the builds are the SCUI_DEBUG=1 ones made beforehand.
        # TEST_BACKEND=WinUI:旁邊有 -gtk4 建置時 test.zsh 拒絕猜測(本機 8 份中有 6 份因此失敗,2026-11-15)。-n:用事先建好的
        # SCUI_DEBUG=1 建置。
        TEST_BACKEND=WinUI TEST_APP_ARGS="--debug${launch_args:+ $launch_args}" \
            timeout "$timeout_s" zsh "$script_dir/test.zsh" "$app" -win -n --showtime 2 --actionfile "$f" > "$log" 2>&1
        rc=$?
        replay_log="$log"
        [ -f "$output_dir/${app:l}-actionfile.log" ] && cp "$output_dir/${app:l}-actionfile.log" "$run_dir/$stem-actionfile.log" \
            && replay_log="$run_dir/$stem-actionfile.log"
        for s in "$shots_dir"/${app:l}-windows-final-*.png(N.om); do
            [ "$s" -nt "$marker" ] && shot="$s"
            break
        done
    else
        run_linux "$f" "$app" "$stem" "$launch_args" > "$log" 2>&1
    fi
    elapsed=$(( $(date +%s) - started ))

    replay=fail
    note=""
    if [ -f "$replay_log" ] && grep -aq -- "-actionfile: replayed $name" "$replay_log"; then
        replay=ok
    elif [ -f "$replay_log" ]; then
        note="$(grep -a -m1 -- "-actionfile: failed" "$replay_log" | cut -c1-160)"
    fi
    capture=fail
    [ -n "$shot" ] && [ -s "$shot" ] && capture=ok
    [ -n "$offscreen" ] && note="$offscreen${note:+; $note}"

    # test.zsh checks the expectation itself on Windows (exit 8); on Linux it is checked here.
    # Windows 上 test.zsh 自己檢查(結束碼 8);Linux 在這裡檢查。
    expected="$(expectation_of "$f")"
    if [ "$platform" = linux ] && [ -n "$expected" ] && [ "$rc" -eq 0 ]; then
        if ! grep -aqF -- "$expected" "$replay_log"; then
            rc=8
            note="expect UNMET: $expected${note:+; $note}"
        fi
    fi

    result=fail
    [ "$rc" -eq 0 ] && [ "$replay" = ok ] && [ "$capture" = ok ] && result=pass
    [ "$rc" -eq 124 ] && result=timeout
    csv2_append "$out_csv" "$today" "$platform" "$backend" "$app" "$name" "$result" "$rc" "$replay" "$capture" \
        "$elapsed" "${shot:t}" "$device" "$note"
    printf '    %-6s %-44s %-7s rc=%-3s replay=%-4s capture=%-4s %4ss\n' \
        "$app" "$name" "$result" "$rc" "$replay" "$capture" "$elapsed"
    rm -f "$marker"
done

total=$(csv2 -r --json -i "$out_csv" | grep -c '"record":' || true)
passed=$(csv2 -r --json -i "$out_csv" | grep -c '"result":"pass"' || true)
printf '==> %s: %s of %s action files pass; written to %s\n' "$platform" "$passed" "$total" "$out_csv"
