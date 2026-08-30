#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P31"
export TEST_TITLE="P31 focus and keyboard"
export TEST_LOG_NAME="p31-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|button clicked|alert"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
