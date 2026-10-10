#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P90"
export TEST_TITLE="P90 wheels by region"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
