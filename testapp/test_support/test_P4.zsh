#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P4"
export TEST_TITLE="P4 WinUI native and callback stress"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
