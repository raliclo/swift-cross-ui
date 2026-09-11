#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P68"
export TEST_TITLE="P68 graphics adapters"
export TEST_LOG_NAME="p68-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|adapters:|-GPU|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
