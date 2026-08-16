#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P10"
export TEST_TITLE="P10 hit testing and shortcuts"
export TEST_LOG_NAME="p10-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#454|#478"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
