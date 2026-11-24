#!/usr/bin/env zsh
# Launches P130, badge(_:), which checks badges on tabs and list rows and that 0 hides one.
#   zsh testapp/test.zsh P130                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P130 --actionfile    wait, then expect P130 PASS
#
# 啟動 P130:badge(_:),它會檢查分頁與清單列上的徽章，以及 0 會隱藏徽章。
#   zsh testapp/test.zsh P130                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P130 --actionfile    等待，預期 P130 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P130"
export TEST_TITLE="P130 Badge"
export TEST_LOG_NAME="p130-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P130"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
