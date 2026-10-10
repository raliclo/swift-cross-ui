#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P88"
export TEST_TITLE="P88 pointer hover"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
