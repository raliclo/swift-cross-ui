#!/usr/bin/env zsh
# Captures the desktop to testapp/output/screenshots/<label>-<timestamp>.png.
#
# Uses ffmpeg's gdigrab, which reads the already-composited screen. Capturing a
# single window instead goes through BitBlt, which comes back black for
# D3D/DirectComposition content -- exactly the content this is used to check.
# 使用 ffmpeg 的 gdigrab 擷取「已合成」的螢幕畫面。若改為擷取單一視窗會走
# BitBlt，對 D3D/DirectComposition 內容只會得到全黑，而那正是本工具要檢查的
# 內容。
#
# The wait before capturing is done by grabbing one frame per second and
# overwriting the same file, so no sleep is needed and the file always holds
# the most recent frame.
# 等待是靠每秒抓一張並覆寫同一個檔案達成，因此不需要 sleep，檔案內容永遠是最新
# 的一張。

set -euo pipefail

script_dir="${0:a:h}"
output_dir="$script_dir/output/screenshots"

usage() {
    printf '%s\n' \
        "Usage: screenshot.sh [-d <seconds>] [-w <window title>] [<label>]" \
        "用法：screenshot.sh [-d <秒數>] [-w <視窗標題>] [<標籤>]" \
        "" \
        "  -d  Wait this many seconds before capturing (default 0)." \
        "  -d  擷取前先等待的秒數（預設 0）。" \
        "  -w  Raise this window to the front just before capturing." \
        "  -w  擷取前先把這個視窗帶到最前面。" \
        "" \
        "Example 範例:" \
        "  zsh testapp/screenshot.sh -d 15 -w 'P6 stream player' p6-960x540"
}

delay=0
label="screen"
window=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -d)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            delay="$2"
            shift 2
            ;;
        -w)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            window="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            label="$1"
            shift
            ;;
    esac
done

mkdir -p "$output_dir"

grab() {
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 -i desktop "$@"
}

# Discarded frames are the wait: one per second, decoded and thrown away.
# 丟棄的影格就是等待：每秒一張，解碼後直接丟掉。
if [ "$delay" -gt 0 ]; then
    grab -frames:v "$delay" -f null - </dev/null
fi

# Windows has no built-in command that activates a window, so drive WSH's
# AppActivate, which does. cscript is a stock Windows tool, called the same way
# this repo calls other native tools from the shell.
# Windows 沒有內建可啟動視窗的命令，因此改用 WSH 的 AppActivate；cscript 是系統
# 內建工具，呼叫方式與本專案從 shell 呼叫其他原生工具一致。
if [ -n "$window" ]; then
    activate_script="$(mktemp -t activate-XXXXXX).vbs"
    printf 'CreateObject("WScript.Shell").AppActivate "%s"\n' "$window" \
        > "$activate_script"
    cscript.exe //nologo "$(cygpath -w "$activate_script")" > /dev/null || true
    rm -f "$activate_script"
    # One discarded frame gives the window a second to come forward.
    # 丟棄一張影格，讓視窗有一秒的時間浮到最前面。
    grab -frames:v 1 -f null - </dev/null
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
target="$output_dir/$label-$timestamp.png"

grab -frames:v 1 -y "$target" </dev/null

printf '%s\n' "$target"
