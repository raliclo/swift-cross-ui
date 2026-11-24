#!/usr/bin/env zsh
# Launches P125, zIndex, checked by where taps land.
#   zsh testapp/test.zsh P125                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P125 --actionfile    wait, then expect P125 PASS
#
# 啟動 P125:zIndex,以點擊落在何處檢查。
#   zsh testapp/test.zsh P125                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P125 --actionfile    等待，預期 P125 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P125"
export TEST_TITLE="P125 zIndex"
export TEST_LOG_NAME="p125-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P125"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
