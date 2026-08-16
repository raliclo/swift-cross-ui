#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P3"
export TEST_TITLE="P3 WinUI layout and clipping"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
