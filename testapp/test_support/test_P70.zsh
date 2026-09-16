#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P70"
export TEST_TITLE="P70 focus state"
export TEST_LOG_NAME="p70-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|FOCUS now|TEXT FOCUS|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
