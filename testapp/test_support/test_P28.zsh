#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P28"
export TEST_TITLE="P28 hit testing"
export TEST_LOG_NAME="p28-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|underlying button clicked"
export TEST_TARGET="macos"
exec zsh "$support_dir/test_common.zsh" "$@"
