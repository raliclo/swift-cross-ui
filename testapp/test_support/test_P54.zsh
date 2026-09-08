#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P54"
export TEST_TITLE="P54 refreshable"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
