#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P40"
export TEST_TITLE="P40 geometric effects"
export TEST_LOG_NAME="p40-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="geometric|hotpink|transform|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
