#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P117"
export TEST_TITLE="P117 TextEditor sizing"
export TEST_LOG_NAME="p117-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="P117"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
