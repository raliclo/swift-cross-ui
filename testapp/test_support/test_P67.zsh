#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P67"
export TEST_TITLE="P67 accessibility names"
export TEST_LOG_NAME="p67-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|BUTTON |BUTTONS FOUND|ACCESSIBILITY|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
