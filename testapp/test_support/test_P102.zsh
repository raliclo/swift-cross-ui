#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P102"
export TEST_TITLE="P102 select"
export TEST_TARGET="both"
export TEST_LOG_NAME="p102-select.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|FIELD|EDITOR|CONTROL"
exec zsh "$support_dir/test_common.zsh" "$@"
