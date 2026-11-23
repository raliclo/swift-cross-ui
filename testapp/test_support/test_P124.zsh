#!/usr/bin/env zsh
# Launches P124, scaledToFit, scaledToFill and labelsHidden, each checked by measuring.
#   zsh testapp/test.zsh P124                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P124 --actionfile    wait, then expect P124 PASS
#
# 啟動 P124:scaledToFit、scaledToFill 與 labelsHidden,各以量測檢查。
#   zsh testapp/test.zsh P124                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P124 --actionfile    等待，預期 P124 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P124"
export TEST_TITLE="P124 Scaling and hidden labels"
export TEST_LOG_NAME="p124-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P124"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
