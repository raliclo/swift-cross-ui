#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P36"
export TEST_TITLE="P36 API shape compatibility"
export TEST_LOG_NAME="p36-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|API|button clicked"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
