#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P83"
export TEST_TITLE="P83 list styles"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
