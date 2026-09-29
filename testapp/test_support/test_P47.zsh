#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P47"
export TEST_TITLE="P47 symbols"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
