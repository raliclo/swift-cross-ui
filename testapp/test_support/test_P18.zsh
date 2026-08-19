#!/usr/bin/env zsh
# P18 file dialogs, run on both Windows and WSLg for comparison.
#
#   zsh testapp/test.zsh P18
#
# P18 檔案對話框，於 Windows 與 WSLg 兩端執行以供對照。
#
# The dialogs need a person to click them, so this run only gets the window up
# and confirms it rendered. What it does give you is both backends in the same
# state, ready to be driven by hand, and a log in the same format from each.
# 對話框需要人實際點擊，因此本次執行只負責把視窗開起來並確認已算繪完成。它真正提供的是
# 讓兩個 backend 處於相同狀態、可供手動操作，並各自產生格式一致的日誌。
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P18"
export TEST_TITLE="P18 file dialogs"
export TEST_LOG_NAME="p18-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend |open:|folder:|save:"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
