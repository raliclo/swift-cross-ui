#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P100"
export TEST_TITLE="P100 flip"
export TEST_TARGET="both"
export TEST_LOG_NAME="p100-flip.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|MID|DONE|JUMP"
exec zsh "$support_dir/test_common.zsh" "$@"
