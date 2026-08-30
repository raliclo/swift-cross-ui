#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P32"
export TEST_TITLE="P32 accessibility"
export TEST_LOG_NAME="p32-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|accessibility|button clicked"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
