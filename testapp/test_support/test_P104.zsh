#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P104"
export TEST_TITLE="P104 layout animation"
export TEST_TARGET="both"
export TEST_LOG_NAME="p104-layout-animation.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|MID|DONE|NIL|JUMP"
exec zsh "$support_dir/test_common.zsh" "$@"
