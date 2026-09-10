#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P63"
export TEST_TITLE="P63 coordinate spaces"
export TEST_LOG_NAME="p63-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|local:|global:|named box:|backend"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
