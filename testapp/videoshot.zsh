#!/usr/bin/env zsh
# Records the composited desktop to testapp/output/videoshots/videoshot.webm.
#
# This intentionally mirrors screenshot.sh and uses ffmpeg's gdigrab. Capturing
# the composited desktop is the reliable path for WinUI/D3D/DirectComposition
# debugging; window-only capture can come back black.

set -euo pipefail

script_dir="${0:a:h}"
output_dir="$script_dir/output/videoshots"
target="$output_dir/videoshot.webm"

usage() {
    printf '%s\n' \
        "Usage: videoshot.zsh [-duration <seconds>] [-d <seconds>] [-w <window title>] [-replay]" \
        "用法：videoshot.zsh [-duration <秒數>] [-d <秒數>] [-w <視窗標題>] [-replay]" \
        "" \
        "  -duration  Record this many seconds of video (default 30)." \
        "  -duration  錄製秒數（預設 30）。" \
        "  -d         Wait this many seconds before recording (default 0)." \
        "  -d         錄製前先等待的秒數（預設 0）。" \
        "  -w         Raise this window to the front just before recording." \
        "  -w         錄製前先把這個視窗帶到最前面。" \
        "  -replay    Replay the latest videoshot.webm and exit." \
        "  -replay    播放最新的 videoshot.webm 後結束。" \
        "" \
        "Example 範例:" \
        "  zsh testapp/videoshot.zsh -duration 30 -w 'P6 stream player'" \
        "  zsh testapp/videoshot.zsh -replay"
}

duration=30
delay=0
window=""
replay=0
fps=30

while [ "$#" -gt 0 ]; do
    case "$1" in
        -duration)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            duration="$2"
            shift 2
            ;;
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
        -replay)
            replay=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

mkdir -p "$output_dir"

if [ "$replay" -eq 1 ]; then
    if [ ! -f "$target" ]; then
        printf 'No videoshot found: %s\n' "$target" >&2
        exit 66
    fi
    if ! command -v ffplay >/dev/null 2>&1; then
        printf 'ffplay is required for -replay but was not found on PATH.\n' >&2
        exit 69
    fi
    ffplay -hide_banner -autoexit "$target"
    exit 0
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    printf 'ffmpeg is required but was not found on PATH.\n' >&2
    exit 69
fi

grab() {
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate "$fps" -i desktop "$@"
}

# Discarded frames are the wait: one per second, decoded and thrown away.
if [ "$delay" -gt 0 ]; then
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 -i desktop \
        -frames:v "$delay" -f null - </dev/null
fi

# Windows has no built-in command that activates a window, so drive WSH's
# AppActivate, matching screenshot.sh.
if [ -n "$window" ]; then
    activate_script="$(mktemp -t activate-XXXXXX).vbs"
    printf 'CreateObject("WScript.Shell").AppActivate "%s"\n' "$window" \
        > "$activate_script"
    cscript.exe //nologo "$(cygpath -w "$activate_script")" > /dev/null || true
    rm -f "$activate_script"
    ffmpeg -hide_banner -loglevel error -f gdigrab -framerate 1 -i desktop \
        -frames:v 1 -f null - </dev/null
fi

tmp_target="$output_dir/videoshot.tmp.webm"
rm -f "$tmp_target"

grab -t "$duration" \
    -an \
    -c:v libvpx-vp9 \
    -deadline realtime \
    -cpu-used 6 \
    -b:v 2M \
    -pix_fmt yuv420p \
    -y "$tmp_target" </dev/null

mv -f "$tmp_target" "$target"
printf '%s\n' "$target"
