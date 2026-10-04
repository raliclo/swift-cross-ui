#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P76"
export TEST_TITLE="P76 mesh primitives"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
