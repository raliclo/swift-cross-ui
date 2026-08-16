#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P9"
export TEST_TITLE="P9 text and field sizing"
export TEST_LOG_NAME="p9-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#504|#295"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
