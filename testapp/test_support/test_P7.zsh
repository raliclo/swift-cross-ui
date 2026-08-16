#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P7"
export TEST_TITLE="P7 lists and split views"
export TEST_LOG_NAME="p7-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="sidebar content|content:|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
