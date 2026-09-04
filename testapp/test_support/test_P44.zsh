#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P44"
export TEST_TITLE="P44 clipping"
export TEST_LOG_NAME="p44-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="clipped|third cell|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
