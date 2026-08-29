#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P24"
export TEST_TITLE="P24 navigation stack"
export TEST_LOG_NAME="p24-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|Level|counter|push|pop|path"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
