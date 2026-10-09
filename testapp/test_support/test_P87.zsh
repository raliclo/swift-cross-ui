#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P87"
export TEST_TITLE="P87 SVG paint and effects"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
