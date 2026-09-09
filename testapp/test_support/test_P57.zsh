#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P57"
export TEST_TITLE="P57 list cost"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
