#!/usr/bin/env zsh
# Launches P128, tint(_:), which checks the tint reaches the controls and changes no size.
#   zsh testapp/test.zsh P128                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P128 --actionfile    wait, then expect P128 PASS
#
# 啟動 P128:tint(_:),它會檢查 tint 抵達控制項且不改變任何尺寸。
#   zsh testapp/test.zsh P128                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P128 --actionfile    等待，預期 P128 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P128"
export TEST_TITLE="P128 Tint"
export TEST_LOG_NAME="p128-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P128"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
