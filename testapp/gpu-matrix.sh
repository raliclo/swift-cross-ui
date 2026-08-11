#!/usr/bin/env zsh
# Runs P6 once per GPU mode at a fixed resolution and frame rate, reports dropped
# frames/sec and the per-stage timings from each run's log.
#
# Each mode gets its own log file, because P6 always writes p6-debug-events.log
# into the working directory.
# 每個模式使用各自的 log 檔，因為 P6 一律把 p6-debug-events.log 寫入工作目錄。

set -euo pipefail

script_dir="${0:a:h}"
output_dir="$script_dir/output"
findings_dir="$script_dir/P6_findings"
csv="$findings_dir/gpu-modes.csv"
resolution="${1:-1080p}"
target_fps="${2:-30}"
seconds="${3:-25}"

mkdir -p "$findings_dir"
if [ ! -f "$csv" ]; then
    printf 'date_tested,mode,resolution,target_fps,measured_fps,frames_dropped_per_sec,read_avg_ms,present_avg_ms,seconds,ffmpeg_args\n' \
        > "$csv"
fi

cd "$output_dir"

for mode in default amd nvidia both-gpu no-gpu; do
    case "$mode" in
        default) flags=() ;;
        amd) flags=(-amd) ;;
        nvidia) flags=(-nvidia) ;;
        both-gpu) flags=(-both-gpu) ;;
        no-gpu) flags=(-no-gpu) ;;
    esac

    taskkill.exe //F //IM P6.exe > /dev/null 2>&1 || true
    rm -f p6-debug-events.log

    # Run in the foreground under timeout: backgrounded launches from inside a
    # script did not survive here and left no log behind at all.
    # 以 timeout 在前景執行：在腳本內以背景方式啟動無法存活，完全不會留下 log。
    timeout "$seconds" ./P6.exe -f q0eVan-FNS4 -autoplay -enable-dropframe \
        -maximized -topmost -res "$resolution" -fps "$target_fps" "${flags[@]}" > /dev/null 2>&1 || true

    taskkill.exe //F //IM P6.exe > /dev/null 2>&1 || true

    printf '=== %s ===\n' "$mode"
    if [ ! -f p6-debug-events.log ]; then
        printf '  no log produced\n'
        continue
    fi
    grep -m 1 "adapters=" p6-debug-events.log | sed 's/^P6 [^ ]* [^ ]* [^ ]* //' || true

    dropped="$({ grep -o "dropped frames/sec [0-9]*" p6-debug-events.log || true; } \
        | awk '{s+=$4; n++} END {if (n) printf "%.1f", s/n; else printf "NA"}')"

    # One "stage timings" line per second: frames and elapsed give the measured
    # frame rate, the averages give where the time went.
    # 每秒一行 "stage timings"：frames 與 elapsed 可得實測影格率，平均值則顯示時間
    # 花在哪裡。
    stats="$({ grep "stage timings" p6-debug-events.log || true; } \
        | sed -E 's/.*stage timings: ([0-9]+) frames in ([0-9.]+)s, read avg ([0-9.]+)ms max [0-9.]+ms, present avg ([0-9.]+)ms.*/\1 \2 \3 \4/' \
        | awk '{f+=$1; t+=$2; r+=$3; p+=$4; n++}
               END {if (n) printf "%.1f %.1f %.1f", f/t, r/n, p/n; else printf "NA NA NA"}')"

    fps="${stats%% *}"
    rest="${stats#* }"
    read_ms="${rest%% *}"
    present_ms="${rest##* }"

    # The last session's arguments: earlier ones are the single-frame decode
    # done at load, which uses the same chain but a different seek.
    # 取最後一個 session 的參數：先前的是載入時的單張解碼，濾鏡鏈相同但 seek 不同。
    ffmpeg_args="$({ grep "ffmpeg args:" p6-debug-events.log || true; } | tail -1 \
        | sed 's/.*ffmpeg args: //' | tr -d '\r')"

    printf '  fps %s, dropped/s %s, read %sms, present %sms\n' \
        "$fps" "$dropped" "$read_ms" "$present_ms"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
        "$(date +%Y-%m-%d)" "$mode" "$resolution" "$target_fps" "$fps" "$dropped" \
        "$read_ms" "$present_ms" "$seconds" "$ffmpeg_args" >> "$csv"
    cp p6-debug-events.log "p6-gpu-$mode-$resolution-$target_fps.log"
done
