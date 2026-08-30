#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P37"
export TEST_TITLE="P37 window level"
export TEST_LOG_NAME="p37-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="supported levels|floating|topmost|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
