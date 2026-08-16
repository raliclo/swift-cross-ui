#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P11"
export TEST_TITLE="P11 sliders, scrollbars and pickers"
export TEST_LOG_NAME="p11-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#82|#485|#473"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
