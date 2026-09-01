#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P42"
export TEST_TITLE="P42 window scale factor"
export TEST_LOG_NAME="p42-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|scale factor ->"
export TEST_TARGET="windows"
# No action file. The event under test is a display-scale change, which no
# synthesised click can produce -- it is made in Settings, by hand, while the
# window is up. Use --showtime to hold the window open long enough to do it.
# 沒有動作檔。受測事件是「顯示器縮放改變」，那不是任何合成點擊能產生的——它必須在設定中手動完成，
# 且要在視窗開著的時候。請用 --showtime 讓視窗停留夠久以便操作。
exec zsh "$support_dir/test_common.zsh" "$@"
