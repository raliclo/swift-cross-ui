#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P105"
export TEST_TITLE="P105 transitions"
export TEST_TARGET="both"
export TEST_LOG_NAME="p105-transitions.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|MID|DONE|REMOVE|EACH|JUMP"
exec zsh "$support_dir/test_common.zsh" "$@"
