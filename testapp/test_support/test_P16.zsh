#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P16"
export TEST_TITLE="P16 split view initial layout"
export TEST_LOG_NAME="p16-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|sidebar:|middle:|detail:|#160"
export TEST_TARGET="windows"
export TEST_ACTION_FILE="$support_dir/../actions/win/P16-force-update.csv"
exec zsh "$support_dir/test_common.zsh" "$@"
