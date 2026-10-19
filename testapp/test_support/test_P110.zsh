#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P110"
export TEST_TITLE="P110 gradient tween"
export TEST_TARGET="both"
export TEST_LOG_NAME="p110-gradient-tween.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|MID|DONE|VALUE|JUMP|FINAL"
exec zsh "$support_dir/test_common.zsh" "$@"
