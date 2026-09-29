#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P75"
export TEST_TITLE="P75 system hand-offs"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
