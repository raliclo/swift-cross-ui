#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P21"
export TEST_TITLE="P21 input controls"
export TEST_LOG_NAME="p21-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|Button|TextField|SecureField|TextEditor|slider|disabled|ContentUnavailable"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
