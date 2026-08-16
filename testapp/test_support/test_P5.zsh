#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P5"
export TEST_TITLE="P5 multi-window alerts"
export TEST_TARGET="windows"
exec zsh "$support_dir/test_common.zsh" "$@"
