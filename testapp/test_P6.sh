#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
p6_executable="$script_dir/output/P6"

# Show the complete command shape before requiring a media path.
# 在要求媒體路徑前，先顯示完整的命令格式。
usage() {
    command_name=$(basename -- "$0")
    printf '%s\n' \
        "Usage: $command_name [-metal|-core] [--debug] [--frame-drop] <media-file>" \
        "用法：$command_name [-metal|-core] [--debug] [--frame-drop] <媒體檔案>" \
        "Example: $command_name --debug --frame-drop '/path/to/video.webm'" \
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

"$p6_executable" "$@"
