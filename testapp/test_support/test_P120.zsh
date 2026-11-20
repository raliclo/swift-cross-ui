#!/usr/bin/env zsh
# Launches P120, NavigationSplitView in a compact window: choose a row, then Back.
#   zsh testapp/test.zsh P120                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P120 --actionfile    choose Banana, press Back, expect P120 PASS
#
# 啟動 P120:compact 視窗中的 NavigationSplitView,選一列，再按 Back。
#   zsh testapp/test.zsh P120                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P120 --actionfile    選 Banana、按 Back,預期 P120 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P120"
export TEST_TITLE="P120 NavigationSplitView compact"
export TEST_LOG_NAME="p120-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P120"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
