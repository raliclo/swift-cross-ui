#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P97"
export TEST_TITLE="P97 timing control"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
