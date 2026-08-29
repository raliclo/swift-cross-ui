#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P41"
export TEST_TITLE="P41 date picker styles"
export TEST_LOG_NAME="p41-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="date picker|graphical|wheel|automatic|compact|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
