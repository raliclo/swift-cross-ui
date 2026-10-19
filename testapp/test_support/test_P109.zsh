#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P109"
export TEST_TITLE="P109 style animation"
export TEST_TARGET="both"
export TEST_LOG_NAME="p109-style-animation.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|MID|DONE|JUMP"
exec zsh "$support_dir/test_common.zsh" "$@"
