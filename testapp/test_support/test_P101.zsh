#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P101"
export TEST_TITLE="P101 scroll"
export TEST_TARGET="both"
export TEST_LOG_NAME="p101-scroll.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|START|TO10|CENTER3|row 15"
exec zsh "$support_dir/test_common.zsh" "$@"
