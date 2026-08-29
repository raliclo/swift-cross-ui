#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P29"
export TEST_TITLE="P29 visual fidelity"
export TEST_LOG_NAME="p29-debug-events.log"
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|progress|cornerRadius|TextEditor|disabled"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
