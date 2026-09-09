#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P60"
export TEST_TITLE="P60 settings scene"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
