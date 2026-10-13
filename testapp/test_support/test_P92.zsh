#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P92"
export TEST_TITLE="P92 command groups"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
