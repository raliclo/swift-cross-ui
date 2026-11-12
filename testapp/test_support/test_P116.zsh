#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P116"
export TEST_TITLE="P116 layout timing"
export TEST_LOG_NAME="p116-debug-events.log"
export TEST_MARKER="appear-to-hop"
export TEST_SUMMARY_PATTERN="onAppear|onChange|appear-to-hop"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
