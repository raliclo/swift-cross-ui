#!/usr/bin/env zsh
# P15-DARK had no test script, so `test.zsh P15-DARK` stopped with
# "Missing test script" and its action file could not be replayed at all. The
# app and the file both existed; only this was missing.
#
# P15-DARK 先前沒有 test script，因此 `test.zsh P15-DARK` 會以「Missing test script」中止，
# 其動作檔根本無法重放。該 app 與該檔案都存在，缺的只有這一個。
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P15-DARK"
export TEST_TITLE="P15-DARK preferredColorScheme"
export TEST_LOG_NAME="p15-dark-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|Requested|Resolved"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
