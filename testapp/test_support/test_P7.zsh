#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P7"
export TEST_TITLE="P7 lists and split views"
export TEST_LOG_NAME="p7-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
# SplitView's own diagnostics, which report the bounds handed to the backend
# and the divider position. Only P7 exercises a split view, so only P7 asks
# for them.
# SplitView 自身的診斷，會回報交給 backend 的上下界與分隔線位置。只有 P7 用到
# split view，因此只有 P7 需要開啟。
export TEST_APP_ENV="SCUI_DEBUG_SPLIT=1"
export TEST_EXTRA_LOG="splitview-debug.log"
export TEST_SUMMARY_PATTERN="sidebar content|content:|RENDER COMPLETE|\[SplitView\]"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
