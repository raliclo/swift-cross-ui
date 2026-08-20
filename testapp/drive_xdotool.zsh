#!/usr/bin/env zsh
# Drives a test app under WSLg with xdotool and captures what happened.
#
#   zsh testapp/drive_xdotool.zsh P19
#   zsh testapp/drive_xdotool.zsh P19 --keep     # leave the app running
#   zsh testapp/drive_xdotool.zsh P19 --click 80,120 --click 80,180
#   zsh testapp/drive_xdotool.zsh P21 --key Tab --key space --pause 2
#   zsh testapp/drive_xdotool.zsh --help
#
# --click X,Y  window-relative click, then capture
# --key KEYS   xdotool key syntax, then capture
# --pause SECS wait, then capture
# Steps run in the order given, each leaving its own numbered screenshot.
# --click X,Y  以視窗相對座標點擊，然後擷取
# --key KEYS   xdotool 的按鍵語法，然後擷取
# --pause SECS 等待，然後擷取
# 各步驟依給定順序執行，每一步各自留下一張編號的截圖。
#
# 於 WSLg 下以 xdotool 驅動測試 app，並擷取其結果。
#
# XWayland only, and that is a real limitation rather than a detail. Wayland does
# not let one process drive another client, so xdotool sees no windows at all in
# a default WSLg session; the app has to be launched with GDK_BACKEND=x11. The
# two are separate code paths in GTK, so a result here is evidence about
# XWayland and not about the Wayland path the user actually runs. The GTK file
# chooser bug was reproducible on Wayland and not under XWayland, which is
# exactly this distinction biting.
# 僅適用於 XWayland，而這是真實的限制而非細節。Wayland 不允許一個行程驅動另一個 client，
# 因此在預設的 WSLg 工作階段中 xdotool 看不到任何視窗；app 必須以 GDK_BACKEND=x11 啟動。
# 兩者在 GTK 中是不同的程式路徑，因此此處的結果是關於 XWayland 的證據，而非使用者實際
# 執行的 Wayland 路徑。GTK 檔案選擇器的缺陷可在 Wayland 重現、在 XWayland 卻不能，正是
# 這個區別造成的。
#
# Clicks use `xdotool mousemove --window`, never absolute screen coordinates.
# Absolute positions are thrown off by window decorations: measured, absolute
# clicks computed from the window geometry did nothing at all, and the same
# click landed correctly once made window-relative.
# 點擊一律使用 `xdotool mousemove --window`，絕不使用螢幕絕對座標。絕對位置會受視窗裝飾
# 影響：實測中，依視窗幾何計算出的絕對座標點擊完全沒有反應，改為視窗相對座標後同一個
# 點擊立即成功。

set -euo pipefail

script_path="${0:a}"
script_dir="${script_path:h}"
keep=0
app=""

usage() {
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
}

# Steps to perform after the initial capture, in order. Each one acts and then
# captures, so a run leaves a numbered trail rather than a single before-and-
# after; when a control does nothing, the shot that matters is the one taken
# immediately after the click that should have worked.
# 於初始擷取之後依序執行的步驟。每個步驟先動作、再擷取，因此一次執行會留下編號連續的軌跡，
# 而非僅有前後兩張；當某個控制項毫無反應時，真正有用的是「本應生效的那次點擊」之後緊接的
# 那一張截圖。
typeset -a steps=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --keep) keep=1; shift ;;
        --click)
            if [ "$#" -lt 2 ]; then usage >&2; exit 64; fi
            steps+=("click:$2"); shift 2 ;;
        --key)
            if [ "$#" -lt 2 ]; then usage >&2; exit 64; fi
            steps+=("key:$2"); shift 2 ;;
        --pause)
            if [ "$#" -lt 2 ]; then usage >&2; exit 64; fi
            steps+=("pause:$2"); shift 2 ;;
        *) app="$1"; shift ;;
    esac
done

if [ -z "$app" ]; then
    printf 'Which app? e.g. P19\n' >&2
    usage >&2
    exit 64
fi

for tool in xdotool xwd xwdtopnm pnmtopng; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing %s. Run: zsh testapp/install_tool_wsl.sh\n' "$tool" >&2
        exit 1
    fi
done

out_dir="$script_dir/output"
exe="$out_dir/$app"
if [ ! -x "$exe" ]; then
    printf 'No %s. Build it: zsh testapp/compile.zsh %s\n' "$exe" "$app" >&2
    exit 1
fi

shots_dir="$out_dir/screenshots"
mkdir -p "$shots_dir"

export GDK_BACKEND=x11

printf '==> Closing any running %s\n' "$app"
pkill -x "$app" 2>/dev/null || true
sleep 1

printf '==> Launching %s under XWayland\n' "$app"
# Launched from the output directory because the apps write their log to the
# process's working directory. Started elsewhere, the log lands next to wherever
# the driver happened to be invoked from and this script reports "no log" for an
# app that was logging perfectly well.
# 由 output 目錄啟動，因為這些 app 會把日誌寫入行程的工作目錄。若從別處啟動，日誌會落在
# 驅動器當時被呼叫的位置，而本腳本會對一個其實正常記錄的 app 回報「沒有日誌」。
: > "$out_dir/${app:l}-debug-events.log" 2>/dev/null || true
( cd "$out_dir" && "$exe" --debug >"/tmp/$app-stdout.log" 2>&1 ) &
app_pid=$!

