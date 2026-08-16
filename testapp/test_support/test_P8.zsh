#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P8"
export TEST_TITLE="P8 scroll views"
export TEST_LOG_NAME="p8-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="cornerScroll|redChild|outerScroll|innerStrip|RENDER COMPLETE"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
