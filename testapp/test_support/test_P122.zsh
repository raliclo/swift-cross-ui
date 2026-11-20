#!/usr/bin/env zsh
# Launches P122, text decorations and spacing, which checks its own measurements.
#   zsh testapp/test.zsh P122                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P122 --actionfile    wait, then expect P122 PASS
#
# 啟動 P122:文字裝飾與間距，它會自行檢查量測結果。
#   zsh testapp/test.zsh P122                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P122 --actionfile    等待，預期 P122 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P122"
export TEST_TITLE="P122 Text decorations"
export TEST_LOG_NAME="p122-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P122"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
