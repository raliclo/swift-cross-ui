#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P59"
export TEST_TITLE="P59 scene storage"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
