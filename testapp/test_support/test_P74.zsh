#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P74"
export TEST_TITLE="P74 picker styles"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
