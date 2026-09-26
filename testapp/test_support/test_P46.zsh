#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P46"
# **This script did not exist until 2026-09-27**, though P46 had a macOS action
# file; the first macOS sweep found `test.zsh P46` stopping at "Missing test
# script". Title copied from P46.swift's WindowGroup.
#
# A real marker here, unlike P45/P49/P53: P46 writes its lines to
# p46-debug-events.log, which is the file the marker wait reads.
#
# **這支腳本在 2026-09-27 之前不存在**,雖然 P46 有一份 macOS 動作檔;第一次 macOS sweep 發現
# `test.zsh P46` 停在「Missing test script」。標題照抄自 P46.swift 的 WindowGroup。
#
# 這裡設了真正的 marker,與 P45/P49/P53 不同:P46 把它的行寫進 p46-debug-events.log,
# 而那正是 marker 等待所讀的檔案。
export TEST_TITLE="P46 parity views"
export TEST_LOG_NAME="p46-debug-events.log"
export TEST_MARKER="RENDER COMPLETE"
export TEST_TARGET="mac"
exec zsh "$support_dir/test_common.zsh" "$@"
