#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P94"
export TEST_TITLE="P94 editor undo"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
