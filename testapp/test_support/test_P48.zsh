#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P48"
export TEST_TITLE="P48 lazy grids"
export TEST_LOG_NAME="p48-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
