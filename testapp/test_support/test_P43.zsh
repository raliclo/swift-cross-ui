#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P43"
export TEST_TITLE="P43 gradient fills"
export TEST_LOG_NAME="p43-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="gradient|circle|clipped|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