# Waiting for the window rather than sleeping a fixed time: startup varies with
# how much the compositor has to do, and a fixed sleep is either too short on a
# slow run or wasted on a fast one.
# 等待視窗出現而非固定 sleep：啟動時間隨 compositor 的負載變動，固定 sleep 不是在慢的
# 情況下太短，就是在快的情況下白等。
# The first match is not good enough. A GTK app owns more than one X window and
# `xdotool search --name P19` returned a 1x1 one, which xwd then captured as a
# single pixel. Take the largest visible match instead: the app's real window is
# the biggest thing carrying its name.
# 取第一個匹配並不足夠。GTK app 擁有不只一個 X window，而 `xdotool search --name P19`
# 回傳了一個 1x1 的視窗，xwd 因而只擷取到一個像素。改為取「可見且最大」的匹配：帶有該
# 名稱的最大視窗才是 app 的真正視窗。
wid=""
for _ in $(seq 1 30); do
    best_area=0
    while read -r candidate; do
        [ -n "$candidate" ] || continue
        geometry="$(xdotool getwindowgeometry --shell "$candidate" 2>/dev/null || true)"
        [ -n "$geometry" ] || continue
        candidate_w="$(printf '%s\n' "$geometry" | sed -n 's/^WIDTH=//p')"
        candidate_h="$(printf '%s\n' "$geometry" | sed -n 's/^HEIGHT=//p')"
        [ -n "$candidate_w" ] && [ -n "$candidate_h" ] || continue
        area=$(( candidate_w * candidate_h ))
        if [ "$area" -gt "$best_area" ]; then
            best_area="$area"
            wid="$candidate"
        fi
    done < <(xdotool search --onlyvisible --name "$app" 2>/dev/null || true)

    # A real window, not a 1x1 helper.
    # 必須是真正的視窗，而非 1x1 的輔助視窗。
    [ "$best_area" -gt 10000 ] && break
    wid=""
    sleep 1
done

if [ -z "$wid" ]; then
    printf '!! %s never opened a window under XWayland.\n' "$app" >&2
    printf '!! stdout/stderr:\n' >&2
    grep -viE 'libEGL|MESA|dri2|zink' "/tmp/$app-stdout.log" 2>/dev/null | head -8 >&2
    kill "$app_pid" 2>/dev/null || true
    exit 1
fi

eval "$(xdotool getwindowgeometry --shell "$wid")"
printf '    window %s: %sx%s\n' "$wid" "$WIDTH" "$HEIGHT"

capture() {
    local label="$1"
    local target="$shots_dir/${app:l}-$label-$(date +%Y%m%d-%H%M%S).png"
    xwd -id "$wid" -out "/tmp/$app.xwd" 2>/dev/null
    xwdtopnm "/tmp/$app.xwd" 2>/dev/null | pnmtopng > "$target" 2>/dev/null
    printf '    %s\n' "$target"
}

printf '==> Capturing initial state\n'
xdotool windowactivate "$wid" 2>/dev/null || true
sleep 1
capture "initial"

# Each step acts, waits a beat for the UI to settle, then captures.
#
# Clicks are window-relative, as the header explains: absolute coordinates
# computed from the window geometry landed nowhere, because they do not account
# for decorations. `mousemove --window` does.
#
# 每個步驟先動作，稍候讓 UI 穩定，然後擷取。
#
# 點擊採視窗相對座標，理由如檔頭所述：依視窗幾何計算出的絕對座標會落在錯誤位置，因為它未計入
# 視窗裝飾；`mousemove --window` 則會。
step_number=0
for step in $steps; do
    step_number=$((step_number + 1))
    action="${step%%:*}"
    value="${step#*:}"

    case "$action" in
        click)
            x="${value%%,*}"
            y="${value##*,}"
            printf '\n==> Step %s: click at %s,%s\n' "$step_number" "$x" "$y"
            xdotool mousemove --window "$wid" "$x" "$y" click 1 2>/dev/null || true
            ;;
        key)
            printf '\n==> Step %s: key %s\n' "$step_number" "$value"
            xdotool windowfocus "$wid" 2>/dev/null || true
            xdotool key --window "$wid" "$value" 2>/dev/null || true
            ;;
        pause)
            printf '\n==> Step %s: pause %ss\n' "$step_number" "$value"
            sleep "$value"
            ;;
    esac

    sleep 1
    capture "step$step_number-$action"
done

printf '\n==> Window list\n'
xdotool search --onlyvisible --name ".+" 2>/dev/null | while read -r id; do
    name="$(xdotool getwindowname "$id" 2>/dev/null || true)"
    [ -n "$name" ] && printf '    %s  %s\n' "$id" "$name"
done

printf '\n==> Diagnostics\n'
if [ -s "$out_dir/${app:l}-debug-events.log" ]; then
    tail -12 "$out_dir/${app:l}-debug-events.log" | cut -c1-110 | sed 's/^/    /'
else
    printf '    (no log; the app may not support --debug)\n'
fi

if [ "$keep" -eq 1 ]; then
    printf '\n==> Left running (pid %s, window %s)\n' "$app_pid" "$wid"
else
    pkill -x "$app" 2>/dev/null || true
    printf '\n==> Closed %s\n' "$app"
fi
