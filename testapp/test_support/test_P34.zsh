#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P34"
export TEST_TITLE="P34 large collections"
export TEST_LOG_NAME="p34-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|backend|rows="
# The caller's arguments win, and 100 rows is only the default. Until 2026-09-28 this
# line overwrote TEST_APP_ARGS unconditionally, so the `-rows 500` that P34's iOS
# action files require -- at 100 both buttons are no-ops by design -- never reached
# the app however it was asked for.
# 呼叫端的參數優先,100 列只是預設值。2026-09-28 之前這一行無條件覆寫 TEST_APP_ARGS,因此 P34 的 iOS
# 動作檔所需的 `-rows 500`(在 100 之下兩顆按鈕依設計都是 no-op)不論怎麼要求都到不了 app。
export TEST_APP_ARGS="${TEST_APP_ARGS:---debug -rows 100}"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
