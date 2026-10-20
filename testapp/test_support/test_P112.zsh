#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P112"
export TEST_TITLE="P112 radial radii"
export TEST_TARGET="both"
export TEST_LOG_NAME="p112.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE"
exec zsh "$support_dir/test_common.zsh" "$@"
