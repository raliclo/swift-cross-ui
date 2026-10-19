#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P106"
export TEST_TITLE="P106 keyframes"
export TEST_TARGET="both"
export TEST_LOG_NAME="p106-keyframes.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|KEYS|LOOP|PHASE|CYCLE|DONE"
exec zsh "$support_dir/test_common.zsh" "$@"
