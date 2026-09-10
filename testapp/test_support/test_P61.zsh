#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P61"
export TEST_TITLE="P61 slider onEditingChanged"
export TEST_LOG_NAME="p61-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|editing |moved from code"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
