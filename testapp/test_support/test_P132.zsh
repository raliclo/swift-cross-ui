#!/usr/bin/env zsh
# Launches P132, blendMode(_:), which checks that blending leaves the layout alone.
#   zsh testapp/test.zsh P132                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P132 --actionfile    wait, then expect P132 PASS
#
# 啟動 P132:blendMode(_:),它會檢查混合不影響版面。
#   zsh testapp/test.zsh P132                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P132 --actionfile    等待，預期 P132 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P132"
export TEST_TITLE="P132 Blend mode"
export TEST_LOG_NAME="p132-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P132"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
