#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P72"
export TEST_TITLE="P72 mesh view"
export TEST_LOG_NAME="p72-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
# STOPPED and CHECK are the two lines the action file exists for; the rest name
# the backend and say whether the conformance is there at all.
# STOPPED 與 CHECK 是那份動作檔存在的理由;其餘幾條說明是哪個 backend,以及那個 conformance 到底在不在。
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|AUTO SPIN|STOPPED at frame|CHECK at frame|mesh view supported|NO FRAME CLOCK|backend"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
