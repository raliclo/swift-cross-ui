#!/usr/bin/env zsh
# Launches P123, shadow(color:radius:x:y:), which checks that shadows leave the layout alone.
#   zsh testapp/test.zsh P123                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P123 --actionfile    wait, then expect P123 PASS
#
# 啟動 P123:shadow(color:radius:x:y:),它會檢查陰影不影響版面。
#   zsh testapp/test.zsh P123                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P123 --actionfile    等待，預期 P123 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P123"
export TEST_TITLE="P123 Shadow"
export TEST_LOG_NAME="p123-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P123"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
