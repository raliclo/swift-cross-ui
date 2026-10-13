#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P93"
export TEST_TITLE="Alpha"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
