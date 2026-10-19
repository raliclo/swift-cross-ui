#!/bin/zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P107"
export TEST_TITLE="P107 motion path"
export TEST_TARGET="both"
export TEST_LOG_NAME="p107-motion-path.log"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|RUN|BACK|SET|DONE"
exec zsh "$support_dir/test_common.zsh" "$@"
