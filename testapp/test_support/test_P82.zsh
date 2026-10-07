#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P82"
export TEST_TITLE="P82 destructive buttons"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
