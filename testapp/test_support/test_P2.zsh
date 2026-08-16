#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P2"
export TEST_TITLE="P2 WinUI controls and styling"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
