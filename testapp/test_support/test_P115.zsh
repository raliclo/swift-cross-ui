#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P115"
export TEST_TITLE="P115 view labels"
export TEST_LOG_NAME="p115-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|switch|checkbox|button|string|link"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
