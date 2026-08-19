#!/usr/bin/env zsh
# P19 flat menus, run on both Windows and WSLg for comparison.
#
#   zsh testapp/test.zsh P19
#
# P19 平面選單，於 Windows 與 WSLg 兩端執行以供對照。
#
# The menus need a person to open them, so this run only gets the window up and
# confirms it rendered. What it gives you is both backends in the same state and
# a log in the same format from each.
# 選單需要人實際開啟，因此本次執行只負責把視窗開起來並確認已算繪完成。它提供的是讓兩個
# backend 處於相同狀態，並各自產生格式一致的日誌。
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P19"
export TEST_TITLE="P19 flat menus"
export TEST_LOG_NAME="p19-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|clicked:"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
