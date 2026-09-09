#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P58"
export TEST_TITLE="P58 two scroll views, one reader"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
