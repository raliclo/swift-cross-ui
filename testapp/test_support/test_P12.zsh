#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P12"
export TEST_TITLE="P12 Android margins, state and toggles"
export TEST_LOG_NAME="p12-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|#632|#580|#544"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
