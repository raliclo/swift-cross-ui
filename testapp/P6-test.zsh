#!/usr/bin/env zsh
# Runs P6 unattended: autoplay on, frame dropping on, so a throughput run needs
# no clicks. Give it a file-name fragment and it picks the matching media out of
# testapp/output; anything else on the line is passed through to P6.
#
#   zsh testapp/P6-test.zsh 4k            # first file whose name contains "4k"
#   zsh testapp/P6-test.zsh 4k -nv12      # and hand -nv12 to P6
#
# 以無人值守方式執行 P6：自動播放與丟棄延遲影格皆開啟，量測吞吐量不需要任何點擊。
# 傳入檔名片段即可從 testapp/output 挑出對應媒體，其餘參數原樣轉交給 P6。
#
# The sibling script is test_P6.zsh, which is the interactive counterpart: it
# takes explicit flags and an explicit media path. This one exists for the
# repeated runs behind gpu-matrix.zsh, where every prompt is a run that did not
# happen.
# 姊妹腳本是 test_P6.zsh，屬互動用途，需明確給定旗標與媒體路徑。本腳本則是為
# gpu-matrix.zsh 的重複執行而存在——在那裡，每一次提示都代表一次沒跑成的量測。

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
        "需要未最佳化 build 時：BUILD_CONFIG=debug zsh testapp/compile.zsh P6" >&2
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
