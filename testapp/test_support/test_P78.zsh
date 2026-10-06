#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P78"
export TEST_TITLE="P78 incoming URLs"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
