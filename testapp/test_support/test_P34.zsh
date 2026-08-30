#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P34"
export TEST_TITLE="P34 large collections"
export TEST_LOG_NAME="p34-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|rows="
export TEST_APP_ARGS="--debug -rows 100"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
