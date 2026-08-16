#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P14"
export TEST_TITLE="P14 rotation and theme"
export TEST_LOG_NAME="p14-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#324|#254"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
