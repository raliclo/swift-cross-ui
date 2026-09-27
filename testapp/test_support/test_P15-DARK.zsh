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
# No marker. P15-DARK.swift never writes "RENDER COMPLETE" or any log line --
# p15-dark-debug-events.log stays at 0 bytes -- so the marker this script used to
# name made every macOS run wait out the 30-second timeout and take a `timeout`
# capture instead of a `final` one (found 2026-09-27, the first time a sweep ran
# this file against P15-DARK rather than P15). With an action file, test_common
# waits for the replay to finish instead.
# 不設 marker。P15-DARK.swift 從不寫「RENDER COMPLETE」或任何 log——p15-dark-debug-events.log 一直是
# 0 位元組——因此本腳本原本指定的 marker,讓每一次 macOS 執行都等滿 30 秒逾時,拍下 `timeout` 擷圖而不是
# `final`(2026-09-27 發現,那是 sweep 第一次拿這份檔案去對 P15-DARK、而不是對 P15 執行)。
export TEST_MARKER=""
export TEST_SUMMARY_PATTERN="RENDER COMPLETE|Requested|Resolved"
export TEST_TARGET="wsl"
exec zsh "$support_dir/test_common.zsh" "$@"
