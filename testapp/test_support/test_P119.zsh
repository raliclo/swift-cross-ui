#!/usr/bin/env zsh
# Launches P119, the guard against root widgets freed with their child attached.
#   zsh testapp/test.zsh P119            show the app; the verdict is in its window
#   P119_SEQUENCE=1 ./output/P119-gtk4   exit 0 on PASS, 1 on FAIL, for scripts
#
# 啟動 P119:防止 root widget 在子元件仍掛著時被釋放的回歸防護。
#   zsh testapp/test.zsh P119            顯示 app,結果在視窗裡
#   P119_SEQUENCE=1 ./output/P119-gtk4   PASS 以 0 結束、FAIL 以 1 結束，供腳本使用
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P119"
export TEST_TITLE="P119 Root widget teardown"
export TEST_LOG_NAME="p119-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P119"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
