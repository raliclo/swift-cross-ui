#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P13"
export TEST_TITLE="P13 layout and view graph"
export TEST_LOG_NAME="p13-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#415|#595|#291|#158"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
