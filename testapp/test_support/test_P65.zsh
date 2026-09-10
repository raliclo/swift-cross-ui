#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P65"
export TEST_TITLE="P65 continuous gestures"
export TEST_LOG_NAME="p65-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|drag |magnify|rotate|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
