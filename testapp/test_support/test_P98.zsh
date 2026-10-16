#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P98"
export TEST_TITLE="P98 callbacks and stagger"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
