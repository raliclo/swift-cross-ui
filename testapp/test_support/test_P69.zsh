#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P69"
export TEST_TITLE="P69 accessibility modifiers"
export TEST_LOG_NAME="p69-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|ACCESSIBILITY READ|HIDDEN|/h'|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
