#!/usr/bin/env zsh
# Launches P129, controlSize(_:), which checks small < regular < large for each control.
#   zsh testapp/test.zsh P129                 show the app; the verdict is in its window
#   zsh testapp/test.zsh P129 --actionfile    wait, then expect P129 PASS
#
# 啟動 P129:controlSize(_:),它會檢查每種控制項都是 small < regular < large。
#   zsh testapp/test.zsh P129                 顯示 app,結果在視窗裡
#   zsh testapp/test.zsh P129 --actionfile    等待，預期 P129 PASS
set -euo pipefail
script_path="${0:A}"
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,8p' "$script_path" | sed 's/^# \{0,1\}//'
    exit 0
fi
support_dir="${0:a:h}"
export TEST_APP="P129"
export TEST_TITLE="P129 Control size"
export TEST_LOG_NAME="p129-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P129"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
