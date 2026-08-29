#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P39"
export TEST_TITLE="P39 visual effects"
export TEST_LOG_NAME="p39-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="backend|samples|visual|effect|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
