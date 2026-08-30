#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P25"
export TEST_TITLE="P25 drag and drop"
export TEST_LOG_NAME="p25-debug-events.log"
export TEST_EXTRA_LOG="scui-dnd-debug.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|SCUI_DND|drop|hover|received|Accepts|Refuses"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
