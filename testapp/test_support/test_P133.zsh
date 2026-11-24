#!/usr/bin/env zsh
# Launches P133, a growing ScrollView, which checks its top stays in view.
#   zsh testapp/test.zsh P133                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P133 --actionfile    wait, then expect P133 PASS
#
# 啟動 P133:變高的 ScrollView,它會檢查頂端維持可見。
#   zsh testapp/test.zsh P133                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P133 --actionfile    等待，預期 P133 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P133"
export TEST_TITLE="P133 Scroll growth"
export TEST_LOG_NAME="p133-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P133"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
