#!/bin/zsh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir="$script_dir/output"
command_name=$(basename -- "$0")

# Windows produces P6.exe, other platforms produce P6.
# Windows 產生 P6.exe，其他平台產生 P6。
if [ -x "$output_dir/P6.exe" ]; then
    p6_executable="$output_dir/P6.exe"
elif [ -x "$output_dir/P6" ]; then
    p6_executable="$output_dir/P6"
else
    printf '%s\n' \
        "P6 executable not found in: $output_dir" \
        "在此找不到 P6 執行檔：$output_dir" \
        "Build it with: zsh testapp/compile.zsh P6" \
        "或使用 release 版本：BUILD_CONFIG=release zsh testapp/compile.zsh P6" >&2
    exit 1
fi

usage() {
    printf '%s\n' \
        "Usage: $command_name [file-pattern] [extra P6 flags...]" \
        "用法：$command_name [檔名關鍵字] [其他 P6 參數...]" \
        "" \
        "Runs P6 with autoplay and frame dropping already enabled." \
        "以「自動播放」與「丟棄延遲影格」皆開啟的狀態執行 P6。" \
        "" \
        "  file-pattern  Substring of the file name, or a full path." \
        "                Omit it to use P6's built-in default (恩典365)." \
        "  檔名關鍵字     檔名的一部分，或完整路徑；省略則使用 P6 內建預設值。" \
        "" \
        "Examples 範例:" \
        "  $command_name" \
        "  $command_name 耶利米" \
        "  $command_name 恩典365 --debug" \
        "  $command_name '/path/to/video.webm'"
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

typeset -a p6_arguments
p6_arguments=(-autoplay -enable-dropframe)

# A leading non-flag argument selects the file; anything else is passed through.
# 開頭的非旗標參數用於選擇檔案，其餘參數原樣轉送。
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
    p6_arguments+=(-f "$1")
    shift
else
    p6_arguments+=(-f)
fi

p6_arguments+=("$@")

# Run from the output directory so p6-debug-events.log lands next to the
# executable instead of in whatever directory this was invoked from.
# 於 output 目錄執行，讓 p6-debug-events.log 產生在執行檔旁邊，而非呼叫時所在的目錄。
cd -- "$output_dir"

printf '%s\n' "==> $p6_executable ${p6_arguments[*]}"
printf '%s\n' "    log: $output_dir/p6-debug-events.log"

"$p6_executable" "${p6_arguments[@]}"
