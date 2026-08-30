#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P30"
export TEST_TITLE="P30 effects and animation"
export TEST_LOG_NAME="p30-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|size toggled|effects|animation"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
