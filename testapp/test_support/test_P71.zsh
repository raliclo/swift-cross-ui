#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P71"
export TEST_TITLE="P71 menu shortcuts"
export TEST_LOG_NAME="p71-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|PLAIN fired|SHIFTED fired|DISABLED FIRED|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
