#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P103"
export TEST_TITLE="P103 emoji"
export TEST_TARGET="both"
export TEST_LOG_NAME="p103-emoji.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|ROW|SOLO|PICKER|PIN|CSV"
exec zsh "$support_dir/test_common.zsh" "$@"
