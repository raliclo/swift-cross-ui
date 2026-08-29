#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P27"
export TEST_TITLE="P27 backend feature coverage"
export TEST_LOG_NAME="p27-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|WebView|Gradient|Angular"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
