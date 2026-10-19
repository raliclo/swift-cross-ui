#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P111"
export TEST_TITLE="P111 keyframe velocity"
export TEST_TARGET="both"
export TEST_LOG_NAME="p111-keyframe-velocity.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|TIMELINE|DONE"
exec zsh "$support_dir/test_common.zsh" "$@"
