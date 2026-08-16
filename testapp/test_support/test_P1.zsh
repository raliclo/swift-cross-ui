#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P1"
export TEST_TITLE="P1 WinUI dialogs and sheets"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
