#!/usr/bin/env zsh
# Launches P127, .focusDisabled() and .focusEffectDisabled(), checked by the app itself.
#   zsh testapp/test.zsh P127                 show the app; it waits for one Tab, then gives its verdict
#   zsh testapp/test.zsh P127 --actionfile    press Tab, then expect P127 PASS
#
# 啟動 P127:.focusDisabled() 與 .focusEffectDisabled(),由 app 自己檢查。
#   zsh testapp/test.zsh P127                 顯示 app,等待一次 Tab,之後給出結果
#   zsh testapp/test.zsh P127 --actionfile    按 Tab,預期 P127 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P127"
export TEST_TITLE="P127 Focus disabling and focus effects"
export TEST_LOG_NAME="p127-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P127"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
