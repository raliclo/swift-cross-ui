#!/usr/bin/env zsh
# Launches P126, colorInvert(), which checks that inversion leaves the layout alone.
#   zsh testapp/test.zsh P126                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P126 --actionfile    wait, then expect P126 PASS
#
# 啟動 P126:colorInvert(),它會檢查反轉不影響版面。
#   zsh testapp/test.zsh P126                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P126 --actionfile    等待，預期 P126 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P126"
export TEST_TITLE="P126 Color invert"
export TEST_LOG_NAME="p126-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P126"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
