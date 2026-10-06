#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P80"
export TEST_TITLE="P80 input targets"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
