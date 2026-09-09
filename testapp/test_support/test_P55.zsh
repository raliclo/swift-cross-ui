#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P55"
export TEST_TITLE="P55 button style"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
