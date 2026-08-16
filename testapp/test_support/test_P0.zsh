#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P0"
export TEST_TITLE="P0 WinUI critical checks"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
