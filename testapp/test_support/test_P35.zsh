#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P35"
export TEST_TITLE="P35 state and scene"
export TEST_LOG_NAME="p35-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|count=|state|scene"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
