#!/bin/zsh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
p6_executable="$script_dir/output/P6"
command_name=$(basename -- "$0")

# Show the complete command shape before requiring a media path.
# 在要求媒體路徑前，先顯示完整的命令格式。
usage() {
    printf '%s\n' \
        "Usage: $command_name [-rss] [-metal|-core] [--debug] [--frame-drop] <media-file>" \
        "用法：$command_name [-rss] [-metal|-core] [--debug] [--frame-drop] <媒體檔案>" \
        "Example: $command_name -rss --debug --frame-drop '/path/to/video.webm'" \
        "Build first if needed: zsh testapp/compile.sh P6"
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 64
fi

if [ ! -x "$p6_executable" ]; then
    printf '%s\n' \
        "P6 executable not found: $p6_executable" \
        "找不到 P6 執行檔：$p6_executable" \
        "Build it with: zsh testapp/compile.sh P6" >&2
    exit 1
fi

rss_enabled=0
typeset -a p6_arguments
p6_arguments=()
for argument in "$@"; do
    if [ "$argument" = "-rss" ]; then
        rss_enabled=1
    else
        p6_arguments+=("$argument")
    fi
done

if [ "${#p6_arguments[@]}" -eq 0 ]; then
    usage >&2
    exit 64
fi

if [ "$rss_enabled" -eq 0 ]; then
    "$p6_executable" "${p6_arguments[@]}"
    exit $?
fi

rss_log_file="$PWD/p6-debug-events-rss.log"
rss_peak_kb=0
rss_sample_count=0

# Start each RSS run with a fresh file instead of mixing samples from old runs.
# 每次 RSS 測試都從全新檔案開始，避免混入先前執行的取樣資料。
: > "$rss_log_file"

# Use a dedicated RSS log file and keep RSS diagnostics out of the terminal.
# 使用固定的 RSS log 檔案，且不在終端機輸出 RSS 診斷。
rss_log() {
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S +0000')
    printf 'P6 RSS %s %s\n' "$timestamp" "$1" >> "$rss_log_file"
}

"$p6_executable" "${p6_arguments[@]}" &
p6_pid=$!

# RSS mode backgrounds P6 for sampling, so explicitly forward terminal signals.
# RSS 模式會將 P6 放到背景以便取樣，因此需明確轉送終端機訊號。
forward_signal() {
    signal_name=$1
    if kill -0 "$p6_pid" 2>/dev/null; then
        kill -s "$signal_name" "$p6_pid" 2>/dev/null || true
    fi
}

trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

rss_log "start pid $p6_pid interval_seconds 1"
while kill -0 "$p6_pid" 2>/dev/null; do
    rss_kb=$(ps -o rss= -p "$p6_pid" 2>/dev/null | tr -d '[:space:]')
    if [[ "$rss_kb" == <-> ]]; then
        rss_sample_count=$((rss_sample_count + 1))
        if [ "$rss_kb" -gt "$rss_peak_kb" ]; then
            rss_peak_kb=$rss_kb
        fi
        rss_log "sample pid $p6_pid rss_kb $rss_kb peak_rss_kb $rss_peak_kb"
    fi
    sleep 1 || true
done

if wait "$p6_pid"; then
    p6_status=0
else
    p6_status=$?
fi
rss_log "finish pid $p6_pid samples $rss_sample_count peak_rss_kb $rss_peak_kb exit_status $p6_status"
exit "$p6_status"
