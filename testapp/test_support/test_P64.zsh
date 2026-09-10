#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P64"
export TEST_TITLE="P64 frame clock"
export TEST_LOG_NAME="p64-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|TICKS|starting the frame clock|does not conform|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
