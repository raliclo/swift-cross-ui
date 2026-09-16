#!/usr/bin/env zsh
# Injects a two-finger touch pinch or rotate into a named window (Windows only).
#
#   zsh testapp/touch_gesture.zsh "P65" pinch  <cx> <cy> <startGap> <endGap> [steps] [ms]
#   zsh testapp/touch_gesture.zsh "P65" rotate <cx> <cy> <radius> <startDeg> <endDeg> [steps] [ms]
#   zsh testapp/touch_gesture.zsh "P65" drag   <x0> <y0> <x1> <y1> [steps] [ms]   one contact
#   zsh testapp/touch_gesture.zsh --help
#
# Coordinates are physical pixels relative to the window frame, the same origin
# as `frame` in testapp/actions/*.csv. Builds testapp/touch_gesture.c into
# testapp/helper/bin/ when the source is newer than the executable.
#
# Why a separate tool and not an action-file verb: see the header of
# touch_gesture.c -- a new InputAction case would break the Mac build.
#
# 向指定視窗注入兩指觸控捏合或旋轉(僅限 Windows)。座標是相對於視窗外框的實體像素,與
# testapp/actions/*.csv 的 `frame` 同一原點。原始碼比執行檔新時,會把 touch_gesture.c 建到
# testapp/helper/bin/。為何是獨立工具而非動作檔動詞:見 touch_gesture.c 開頭——新增 InputAction
# case 會弄壞 Mac 的建置。
set -euo pipefail

script_path="${0:A}"
script_dir="${script_path:h}"

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,19p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        printf 'touch_gesture.zsh: Windows only (uname -s = %s)\n' "$(uname -s)" >&2
        exit 2
        ;;
esac

source_file="${script_dir}/touch_gesture.c"
exe_file="${script_dir}/helper/bin/touch_gesture.exe"

if [[ ! -x "$exe_file" || "$source_file" -nt "$exe_file" ]]; then
    mkdir -p "${exe_file:h}"
    printf 'touch_gesture.zsh: building %s\n' "$exe_file" >&2
    clang -O1 -Wall -municode "$source_file" -o "$exe_file" -luser32
fi

exec "$exe_file" "$@"
