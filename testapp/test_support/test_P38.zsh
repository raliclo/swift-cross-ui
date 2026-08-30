#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P38"
export TEST_TITLE="P38 web view"
export TEST_LOG_NAME="p38-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="navigated|Requested|WebView|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
