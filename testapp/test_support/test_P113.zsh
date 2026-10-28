#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P113"
export TEST_TITLE="P113 window behaviors"
export TEST_TARGET="both"
export TEST_LOG_NAME="p113.log"
export TEST_SUMMARY_PATTERN="[P113] main closable"
exec zsh "$support_dir/test_common.zsh" "$@"
