#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P114"
export TEST_TITLE="P114 back button label"
export TEST_LOG_NAME="p114-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|path ->"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
