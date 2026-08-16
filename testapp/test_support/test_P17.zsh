#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P17"
export TEST_TITLE="P17 cross-backend layout"
export TEST_LOG_NAME="p17-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|subject:|control:|picker:|aspect:|stack:|#264|#161|#266"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
