#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P81"
export TEST_TITLE="P81 window A"
# The pass condition is a sheet over window B -- a window of its own -- so the
# final screenshot is of the desktop, not of window A by title (2026-10-22).
# 通過條件是視窗 B 上的 sheet(它自己就是一個視窗),所以最後那張拍整個桌面，而不是依標題拍視窗 A(2026-10-22)。
export TEST_FINAL_CAPTURE=desktop
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
