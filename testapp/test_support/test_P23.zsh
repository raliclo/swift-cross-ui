#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P23"
export TEST_TITLE="P23 tables"
export TEST_LOG_NAME="p23-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|rows|selection|table|cell|header"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
