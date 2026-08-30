#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P33"
export TEST_TITLE="P33 missing views"
export TEST_LOG_NAME="p33-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|missing|Stepper|DisclosureGroup"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
