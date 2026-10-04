#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P77"
export TEST_TITLE="P77 one million vertices"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
