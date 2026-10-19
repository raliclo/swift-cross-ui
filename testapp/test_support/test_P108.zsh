#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P108"
export TEST_TITLE="P108 inertia"
export TEST_TARGET="both"
export TEST_LOG_NAME="p108-inertia.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|FREE|BOUND|DRAG|HOLD|DONE"
exec zsh "$support_dir/test_common.zsh" "$@"
