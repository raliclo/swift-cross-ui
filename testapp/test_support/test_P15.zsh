#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P15"
export TEST_TITLE="P15 colour scheme and window height"
export TEST_LOG_NAME="p15-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#386|#289"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
