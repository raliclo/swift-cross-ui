#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P52"
export TEST_TITLE="P52"
export TEST_LOG_NAME="p52-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="P52 results|press |mount |NO RESULT|backend"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
