#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P22"
export TEST_TITLE="P22 text styles"
export TEST_LOG_NAME="p22-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|caption|footnote|subheadline|body|title|large title|lineLimit|wrapped|font|weight|alignment"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
